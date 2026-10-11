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
    static let caffeinated = hex(0x5CE1E6) // 2: outer ring (aqua: kept clear of the focus heat)
    static let away = hex(0x8FA3B8)        // 1: on a break (⌘B walk / ⌘⇧B smoke)
    static let note = hex(0x8CC2FF)        // 3: typing a note
    static let past = hex(0xC9CED6)        // 3: looking back / editing / filling (dashed ring)
    static let meeting = hex(0x7A8CFF)     // a Wispr meeting when looking back
    static let chrome = Color(white: 0.035)  // solid, like Wispr: nothing bleeds through
    static let edge = Color.white.opacity(0.09)
    static let text = Color.white.opacity(0.94)
    static let muted = Color.white.opacity(0.48)

    /// The task color for a focus tier: pearl, then heating up to red.
    static func taskColor(focus: Int) -> Color { focusHeat[max(0, min(focus, 3))] }

    /// Substance rings, innermost first. Order is fixed so the rings never shuffle.
    static let stateOrder: [(name: String, color: Color)] =
        [("high", high), ("intoxicated", intoxicated), ("caffeinated", caffeinated)]
    static func stateColors(_ on: Set<String>) -> [Color] { stateOrder.filter { on.contains($0.name) }.map(\.color) }

    /// Dimension 1 for what's going on right now (used by the bar, the pill and the side ring).
    @MainActor static func statusColor(_ s: Store) -> Color {
        s.onBreak != nil ? away : s.ghost != nil ? ghost
            : s.timer != nil ? taskColor(focus: s.timer?.focus ?? 0) : idle
    }

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
            ZStack(alignment: .top) {
                // Closed: the dimmed pill stays (if on). Opening fades it as the bar grows out of it.
                if store.showsPill {
                    RestPill(store: store)
                        .padding(.top, 3)
                        .opacity(store.isOpen ? 0 : 1)
                        .scaleEffect(store.isOpen ? 1.2 : 1, anchor: .top)
                        .animation(Theme.open, value: store.isOpen)
                }
                bar
            }
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
            case .input: Theme.statusColor(store)
            case .note: Theme.note
            case .ghost: Theme.ghost
            case .browse, .fill, .edit: Theme.past
            case .menu: Theme.task
        }
        let dashed = [.browse, .fill, .edit].contains(store.mode)  // the past is dashed
        return ZStack {
            // Looking back shows one stop at a time instead of the input line.
            if store.mode == .browse, let item = store.current {
                stop(item)
                    .id(item.key)
                    .transition(.asymmetric(
                        insertion: .move(edge: store.movedOlder ? .top : .bottom).combined(with: .opacity),
                        removal: .move(edge: store.movedOlder ? .bottom : .top).combined(with: .opacity)))
            }
            // ONE text field for every mode. Only the chip and the prompt change, so the field
            // never gets rebuilt and keyboard focus can't get lost on a fast mode switch.
            HStack(spacing: 10) {
                leadingChip
                field(prompt)
            }
            .opacity(store.mode == .browse ? 0 : 1)
            .allowsHitTesting(store.mode != .browse)
        }
        .animation(.spring(response: 0.26, dampingFraction: 0.86), value: store.index)
        .padding(.horizontal, 16)
        .opacity(store.isOpen ? 1 : 0)
        .frame(width: size.width, height: size.height)
        .clipShape(Capsule())
        .background(Capsule().fill(Theme.chrome))
        .overlay(Capsule().strokeBorder(ring.opacity(0.85), style: StrokeStyle(
            lineWidth: 1.5 + CGFloat(focusTier) * 0.5, dash: dashed ? [6, 4] : [])))
        // Substances: outer rings that stack outside the main ring (high, intoxicated, caffeinated).
        .overlay(OuterRings(colors: Theme.stateColors(store.states), shape: Capsule(), opacity: 0.8)
            .opacity(store.isOpen ? 1 : 0))
        // Focus glows: the deeper you are, the brighter the ring.
        .shadow(color: ring.opacity(0.18 + Double(focusTier) * 0.14), radius: 10 + CGFloat(focusTier) * 7)
        .animation(.easeInOut(duration: 0.35), value: focusTier)
        .shadow(color: .black.opacity(store.isOpen ? 0.45 : 0), radius: 22, y: 8)
        .animation(.easeOut(duration: 0.15), value: store.mode)
        .scaleEffect(store.isOpen ? 1 : 0.85, anchor: .top)
        .opacity(store.isOpen ? 1 : 0)
        .animation(Theme.open, value: store.isOpen)
    }

    /// What the single input line asks for, per mode.
    private var prompt: String {
        switch store.mode {
        case .input:
            store.onBreak != nil ? "On a \(store.onBreak!.label) · ⌘B when you're back"
                : store.ghost != nil ? "Type a task to come back"
                : store.timer == nil ? "What are you doing?" : "Switch, or log: client call 3:10-3:25"
        case .note: "What’s on your mind?"
        case .ghost: "Status (optional): dinner with family, deep reset…"
        case .menu: "Type a command… (↑↓ ⏎, esc)"
        case .edit: "Title"
        case .fill: "What were you doing then?"
        case .browse: ""
        }
    }

    /// The chip to the left of the input line: what mode you're in, or what's running.
    @ViewBuilder private var leadingChip: some View {
        switch store.mode {
        case .input:
            if let b = store.onBreak { breakChip(b) }
            else if let g = store.ghost { ghostChip(g) } else if let t = store.timer { timerChip(t) }
        case .note:
            HStack(spacing: 6) {
                Image(systemName: "note.text")
                Text(store.timer.map { "note · \($0.label)" } ?? "note")
                    .lineLimit(1).truncationMode(.tail).frame(maxWidth: 170, alignment: .leading)
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Theme.note)
            .padding(.horizontal, 10).frame(height: 30)
            .background(Capsule().fill(Theme.note.opacity(0.13)))
        case .ghost:
            HStack(spacing: 6) {
                Image(systemName: "moon.zzz.fill")
                Text("ghost")
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Theme.ghost)
            .padding(.horizontal, 10).frame(height: 30)
            .background(Capsule().fill(Theme.ghost.opacity(0.14)))
        case .menu:
            Text("⌘K").font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 9).frame(height: 26)
                .background(Capsule().fill(Color.white.opacity(0.1)))
        case .edit:
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
        case .fill:
            if let gap = store.fillItem {
                Text(gap.range)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.past)
                    .padding(.horizontal, 10).frame(height: 30)
                    .background(Capsule().fill(Theme.past.opacity(0.13)))
            }
        case .browse:
            EmptyView()
        }
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
            : item.isNote ? Theme.note : item.kind == "ghost" ? Theme.ghost : item.kind == "break" ? Theme.away
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

    private func breakChip(_ b: BreakInfo) -> some View {
        HStack(spacing: 7) {
            Image(systemName: b.kind == "smoke" ? "smoke.fill" : "figure.walk").font(.system(size: 10))
            Text(b.label)
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                Text(Time.duration(ctx.date.timeIntervalSince(Time.parse(b.start)), withSeconds: true))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
            }
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(Theme.away)
        .padding(.horizontal, 10).frame(height: 30)
        .background(Capsule().fill(Theme.away.opacity(0.14)))
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
        } else if let b = store.onBreak {
            Text("⌘B back").foregroundStyle(Theme.text)
            Text(b.resume.map { "· resumes “\($0)”" } ?? "· nothing to resume").foregroundStyle(Theme.muted).lineLimit(1)
            if b.kind == "smoke" { Text("· comes back high").foregroundStyle(Theme.high) }
        } else if let g = store.ghost, let r = g.resume {
            Text("⌘B back").foregroundStyle(Theme.text)
            Text("· resumes “\(r)” · gone since \(Time.clockString(Time.parse(g.start)))").foregroundStyle(Theme.muted).lineLimit(1)
        } else if let g = store.ghost {
            Text("ghost since \(Time.clockString(Time.parse(g.start)))").foregroundStyle(Theme.ghost)
            Text("· ⌘O back online · or type a task").foregroundStyle(Theme.muted)
        } else {
            if let f = store.timer?.focus, f > 0 {
                Text(Store.focusNames[f]).foregroundStyle(Theme.taskColor(focus: f)).fontWeight(.semibold)
                Text("·").foregroundStyle(Theme.muted)
            }
            Text(store.timer != nil ? "⌘K all commands · ⌘F focus · ⌘B break · ↑ look back · ⌘N note"
                                    : "⌘K all commands · ↑ look back · ↓ edit · ⌘N note · ⌘O ghost").foregroundStyle(Theme.muted)
            if store.timer != nil { Text("· ⌘. stop").foregroundStyle(Theme.muted) }
        }
    }
}

