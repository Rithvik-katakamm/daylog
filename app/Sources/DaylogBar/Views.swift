import SwiftUI

/// Visual language borrowed from Wispr Flow's Flow Bar: solid black capsules floating at
/// the bottom-center of the screen, no window chrome, shapes that grow and morph rather
/// than windows that open.
enum Theme {
    // Source of truth: docs/ui/colors.md. Three dimensions:
    // 1. WHAT am I doing (main ring)  2. HOW am I (heat + outer rings)  3. WHAT am I typing.
    static let idle = hex(0x6B7280)        // 1: nothing running
    static let task = hex(0xECEEF2)        // 1: a task, pearl white (heats up with focus)
    static let ghost = hex(0xB87AFF)       // 1: ghost, off the clock
    static let focusHeat = [task, hex(0xFFD652), hex(0xFF9A3C), hex(0xFF4D4D)]  // 2: ▲ yellow ▲▲ orange ▲▲▲ red
    static let intoxicated = hex(0xFF6FA5) // 2: outer ring
    static let high = hex(0x7CFF6B)        // 2: outer ring
    static let note = hex(0x8CC2FF)        // 3: typing a note
    static let past = hex(0xC9CED6)        // 3: looking back / editing / filling (dashed ring)
    static let meeting = hex(0x7A8CFF)     // a Wispr meeting when looking back
    static let chrome = Color(white: 0.035)  // solid, like Wispr: nothing bleeds through
    static let edge = Color.white.opacity(0.09)
    static let text = Color.white.opacity(0.94)
    static let muted = Color.white.opacity(0.48)

    /// The task color for a focus tier: pearl, then heating up to red.
    static func taskColor(focus: Int) -> Color { focusHeat[max(0, min(focus, 3))] }

    static func hex(_ v: UInt32) -> Color {
        Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255,
              blue: Double(v & 0xFF) / 255)
    }

    static let open = Animation.spring(response: 0.32, dampingFraction: 0.8)
    static let barSize = CGSize(width: 560, height: 50)
    static let restSize = CGSize(width: 84, height: 30)  // what the bar grows out of
}

