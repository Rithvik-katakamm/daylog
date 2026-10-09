import SwiftUI

enum Theme {
    static let accent = Color(red: 0.36, green: 0.96, blue: 0.78)      // neon mint: your claims
    static let text = Color.white.opacity(0.92)
    static let muted = Color.white.opacity(0.45)
    static let faint = Color.white.opacity(0.08)

}

// MARK: - The panel

struct PanelView: View {
    @ObservedObject var store: Store
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            timerCard
            inputArea
            if let msg = store.serverDown ? "Server not reachable on 127.0.0.1:7878" : store.error {
                Text(msg).font(.caption).foregroundStyle(.red.opacity(0.85))
            }
        }
        .padding(14)
        .frame(width: AppDelegate.panelSize.width, height: AppDelegate.panelSize.height, alignment: .top)
        .background(.ultraThinMaterial)
        .background(Color.black.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.1)))
        .environment(\.colorScheme, .dark)
        .onChange(of: store.focusRequest) { inputFocused = true }
        .onAppear { inputFocused = true }
    }

    private var header: some View {
        HStack {
            Text("daylog").font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundStyle(Theme.text)
            Spacer()
            if let s = store.summary {
                Text("\(Time.minutes(s.trackedMinutes)) logged · \(Time.minutes(s.computerActiveMinutes)) on Mac")
                    .font(.system(size: 11)).foregroundStyle(Theme.muted)
            }
        }
    }

    @ViewBuilder private var timerCard: some View {
        if let t = store.timer {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("NOW").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.accent)
                    Text(t.label).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.text).lineLimit(2)
                }
                Spacer()
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    Text(Time.duration(ctx.date.timeIntervalSince(Time.parse(t.start)), withSeconds: true))
                        .font(.system(size: 20, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.text)
                }
                Button(action: store.stop) {
                    Image(systemName: "stop.fill").font(.system(size: 12))
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Color.white.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .help("Stop timer")
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.accent.opacity(0.08)))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.accent.opacity(0.35)))
        } else {
            Text("Nothing running").font(.system(size: 12)).foregroundStyle(Theme.muted)
        }
    }

    private var inputArea: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField(store.timer == nil ? "What are you doing?" : "Switch to…, or log something: “client call 3:10-3:25”",
                      text: $store.input)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .padding(.horizontal, 10).padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.07)))
                .focused($inputFocused)
                .onSubmit { store.submit() }
            hint
        }
    }

    @ViewBuilder private var hint: some View {
        HStack(spacing: 6) {
            if let flash = store.flash {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent)
                Text("Logged \(flash)").foregroundStyle(Theme.text)
            } else if let p = store.preview, p.action == "log", let d = store.describe(p) {
                Text("↳ log").foregroundStyle(Theme.accent).fontWeight(.semibold)
                Text(d).foregroundStyle(Theme.text)
                Spacer()
                Text("⏎ log · ⇧⏎ timer").foregroundStyle(Theme.muted)
            } else if !store.input.trimmingCharacters(in: .whitespaces).isEmpty {
                Text(store.timer == nil ? "⏎ start timer" : "⏎ switch timer").foregroundStyle(Theme.muted)
                Spacer()
                Text("add a time to log instead: 15m · 3:10-3:25 · since 2pm").foregroundStyle(Theme.muted)
            } else {
                Text("type what you’re doing · add a time to log something past").foregroundStyle(Theme.muted)
            }
        }
        .font(.system(size: 11))
        .lineLimit(1)
        .padding(.horizontal, 2)
    }
}

struct Chip: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(Color.white.opacity(configuration.isPressed ? 0.2 : 0.1)))
            .foregroundStyle(Theme.text)
    }
}