// MARK: - substances: one blended glow outside the main ring

/// Substances as a single soft halo, not separate lines (his call, Oct 11: "a blend and glow").
/// Several at once blend around the shape (high's green flowing into caffeinated's aqua);
/// one alone is a plain colored glow. The crisp main ring stays the task/focus.
struct OuterRings<S: InsettableShape>: View {
    let colors: [Color]
    let shape: S
    var opacity: Double = 0.8
    var spacing: CGFloat = 3.5

    var body: some View {
        if colors.isEmpty { EmptyView() } else {
            let style: AnyShapeStyle = colors.count == 1 ? AnyShapeStyle(colors[0])
                : AnyShapeStyle(AngularGradient(colors: colors + [colors[0]], center: .center))
            ZStack {
                // A wide, very soft aura…
                shape.inset(by: -spacing * 1.6).stroke(style, lineWidth: spacing * 2.6)
                    .blur(radius: spacing * 2.6).opacity(opacity * 0.6)
                // …and a tighter bright edge, still blurred so it never reads as a line.
                shape.inset(by: -spacing * 0.6).stroke(style, lineWidth: spacing * 0.9)
                    .blur(radius: spacing * 0.9).opacity(opacity)
            }
            .allowsHitTesting(false)
        }
    }
}

/// A slow breath for glows while the bar is closed: focus and substances feel "on" without
/// moving anything. Core Animation runs it, so it costs nothing per frame on our side.
struct Breathing: ViewModifier {
    let active: Bool
    @State private var phase = false
    func body(content: Content) -> some View {
        content
            .opacity(active ? (phase ? 1 : 0.55) : 0.8)
            .onAppear { withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) { phase = true } }
    }
}

