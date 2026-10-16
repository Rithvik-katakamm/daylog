import AppKit
import SwiftUI

/// Demo window (⌘K → Demo): see the pill in every state, watch the model read lines live, and try a
/// line. Read-only: the pill states are made up on screen (nothing is written), and the model views
/// only read from the server.
@MainActor
final class DemoWindow {
    private static var window: NSWindow?

    static func show(store: Store) {
        if let w = window { w.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 600),
                         styleMask: [.titled, .closable, .resizable, .miniaturizable],
                         backing: .buffered, defer: false)
        w.title = "Day Log prototype · demo"
        w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(rootView: DemoView(store: store))
        w.center()
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = w
    }
}

/// What the model is doing (GET /harness on the Dev server).
struct HarnessActivity: Decodable {
    struct Busy: Decodable { let text: String; let since: String }
    struct Reading: Decodable, Identifiable {
        let at: String
        let text: String
        let ms: Int
        let model: String
        let why: String
        let mode: String?
        let kept: Bool
        let did: String
        let overruled: Bool
        var applied: Bool? = nil
        var id: String { at + text }
    }
    let model: String
    let busy: Busy?
    let recent: [Reading]
}

struct DemoView: View {
    @ObservedObject var store: Store
    @State private var activity: HarnessActivity?
    @State private var tryText = ""
    @State private var tryResult: LinePreview?
    @State private var tryBusy = false
    @State private var touring = false

    private static func ago(_ minutes: Double) -> String { Time.string(Date().addingTimeInterval(-minutes * 60)) }

