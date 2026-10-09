import SwiftUI

/// Visual language borrowed from Wispr Flow's Flow Bar: solid black capsules floating at
/// the bottom-center of the screen, no window chrome, shapes that grow and morph rather
/// than windows that open.
enum Theme {
    static let accent = Color(red: 0.36, green: 0.96, blue: 0.78)  // neon mint: a running timer
    static let chrome = Color.black.opacity(0.92)
    static let edge = Color.white.opacity(0.09)
    static let text = Color.white.opacity(0.94)
    static let muted = Color.white.opacity(0.48)

    static let open = Animation.spring(response: 0.32, dampingFraction: 0.8)
    static let barSize = CGSize(width: 560, height: 50)
    static let restSize = CGSize(width: 84, height: 30)  // what the bar grows out of
}

struct BarView: View {
    @ObservedObject var store: Store
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 8) {
            Spacer(minLength: 0)
            hintChip
                .opacity(store.isOpen ? 1 : 0)
                .offset(y: store.isOpen ? 0 : 10)
                .animation(Theme.open.delay(store.isOpen ? 0.06 : 0), value: store.isOpen)
            bar
        }
        .frame(width: AppDelegate.windowSize.width, height: AppDelegate.windowSize.height, alignment: .bottom)
        .environment(\.colorScheme, .dark)
        .onChange(of: store.focusRequest) { inputFocused = true }
    }

    // MARK: the bar

    private var bar: some View {
        let size = store.isOpen ? Theme.barSize : Theme.restSize
        return HStack(spacing: 10) {
            if let t = store.timer { timerChip(t) }
            TextField("", text: $store.input,
                      prompt: Text(store.timer == nil ? "What are you doing?" : "Switch, or log: client call 3:10-3:25")
                        .foregroundStyle(Theme.muted))
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .foregroundStyle(Theme.text)
                .focused($inputFocused)
                .onSubmit { store.submit() }
        }
        .padding(.horizontal, 16)
        .opacity(store.isOpen ? 1 : 0)
        .frame(width: size.width, height: size.height)
        .background(Capsule().fill(Theme.chrome))
        .overlay(Capsule().strokeBorder(Theme.edge, lineWidth: 1))
        .shadow(color: .black.opacity(store.isOpen ? 0.45 : 0), radius: 22, y: 8)
        .scaleEffect(store.isOpen ? 1 : 0.85, anchor: .bottom)
        .opacity(store.isOpen ? 1 : 0)
        .animation(Theme.open, value: store.isOpen)
    }

    private func timerChip(_ t: TimerInfo) -> some View {
        HStack(spacing: 7) {
            Circle().fill(Theme.accent).frame(width: 7, height: 7)
                .shadow(color: Theme.accent, radius: 3)
            Text(t.label).lineLimit(1).truncationMode(.tail).frame(maxWidth: 170, alignment: .leading)
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                Text(Time.duration(ctx.date.timeIntervalSince(Time.parse(t.start)), withSeconds: true))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.accent)
            }
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(Theme.text)
        .padding(.horizontal, 10).frame(height: 30)
        .background(Capsule().fill(Theme.accent.opacity(0.13)))
        .help("Running. ⌘. stops it")
    }

    // MARK: the floating chip above the bar

    private var hintChip: some View {
        HStack(spacing: 6) { hintContent }
            .font(.system(size: 12))
            .lineLimit(1)
            .padding(.horizontal, 12).frame(height: 26)
            .background(Capsule().fill(Theme.chrome))
            .overlay(Capsule().strokeBorder(Theme.edge, lineWidth: 1))
            .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
            .animation(.easeOut(duration: 0.12), value: store.preview)
    }

    @ViewBuilder private var hintContent: some View {
        let typed = !store.input.trimmingCharacters(in: .whitespaces).isEmpty
        if store.serverDown {
            Circle().fill(.red).frame(width: 6, height: 6)
            Text("daylog server isn’t running").foregroundStyle(Theme.text)
        } else if let flash = store.flash {
            Image(systemName: "checkmark").foregroundStyle(Theme.accent).fontWeight(.bold)
            Text("Logged \(flash)").foregroundStyle(Theme.text)
        } else if let err = store.error {
            Text(err).foregroundStyle(.red.opacity(0.9))
        } else if typed, let p = store.preview, p.action == "log", let d = store.describe(p) {
            Text("log").foregroundStyle(Theme.accent).fontWeight(.semibold)
            Text(d).foregroundStyle(Theme.text)
            Text("⏎").foregroundStyle(Theme.muted)
        } else if typed {
            Text(store.timer == nil ? "⏎ start timer" : "⏎ switch timer").foregroundStyle(Theme.text)
            Text("· add 15m or 3:10-3:25 to log past time").foregroundStyle(Theme.muted)
        } else if let s = store.summary {
            Text("today").foregroundStyle(Theme.muted)
            Text("\(Time.minutes(s.trackedMinutes)) logged").foregroundStyle(Theme.text)
            if store.timer != nil { Text("· ⌘. stop").foregroundStyle(Theme.muted) }
        } else {
            Text("what are you doing?").foregroundStyle(Theme.muted)
        }
    }
}
