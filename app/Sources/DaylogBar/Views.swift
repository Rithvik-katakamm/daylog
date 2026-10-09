import SwiftUI

/// Visual language borrowed from Wispr Flow's Flow Bar: solid black capsules floating at
/// the bottom-center of the screen, no window chrome, shapes that grow and morph rather
/// than windows that open.
enum Theme {
    static let accent = Color(red: 0.36, green: 0.96, blue: 0.78)  // neon mint: a running timer
    static let ring = Color(red: 1.0, green: 0.84, blue: 0.32)     // yellow: you're looking at the past
    static let meeting = Color(red: 0.70, green: 0.55, blue: 1.0)  // violet: Wispr meetings
    static let note = Color(red: 0.55, green: 0.76, blue: 1.0)     // soft blue: a thought, not a task
    static let ghost = Color(red: 0.72, green: 0.48, blue: 1.0)    // purple: offline, logging nothing
    static let chrome = Color(white: 0.035)  // solid, like Wispr: nothing bleeds through
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
            bar
            hintChip
                .opacity(store.isOpen ? 1 : 0)
                .offset(y: store.isOpen ? 0 : -10)
                .animation(Theme.open.delay(store.isOpen ? 0.06 : 0), value: store.isOpen)
            Spacer(minLength: 0)
        }
        .frame(width: AppDelegate.windowSize.width, height: AppDelegate.windowSize.height, alignment: .top)
        .environment(\.colorScheme, .dark)
        .onChange(of: store.focusRequest) { inputFocused = true }
    }

    // MARK: the bar

    private var bar: some View {
        let size = store.isOpen ? Theme.barSize : Theme.restSize
        // One input line; the ring says which mode you're in.
        let ring: Color = switch store.mode {
            case .input: store.ghost != nil ? Theme.ghost : Theme.accent  // green: tasks
            case .note: Theme.note
            case .ghost: Theme.ghost
            case .browse, .fill: Theme.ring
        }
        return ZStack {
            switch store.mode {
            case .input:
                HStack(spacing: 10) {
                    if let g = store.ghost { ghostChip(g) } else if let t = store.timer { timerChip(t) }
                    field(store.ghost != nil ? "Type a task to come back"
                          : store.timer == nil ? "What are you doing?" : "Switch, or log: client call 3:10-3:25")
                }
            case .browse:
                if let item = store.current {
                    stop(item)
                        .id(item.key)
                        .transition(.asymmetric(
                            insertion: .move(edge: store.movedOlder ? .top : .bottom).combined(with: .opacity),
                            removal: .move(edge: store.movedOlder ? .bottom : .top).combined(with: .opacity)))
                }
            case .note:
                HStack(spacing: 10) {
                    HStack(spacing: 6) {
                        Image(systemName: "note.text")
                        Text(store.timer.map { "note · \($0.label)" } ?? "note")
                            .lineLimit(1).truncationMode(.tail).frame(maxWidth: 170, alignment: .leading)
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.note)
                    .padding(.horizontal, 10).frame(height: 30)
                    .background(Capsule().fill(Theme.note.opacity(0.13)))
                    field("What’s on your mind?")
                }
            case .ghost:
                HStack(spacing: 10) {
                    HStack(spacing: 6) {
                        Image(systemName: "moon.zzz.fill")
                        Text("ghost")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.ghost)
                    .padding(.horizontal, 10).frame(height: 30)
                    .background(Capsule().fill(Theme.ghost.opacity(0.14)))
                    field("Status (optional): dinner with family, deep reset…")
                }
            case .fill:
                HStack(spacing: 10) {
                    if let gap = store.fillItem {
                        Text(gap.range)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Theme.ring)
                            .padding(.horizontal, 10).frame(height: 30)
                            .background(Capsule().fill(Theme.ring.opacity(0.13)))
                    }
                    field("What were you doing then?")
                }
            }
        }
        .animation(.spring(response: 0.26, dampingFraction: 0.86), value: store.index)
        .padding(.horizontal, 16)
        .opacity(store.isOpen ? 1 : 0)
        .frame(width: size.width, height: size.height)
        .clipShape(Capsule())
        .background(Capsule().fill(Theme.chrome))
        .overlay(Capsule().strokeBorder(ring.opacity(0.85), lineWidth: 1.5))
        .shadow(color: ring.opacity(0.18), radius: 10)
        .shadow(color: .black.opacity(store.isOpen ? 0.45 : 0), radius: 22, y: 8)
        .animation(.easeOut(duration: 0.15), value: store.mode)
        .scaleEffect(store.isOpen ? 1 : 0.85, anchor: .top)
        .opacity(store.isOpen ? 1 : 0)
        .animation(Theme.open, value: store.isOpen)
    }

    private func field(_ prompt: String) -> some View {
        TextField("", text: $store.input, prompt: Text(prompt).foregroundStyle(Theme.muted))
            .textFieldStyle(.plain)
            .font(.system(size: 15))
            .foregroundStyle(Theme.text)
            .focused($inputFocused)
            .onSubmit { store.submit() }
    }

    /// One stop in the past, shown inside the oval.
    private func stop(_ item: HistoryItem) -> some View {
        let color: Color = item.isGap ? Theme.muted : item.kind == "meeting" ? Theme.meeting
            : item.isNote ? Theme.note : item.kind == "ghost" ? Theme.ghost : Theme.accent
        return HStack(spacing: 12) {
            if item.isNote {
                Image(systemName: "note.text").font(.system(size: 11)).foregroundStyle(color)
            } else {
                Circle().fill(item.isGap ? .clear : color).overlay(Circle().strokeBorder(color, lineWidth: 1))
                    .frame(width: 7, height: 7)
            }
            Text(item.isNote ? Time.clockString(item.startDate) : item.range)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.muted)
            Text(item.isGap ? "untracked" : (item.label ?? ""))
                .font(.system(size: 15, weight: item.isGap ? .regular : .medium))
                .italic(item.isGap)
                .foregroundStyle(item.isGap ? Theme.muted : Theme.text)
                .lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 8)
            Text(item.isNote ? "" : Time.minutes(item.minutes))
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(item.isGap ? Theme.muted : Theme.text)
        }
    }

    private func ghostChip(_ g: GhostInfo) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "moon.zzz.fill").font(.system(size: 10))
            Text(g.status).lineLimit(1).truncationMode(.tail).frame(maxWidth: 170, alignment: .leading)
            TimelineView(.periodic(from: .now, by: 30)) { ctx in
                Text(Time.duration(ctx.date.timeIntervalSince(Time.parse(g.start))))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
            }
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(Theme.ghost)
        .padding(.horizontal, 10).frame(height: 30)
        .background(Capsule().fill(Theme.ghost.opacity(0.14)))
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
            Text(flash).foregroundStyle(Theme.text)
        } else if let err = store.error {
            Text(err).foregroundStyle(.red.opacity(0.9))
        } else if store.mode == .ghost {
            Text("⏎ go ghost").foregroundStyle(Theme.text)
            Text("· stops your timer · logs nothing until you’re back · esc").foregroundStyle(Theme.muted)
        } else if store.mode == .note {
            Text("⏎ save note").foregroundStyle(Theme.text)
            Text(store.timer == nil ? "· esc back" : "· your timer keeps running · esc back").foregroundStyle(Theme.muted)
        } else if store.mode == .fill {
            Text("⏎ log it").foregroundStyle(Theme.text)
            Text("· esc back").foregroundStyle(Theme.muted)
        } else if store.mode == .browse, let item = store.current {
            Text(item.startDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                .foregroundStyle(Theme.ring)
            Text("· ↑ earlier  ↓ later").foregroundStyle(Theme.muted)
            switch item.kind {
            case "gap": Text("· ⏎ fill in").foregroundStyle(Theme.text)
            case "meeting": Text("· from Wispr").foregroundStyle(Theme.muted)
            case "ghost": Text("· ghost mode · ⌘⌫ delete").foregroundStyle(Theme.muted)
            case "note":
                if let d = item.during { Text("· during \(d)").foregroundStyle(Theme.muted).lineLimit(1) }
                Text("· ⌘⌫ delete").foregroundStyle(Theme.muted)
            default: Text("· ⌘⌫ delete").foregroundStyle(Theme.muted)
            }
        } else if typed, let p = store.preview, p.action == "log", let d = store.describe(p) {
            Text("log").foregroundStyle(Theme.accent).fontWeight(.semibold)
            Text(d).foregroundStyle(Theme.text)
            Text("⏎").foregroundStyle(Theme.muted)
        } else if typed {
            Text(store.timer == nil ? "⏎ start timer" : "⏎ switch timer").foregroundStyle(Theme.text)
            Text("· add 15m or 3:10-3:25 to log past time").foregroundStyle(Theme.muted)
        } else if let g = store.ghost {
            Text("ghost since \(Time.clockString(Time.parse(g.start)))").foregroundStyle(Theme.ghost)
            Text("· ⌘O back online · or type a task").foregroundStyle(Theme.muted)
        } else {
            if let s = store.summary {
                Text("today").foregroundStyle(Theme.muted)
                Text("\(Time.minutes(s.trackedMinutes)) logged").foregroundStyle(Theme.text)
            }
            Text("· ↑ look back · ⌘N note · ⌘O ghost").foregroundStyle(Theme.muted)
            if store.timer != nil { Text("· ⌘. stop").foregroundStyle(Theme.muted) }
        }
    }
}