struct BarView: View {
    @ObservedObject var store: Store
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 6) {
            if store.env == .dev { devTag }
            bar
            Group {
                if store.mode == .menu { menuList } else { hintChip }
            }
            .opacity(store.isOpen ? 1 : 0)
            .offset(y: store.isOpen ? 0 : -10)
            .animation(Theme.open.delay(store.isOpen ? 0.06 : 0), value: store.isOpen)
            Spacer(minLength: 0)
        }
        .frame(width: AppDelegate.windowSize.width,
               height: store.mode == .menu ? AppDelegate.menuWindowSize.height : AppDelegate.windowSize.height,
               alignment: .top)
        .environment(\.colorScheme, .dark)
        .onChange(of: store.focusRequest) { inputFocused = true }
        // Each mode swaps in a new field; give it the keyboard straight away.
        .onChange(of: store.mode) { DispatchQueue.main.async { inputFocused = true } }
    }

    // MARK: dev tag (⌥D): same colors, but nothing here touches the real log

    private var devTag: some View {
        HStack(spacing: 6) {
            Text("DEV").font(.system(size: 10, weight: .heavy, design: .monospaced))
            Text("testing · nothing is logged").font(.system(size: 10))
                .foregroundStyle(Theme.muted)
        }
        .foregroundStyle(Theme.text)
        .padding(.horizontal, 10).frame(height: 20)
        .background(Capsule().fill(Theme.chrome))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
        .opacity(store.isOpen ? 1 : 0)
    }

    // MARK: the bar

    private var bar: some View {
        let size = store.isOpen ? Theme.barSize : Theme.restSize
        // One input line; the ring says which mode you're in.
        let ring: Color = switch store.mode {
            case .input:
                store.ghost != nil ? Theme.ghost
                    : store.timer != nil ? Theme.taskColor(focus: store.timer?.focus ?? 0) : Theme.idle
            case .note: Theme.note
            case .ghost: Theme.ghost
            case .browse, .fill, .edit: Theme.past
            case .menu: Theme.task
        }
        let dashed = [.browse, .fill, .edit].contains(store.mode)  // the past is dashed
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
            case .menu:
                HStack(spacing: 10) {
                    Text("⌘K").font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.text)
                        .padding(.horizontal, 9).frame(height: 26)
                        .background(Capsule().fill(Color.white.opacity(0.1)))
                    field("Type a command… (↑↓ ⏎, esc)")
                }
            case .edit:
                HStack(spacing: 10) {
                    if let t = store.editTarget {
                        HStack(spacing: 5) {
                            Text(Time.clockString(t.start))
                            Text("–")
                            Text(Time.clockString(store.editEnd)).fontWeight(.bold)
                            Text("· " + Time.duration(store.editEnd.timeIntervalSince(t.start)))
                        }
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.past)
                        .padding(.horizontal, 10).frame(height: 30)
                        .background(Capsule().fill(Theme.past.opacity(0.13)))
                        .animation(.easeOut(duration: 0.1), value: store.editEnd)
                    }
                    field("Title")
                }
            case .fill:
                HStack(spacing: 10) {
                    if let gap = store.fillItem {
                        Text(gap.range)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Theme.past)
                            .padding(.horizontal, 10).frame(height: 30)
                            .background(Capsule().fill(Theme.past.opacity(0.13)))
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
        .overlay(Capsule().strokeBorder(ring.opacity(0.85), style: StrokeStyle(
            lineWidth: 1.5 + CGFloat(focusTier) * 0.5, dash: dashed ? [6, 4] : [])))
        // Focus glows: the deeper you are, the brighter the ring.
        .shadow(color: ring.opacity(0.18 + Double(focusTier) * 0.14), radius: 10 + CGFloat(focusTier) * 7)
        .animation(.easeInOut(duration: 0.35), value: focusTier)
        .shadow(color: .black.opacity(store.isOpen ? 0.45 : 0), radius: 22, y: 8)
        .animation(.easeOut(duration: 0.15), value: store.mode)
        .scaleEffect(store.isOpen ? 1 : 0.85, anchor: .top)
        .opacity(store.isOpen ? 1 : 0)
        .animation(Theme.open, value: store.isOpen)
    }

    private var focusTier: Int { store.mode == .input && store.ghost == nil ? (store.timer?.focus ?? 0) : 0 }

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
            : item.isNote ? Theme.note : item.kind == "ghost" ? Theme.ghost
            : Theme.taskColor(focus: item.focusPeak ?? 0)
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
            if let f = item.focusPeak, f > 0 {
                Text(String(repeating: "▲", count: f))
                    .font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.taskColor(focus: f))
            }
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
        let tint = Theme.taskColor(focus: t.focus ?? 0)
        return HStack(spacing: 7) {
            Circle().fill(tint).frame(width: 7, height: 7)
                .shadow(color: tint, radius: 3)
            Text(t.label).lineLimit(1).truncationMode(.tail).frame(maxWidth: 170, alignment: .leading)
            if let f = t.focus, f > 0 {
                Text(String(repeating: "▲", count: f))
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(tint)
                    .help(Store.focusNames[f])
            }
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                Text(Time.duration(ctx.date.timeIntervalSince(Time.parse(t.start)), withSeconds: true))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(tint)
            }
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(Theme.text)
        .padding(.horizontal, 10).frame(height: 30)
        .background(Capsule().fill(tint.opacity(0.13)))
        .help("Running. ⌘. stops it")
    }

    // MARK: the command menu (⌘K / "/"): every command, grouped, with its shortcut

    private var menuList: some View {
        let items = store.menuItems
        return VStack(alignment: .leading, spacing: 1) {
            if items.isEmpty {
                Text("No matching command").font(.system(size: 12)).foregroundStyle(Theme.muted)
                    .padding(.horizontal, 12).padding(.vertical, 8)
            }
            ForEach(Array(items.enumerated()), id: \.element.id) { i, cmd in
                if i == 0 || items[i - 1].group != cmd.group {
                    Text(cmd.group.rawValue)
                        .font(.system(size: 9, weight: .bold)).tracking(1.2)
                        .foregroundStyle(Theme.muted)
                        .padding(.horizontal, 12).padding(.top, i == 0 ? 4 : 8).padding(.bottom, 2)
                }
                HStack {
                    Text(cmd.title).font(.system(size: 13)).foregroundStyle(Theme.text)
                    Spacer()
                    Text(cmd.shortcut).font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.muted)
                }
                .padding(.horizontal, 12).frame(height: 28)
                .background(RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(i == store.menuIndex ? 0.1 : 0)))
                .contentShape(Rectangle())
                .onTapGesture { store.menuIndex = i; store.runSelectedCommand() }
            }
        }
        .padding(8)
        .frame(width: Theme.barSize.width - 40)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.chrome))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.edge, lineWidth: 1))
        .shadow(color: .black.opacity(0.4), radius: 18, y: 6)
        .animation(.easeOut(duration: 0.1), value: store.menuIndex)
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
            Image(systemName: "checkmark").foregroundStyle(Theme.text).fontWeight(.bold)
            Text(flash).foregroundStyle(Theme.text)
        } else if let err = store.error {
            Text(err).foregroundStyle(.red.opacity(0.9))
        } else if store.mode == .ghost {
            Text("⏎ go ghost").foregroundStyle(Theme.text)
            Text("· stops your timer · logs nothing until you’re back · esc").foregroundStyle(Theme.muted)
        } else if store.mode == .note {
            Text("⏎ save note").foregroundStyle(Theme.text)
            Text(store.timer == nil ? "· esc back" : "· your timer keeps running · esc back").foregroundStyle(Theme.muted)
        } else if store.mode == .edit {
            Text("↓↑ move the end · ⇧ 15m").foregroundStyle(Theme.text)
            Text("· edit the title · ⏎ save · esc cancel").foregroundStyle(Theme.muted)
        } else if store.mode == .fill {
            Text("⏎ log it").foregroundStyle(Theme.text)
            Text("· esc back").foregroundStyle(Theme.muted)
        } else if store.mode == .browse, let item = store.current {
            Text(item.startDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                .foregroundStyle(Theme.past)
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
            Text("log").foregroundStyle(Theme.task).fontWeight(.semibold)
            Text(d).foregroundStyle(Theme.text)
            Text("⏎").foregroundStyle(Theme.muted)
        } else if typed {
            Text(store.timer == nil ? "⏎ start timer" : "⏎ switch timer").foregroundStyle(Theme.text)
            Text("· add 15m or 3:10-3:25 to log past time").foregroundStyle(Theme.muted)
        } else if let g = store.ghost {
            Text("ghost since \(Time.clockString(Time.parse(g.start)))").foregroundStyle(Theme.ghost)
            Text("· ⌘O back online · or type a task").foregroundStyle(Theme.muted)
        } else {
            if let f = store.timer?.focus, f > 0 {
                Text(Store.focusNames[f]).foregroundStyle(Theme.taskColor(focus: f)).fontWeight(.semibold)
                Text("·").foregroundStyle(Theme.muted)
            }
            Text(store.timer != nil ? "⌘K all commands · ⌘F focus · ↑ look back · ↓ edit · ⌘N note"
                                    : "⌘K all commands · ↑ look back · ↓ edit · ⌘N note · ⌘O ghost").foregroundStyle(Theme.muted)
            if store.timer != nil { Text("· ⌘. stop").foregroundStyle(Theme.muted) }
        }
    }
}