    /// Each pill state, made up on screen: (name, timer, ghost, break, substances).
    private static let states: [(String, TimerInfo?, GhostInfo?, BreakInfo?, Set<String>)] = [
        ("Idle", nil, nil, nil, []),
        ("Task", TimerInfo(id: "d", label: "working on daylog backend", start: ago(42)), nil, nil, []),
        ("Focus ▲", TimerInfo(id: "d", label: "working on daylog backend", start: ago(42), focus: 1), nil, nil, []),
        ("Deep ▲▲", TimerInfo(id: "d", label: "working on daylog backend", start: ago(42), focus: 2), nil, nil, []),
        ("Hyper ▲▲▲", TimerInfo(id: "d", label: "working on daylog backend", start: ago(42), focus: 3), nil, nil, []),
        ("Long title", TimerInfo(id: "d", label: "daylog backend + the harness and brain global config", start: ago(95)), nil, nil, []),
        ("Walk", nil, nil, BreakInfo(id: "d", kind: "walk", label: "walk", start: ago(6), resume: "working on daylog"), []),
        ("Smoke", nil, nil, BreakInfo(id: "d", kind: "smoke", label: "smoke break", start: ago(4), resume: "working on daylog"), []),
        ("Ghost", nil, GhostInfo(id: "d", status: "watching code geass", start: ago(70)), nil, []),
        ("High", TimerInfo(id: "d", label: "working on daylog", start: ago(30)), nil, nil, ["high"]),
        ("Drunk", TimerInfo(id: "d", label: "working on daylog", start: ago(30)), nil, nil, ["intoxicated"]),
        ("Coffee", TimerInfo(id: "d", label: "working on daylog", start: ago(30)), nil, nil, ["caffeinated"]),
        ("All rings", TimerInfo(id: "d", label: "working on daylog", start: ago(30), focus: 2), nil, nil,
         ["high", "intoxicated", "caffeinated"]),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            pillSection
            Divider()
            modelSection
            Divider()
            trySection
        }
        .padding(20)
        .frame(minWidth: 560, minHeight: 540, alignment: .topLeading)
        .task { await poll() }
        .onDisappear { store.endDemo() }
    }

    // MARK: pill states

    private var pillSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Pill states").font(.headline)
                Text(store.demoState.map { "showing: \($0) (made up, nothing logged)" } ?? "showing: your real state")
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("Pill on", selection: Binding(
                    get: { store.restStyle == .off ? "off" : store.pillScreen.rawValue },
                    set: { v in
                        if v == "off" { store.restStyle = .off }
                        else { store.restStyle = .pill; store.pillScreen = Store.PillScreen(rawValue: v) ?? .follow }
                    })) {
                    Text("Hidden").tag("off")
                    Text("MacBook").tag("laptop")
                    Text("Monitor").tag("monitor")
                    Text("Follow cursor").tag("follow")
                }
                .pickerStyle(.segmented).frame(width: 330)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                ForEach(Self.states, id: \.0) { s in
                    Button(s.0) { show(s) }.disabled(touring)
                }
            }
            HStack {
                Button(touring ? "Touring…" : "Tour every state (3 s each)") { Task { await tour() } }.disabled(touring)
                Button("Back to my real state") { store.endDemo() }.disabled(store.demoState == nil || touring)
                Text("Made up on screen only; your log is untouched.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func show(_ s: (String, TimerInfo?, GhostInfo?, BreakInfo?, Set<String>)) {
        store.showDemo(s.0, timer: s.1, ghost: s.2, onBreak: s.3, states: s.4)
    }

    private func tour() async {
        touring = true
        if store.restStyle == .off { store.restStyle = .pill }
        for s in Self.states {
            show(s)
            try? await Task.sleep(for: .seconds(3))
        }
        touring = false
        store.endDemo()
    }

    // MARK: the model, live

    private var modelSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("The model, live").font(.headline)
                Text(activity?.model ?? "server not answering").foregroundStyle(.secondary)
                Spacer()
                if let b = activity?.busy {
                    ProgressView().controlSize(.small)
                    Text("reading “\(b.text)” · \(Self.elapsed(since: b.since))").lineLimit(1).truncationMode(.middle)
                } else {
                    Circle().fill(.secondary).frame(width: 7, height: 7)
                    Text("idle").foregroundStyle(.secondary)
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if activity?.recent.isEmpty ?? true {
                        Text("Nothing read yet. Type in the bar (⌥L) or try a line below.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(activity?.recent ?? []) { r in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text("“\(r.text)”").fontWeight(.medium).lineLimit(1)
                                Spacer()
                                Text("\(r.ms) ms").monospacedDigit().foregroundStyle(.secondary)
                            }
                            HStack(spacing: 6) {
                                Text("→ \(r.did)")
                                if r.overruled { Text("· code overruled the model (\(r.mode ?? "?"))").foregroundStyle(.orange) }
                                if r.applied == true { Text("· applied").foregroundStyle(.green) }
                            }
                            .font(.callout)
                            if !r.why.isEmpty { Text("why: \(r.why)").font(.callout).foregroundStyle(.secondary).italic() }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 160)
        }
    }

    private func poll() async {
        while !Task.isCancelled {
            activity = try? await API.get("harness")
            try? await Task.sleep(for: .milliseconds(500))
        }
    }

    private static func elapsed(since iso: String) -> String {
        String(format: "%.1f s", Date().timeIntervalSince(Time.parse(iso)))
    }

    // MARK: try a line

    private var trySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Try a line (preview only, nothing is logged)").font(.headline)
            HStack {
                TextField("e.g. took a nap now deep in the harness", text: $tryText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await tryLine() } }
                Button("Read it") { Task { await tryLine() } }.disabled(tryText.isEmpty || tryBusy)
            }
            if tryBusy { Text("reading…").italic().foregroundStyle(.secondary) }
            if let r = tryResult {
                Text(r.action == "none" ? "→ the rules handle it (\(r.why ?? "no reading"))" : "→ \(r.label)")
                    .fontWeight(.medium)
                if let why = r.why, r.action != "none" { Text("why: \(why)").italic().foregroundStyle(.secondary) }
            }
        }
    }

    private func tryLine() async {
        tryBusy = true
        tryResult = try? await API.get("read", query: ["text": tryText], slow: true)
        tryBusy = false
    }
}
