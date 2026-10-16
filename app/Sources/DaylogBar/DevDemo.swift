import AppKit
import SwiftUI

/// Dev-only demo window (⌘K → "Dev demo"): put the Dev pill into every state, watch the model read
/// lines live, and try a line without logging it. Everything here talks to the Dev server (:7879) and
/// its throwaway database; the real Day Log is never touched.
@MainActor
final class DevDemoWindow {
    private static var window: NSWindow?

    static func show(store: Store) {
        if let w = window { w.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 600),
                         styleMask: [.titled, .closable, .resizable, .miniaturizable],
                         backing: .buffered, defer: false)
        w.title = "Day Log Dev · demo"
        w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(rootView: DevDemoView(store: store))
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

struct DevDemoView: View {
    @ObservedObject var store: Store
    @State private var activity: HarnessActivity?
    @State private var tryText = ""
    @State private var tryResult: LinePreview?
    @State private var tryBusy = false
    @State private var touring = false
    @State private var stateName = "—"

    /// Each pill state: a name, and the Dev-server calls that produce it from a clean slate.
    private static let states: [(String, [(String, [String: Any])])] = [
        ("Idle", []),
        ("Task", [("log", ["text": "working on daylog backend"])]),
        ("Focus ▲", [("log", ["text": "working on daylog backend"]), ("focus", ["tier": 1])]),
        ("Deep ▲▲", [("log", ["text": "working on daylog backend"]), ("focus", ["tier": 2])]),
        ("Hyper ▲▲▲", [("log", ["text": "working on daylog backend"]), ("focus", ["tier": 3])]),
        ("Long title", [("log", ["text": "daylog backend"]), ("log", ["text": "and the harness and brain global config"])]),
        ("Walk", [("log", ["text": "working on daylog"]), ("break", ["kind": "walk"])]),
        ("Smoke", [("log", ["text": "working on daylog"]), ("break", ["kind": "smoke"])]),
        ("Ghost", [("ghost", ["status": "watching code geass"])]),
        ("High", [("log", ["text": "working on daylog"]), ("state", ["state": "high"])]),
        ("Drunk", [("log", ["text": "working on daylog"]), ("state", ["state": "intoxicated"])]),
        ("Coffee", [("log", ["text": "working on daylog"]), ("state", ["state": "caffeinated"])]),
        ("All rings", [("log", ["text": "working on daylog"]), ("state", ["state": "high"]),
                       ("state", ["state": "intoxicated"]), ("state", ["state": "caffeinated"]), ("focus", ["tier": 2])]),
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
    }

    // MARK: pill states

    private var pillSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Pill states").font(.headline)
                Text("now: \(stateName)").foregroundStyle(.secondary)
                Spacer()
                Picker("Show the Dev pill on", selection: Binding(
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
                    Button(s.0) { Task { await show(s) } }.disabled(touring)
                }
            }
            HStack {
                Button(touring ? "Touring…" : "Tour every state (3 s each)") { Task { await tour() } }.disabled(touring)
                Text("The Dev pill and the open Dev bar both follow; nothing real is logged.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func show(_ s: (String, [(String, [String: Any])])) async {
        _ = try? await API.post("dev/reset", env: .dev)
        for (path, body) in s.1 { _ = try? await API.post(path, body.merging(["source": "demo"]) { a, _ in a }, env: .dev) }
        stateName = s.0
        await store.refreshAll()
    }

    private func tour() async {
        touring = true
        if store.restStyle == .off { store.restStyle = .pill }
        for s in Self.states {
            await show(s)
            try? await Task.sleep(for: .seconds(3))
        }
        touring = false
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
                        Text("Nothing read yet. Type in the Dev bar (⌥D) or try a line below.")
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
            activity = try? await API.get("harness", env: .dev)
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
        tryResult = try? await API.get("read", query: ["text": tryText], env: .dev, slow: true)
        tryBusy = false
    }
}