// MARK: - always-on, while the bar is closed (Oct 11: try both, then pick)

/// Center pill: a dimmed, smaller version of the bar showing what you're on and for how long.
/// The bar grows out of this same spot when you open it.
struct RestPill: View {
    @ObservedObject var store: Store

    var body: some View {
        let color = Theme.statusColor(store)
        let tier = store.onBreak == nil && store.ghost == nil ? (store.timer?.focus ?? 0) : 0
        let lively = tier > 0 || !store.states.isEmpty
        HStack(spacing: 7) {
            content(color)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(Theme.text.opacity(0.85))
        .lineLimit(1)
        .padding(.horizontal, 11).frame(height: 24)
        .background(Capsule().fill(Theme.chrome.opacity(0.82)))
        .overlay(Capsule().strokeBorder(color.opacity(0.75), lineWidth: 1 + CGFloat(tier) * 0.4))
        .overlay(OuterRings(colors: Theme.stateColors(store.states), shape: Capsule(), opacity: 0.7, spacing: 3))
        .background(Capsule().fill(.clear).shadow(color: color.opacity(lively ? 0.25 + Double(tier) * 0.12 : 0),
                                                   radius: 6 + CGFloat(tier) * 4)
            .modifier(Breathing(active: lively)))
        .opacity(0.6)
        .frame(maxWidth: 300)
    }

    @ViewBuilder private func content(_ color: Color) -> some View {
        if let b = store.onBreak {
            Image(systemName: b.kind == "smoke" ? "smoke.fill" : "figure.walk").foregroundStyle(color)
            Text(b.label)
            elapsed(b.start, color)
        } else if let g = store.ghost {
            Image(systemName: "moon.zzz.fill").foregroundStyle(color)
            Text(g.status).frame(maxWidth: 170, alignment: .leading)
            elapsed(g.start, color)
        } else if let t = store.timer {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(t.label).truncationMode(.tail).frame(maxWidth: 170, alignment: .leading)
            if let f = t.focus, f > 0 {
                Text(String(repeating: "▲", count: f)).font(.system(size: 8, weight: .bold)).foregroundStyle(color)
            }
            elapsed(t.start, color)
        } else {
            Circle().strokeBorder(color, lineWidth: 1).frame(width: 6, height: 6)
            Text("nothing running").foregroundStyle(Theme.muted)
        }
    }

    private func elapsed(_ start: String, _ color: Color) -> some View {
        TimelineView(.periodic(from: .now, by: 30)) { ctx in
            Text(Time.duration(ctx.date.timeIntervalSince(Time.parse(start))))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
        }
    }
}

/// Side ring: just the status as a ring on the screen edge, with substance rings around it
/// and minutes in the middle. Glance, don't read.
struct SideRing: View {
    @ObservedObject var store: Store

    var body: some View {
        let color = Theme.statusColor(store)
        let tier = store.onBreak == nil && store.ghost == nil ? (store.timer?.focus ?? 0) : 0
        let lively = tier > 0 || !store.states.isEmpty
        ZStack {
            OuterRings(colors: Theme.stateColors(store.states), shape: Circle(), opacity: 1, spacing: 4)
            Circle().fill(Theme.chrome.opacity(0.92))
            Circle().strokeBorder(color.opacity(0.9), lineWidth: 2 + CGFloat(tier) * 0.6)
            minutes(color)
        }
        .frame(width: 30, height: 30)
        .background(Circle().fill(.clear).shadow(color: color.opacity(lively ? 0.3 + Double(tier) * 0.12 : 0),
                                                  radius: 6 + CGFloat(tier) * 4)
            .modifier(Breathing(active: lively)))
        .opacity(0.85)
        .frame(width: 96, height: 96)
    }

    @ViewBuilder private func minutes(_ color: Color) -> some View {
        let start = store.onBreak?.start ?? store.ghost?.start ?? store.timer?.start
        if let start {
            TimelineView(.periodic(from: .now, by: 30)) { ctx in
                let m = Int(ctx.date.timeIntervalSince(Time.parse(start)) / 60)
                Text(m >= 60 ? "\(m / 60)h" : "\(m)")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(color)
            }
        }
    }
}
