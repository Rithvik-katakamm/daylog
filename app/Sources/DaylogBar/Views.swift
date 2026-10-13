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
    static let high = hex(0x39FF14)        // 2: halo, neon green (brighter, Oct 11)
    static let caffeinated = hex(0xA8754A) // 2: outer ring (coffee brown, Oct 13; was aqua)
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
    static let ear: CGFloat = 100  // width of each side of the closed pill, beside the notch
    /// Monitor (no notch) closed pill: one compact island, status centered (knobs, docs/ui/design-notes.md).
    static let monitorPill = CGSize(width: 280, height: 30)

    /// Text size multiplier (⌘= / ⌘− / ⌘0), remembered between launches.
    static var textScale: CGFloat = {
        let v = UserDefaults.standard.double(forKey: "textScale")
        return v > 0 ? CGFloat(v) : 1
    }()
}

/// A font size, scaled by the user's text size (⌘= / ⌘−).
func fs(_ size: CGFloat) -> CGFloat { (size * Theme.textScale).rounded() }

struct BarView: View {
    @ObservedObject var store: Store
    @FocusState private var inputFocused: Bool
    // The liquid drop: height and width move on their own springs, so opening stretches down
    // first and then spreads (a droplet), and closing narrows first and then pulls back up.
    @State private var dropH = false
    @State private var dropW = false

    var body: some View {
        VStack(spacing: 6) {
            bar
            Group {
                if store.mode == .menu { menuList } else { hintChip }
            }
            .opacity(store.isOpen ? 1 : 0)
            .offset(y: store.isOpen ? 0 : -10)
            .animation(.spring(response: Motion.current.response, dampingFraction: 1)
                .delay(store.isOpen ? Motion.current.contentDelay : 0), value: store.isOpen)
            if store.env == .dev { devTag }
            Spacer(minLength: 0)
        }
        .frame(width: AppDelegate.windowSize.width,
               height: store.mode == .menu ? AppDelegate.menuWindowSize.height : AppDelegate.windowSize.height,
               alignment: .top)
        .environment(\.colorScheme, .dark)
        .onChange(of: store.focusRequest) { inputFocused = true }
        .onChange(of: store.isOpen) { liquid(store.isOpen) }
        // Each mode swaps in a new field; give it the keyboard straight away.
        .onChange(of: store.mode) { DispatchQueue.main.async { inputFocused = true } }
    }

    /// The drop (v3, Oct 11 night: "crisp like Wispr"). Same path as v2 (widen on the notch, then
    /// down; close in reverse) but compressed: near-critical damping (no wobble), short response,
    /// tiny stagger. Every number is a knob in `Motion` (tunable live, see docs/ui/motion.md).
    private func liquid(_ open: Bool) {
        let m = Motion.current
        if open {
            withAnimation(.spring(response: m.response * 0.8, dampingFraction: m.damping)) { dropW = true }
            withAnimation(.spring(response: m.response, dampingFraction: m.damping).delay(m.stagger)) { dropH = true }
        } else {
            withAnimation(.spring(response: m.closeResponse, dampingFraction: 1)) { dropH = false }
            withAnimation(.spring(response: m.closeResponse * 0.8, dampingFraction: 1).delay(m.stagger)) { dropW = false }
        }
    }

    // MARK: dev tag (⌥D): same colors, but nothing here touches the real log

    private var devTag: some View {
        HStack(spacing: 6) {
            Text("DEV").font(.system(size: fs(10), weight: .heavy).monospacedDigit())
            Text("testing · nothing is logged").font(.system(size: fs(10)))
                .foregroundStyle(Theme.muted)
        }
        .foregroundStyle(Theme.text)
        .padding(.horizontal, 10).frame(height: 20)
        .background(Capsule().fill(Theme.chrome))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
        .opacity(store.isOpen ? 1 : 0)
    }

    // MARK: the bar

    /// ONE shape, hanging from the top of the screen like the Dynamic Island. Closed, it hugs
    /// the notch: status on the left ear, time on the right, the camera in between. ⌥L grows the
    /// same shape down into the bar; closing shrinks it back. With no notch it's a small tab.
    private var bar: some View {
        let open = store.isOpen
        let ear = Theme.ear * Theme.textScale
        // MacBook: hug the notch (ears either side of the camera). Monitor: one row, room for the title.
        let closedSize = store.notchWidth > 0
            ? CGSize(width: store.notchWidth + ear * 2, height: store.topInset)
            : CGSize(width: Theme.monitorPill.width * Theme.textScale,
                     height: max(store.topInset, Theme.monitorPill.height))
        let openSize = CGSize(width: Theme.barSize.width, height: store.topInset + Theme.barSize.height)
        let size = CGSize(width: dropW ? openSize.width : closedSize.width,
                          height: dropH ? openSize.height : closedSize.height)
        // Pill-like: the closed pill's corners are half its height; the bar's are generous too.
        let radius: CGFloat = dropH ? 26 : store.topInset * 0.5
        // One input line; the ring says which mode you're in.
        let ring: Color = switch store.mode {
            case .input: Theme.statusColor(store)
            case .note: Theme.note
            case .ghost: Theme.ghost
            case .browse, .fill, .edit: Theme.past
            case .menu: Theme.task
        }
        let dashed = [.browse, .fill, .edit].contains(store.mode)  // the past is dashed
        let tier = focusTierAnyMode
        let lively = tier > 0 || !store.states.isEmpty
        return ZStack(alignment: .top) {
            // Open: the input row sits below the notch line.
            VStack(spacing: 0) {
                Color.clear.frame(height: store.topInset)
                openRow.frame(height: Theme.barSize.height)
            }
            .opacity(open ? 1 : 0)
            .animation(open ? .easeOut(duration: 0.12).delay(Motion.current.contentDelay) : .easeIn(duration: 0.06), value: open)
            // Closed: a glance at the ears beside the camera.
            restRow(ear: Theme.ear * Theme.textScale)
                .frame(height: store.topInset)
                .opacity(open ? 0 : 0.85)
                .animation(open ? .easeIn(duration: 0.06) : .easeOut(duration: 0.14).delay(Motion.current.closeResponse), value: open)
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .clipShape(NotchShape(radius: radius))
        .background(NotchShape(radius: radius).fill(Theme.chrome))
        // The neon tube: bloom, colored glass, hot core (see docs/ui/neon.md).
        .overlay(NeonTube(shape: NotchShape(radius: radius, closed: false), color: ring,
                          heat: tier, dashed: dashed, dim: !open))
        // Substances: one blended halo just outside the tube.
        .overlay(OuterRings(colors: Theme.stateColors(store.states), shape: NotchShape(radius: radius, closed: false),
                            opacity: open ? 0.85 : 0.65, spacing: open ? 4 : 3))
        // Focus heat: the bloom grows with the tier and breathes while closed.
        .background(NotchShape(radius: radius).fill(.clear)
            .shadow(color: ring.opacity(lively || open ? 0.18 + Double(tier) * 0.14 : 0),
                    radius: (open ? 10 : 5) + CGFloat(tier) * (open ? 7 : 3))
            .modifier(Breathing(active: lively && !open)))
        .shadow(color: .black.opacity(open ? 0.45 : 0), radius: 22, y: 8)
        .opacity(open || store.showsPill ? 1 : 0)
        .animation(.easeInOut(duration: 0.35), value: tier)
        .animation(.easeOut(duration: 0.15), value: store.mode)
        .animation(Theme.open, value: store.notchWidth)
    }

    private var openRow: some View {
        ZStack {
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
    }

    /// Closed view. MacBook: left ear = what, right ear = how long, the camera between.
    /// Monitor (no notch): one row with the whole title and the time.
    @ViewBuilder private func restRow(ear: CGFloat) -> some View {
        if store.notchWidth > 0 { notchRow(ear: ear) } else { monitorRow }
    }

    private var monitorRow: some View {
        let color = Theme.statusColor(store)
        let start = store.onBreak?.start ?? store.ghost?.start ?? store.timer?.start
        // Centered like an island: status and time sit together in the middle; a long title
        // truncates before the spacers squeeze the time out.
        return HStack(spacing: 7) {
            Spacer(minLength: 0)
            if let b = store.onBreak {
                Image(systemName: b.kind == "smoke" ? "smoke.fill" : "figure.walk").foregroundStyle(color)
                Text(b.label + (b.resume.map { " · then \($0)" } ?? ""))
            } else if let g = store.ghost {
                Image(systemName: "moon.zzz.fill").foregroundStyle(color)
                Text(g.status)
            } else if let t = store.timer {
                Circle().fill(color).frame(width: 6, height: 6).shadow(color: color, radius: 2)
                Text(t.label)
            } else {
                Circle().strokeBorder(color, lineWidth: 1).frame(width: 6, height: 6)
                if let g = store.guess {  // the labeler's guess, faded
                    Text(g.ask ? "\(g.category)?" : "probably \(g.category)").foregroundStyle(Theme.muted).italic()
                } else {
                    Text("nothing running").foregroundStyle(Theme.muted)
                }
            }
            if let f = store.timer?.focus, f > 0, store.onBreak == nil, store.ghost == nil {
                Text(String(repeating: "▲", count: f)).font(.system(size: fs(8), weight: .bold)).foregroundStyle(color)
            }
            if let start {
                TimelineView(.periodic(from: .now, by: 30)) { ctx in
                    Text(Time.duration(ctx.date.timeIntervalSince(Time.parse(start))))
                        .font(.system(size: fs(12), weight: .semibold).monospacedDigit())
                        .foregroundStyle(color)
                        .fixedSize()
                }
            }
            Spacer(minLength: 0)
        }
        .lineLimit(1).truncationMode(.tail)
        .font(.system(size: fs(12), weight: .medium))
        .foregroundStyle(Theme.text)
        .padding(.horizontal, 14)
    }

    private func notchRow(ear: CGFloat) -> some View {
        let color = Theme.statusColor(store)
        let start = store.onBreak?.start ?? store.ghost?.start ?? store.timer?.start
        return HStack(spacing: 0) {
            HStack(spacing: 5) {
                if let b = store.onBreak {
                    Image(systemName: b.kind == "smoke" ? "smoke.fill" : "figure.walk").foregroundStyle(color)
                    Text(b.label)
                } else if let g = store.ghost {
                    Image(systemName: "moon.zzz.fill").foregroundStyle(color)
                    Text(g.status)
                } else if let t = store.timer {
                    Circle().fill(color).frame(width: 6, height: 6).shadow(color: color, radius: 2)
                    Text(t.label)
                } else {
                    Circle().strokeBorder(color, lineWidth: 1).frame(width: 6, height: 6)
                    Text(store.guess.map { $0.ask ? "\($0.category)?" : $0.category } ?? "idle")
                        .foregroundStyle(Theme.muted).italic(store.guess != nil)
                }
            }
            .lineLimit(1).truncationMode(.tail)
            .frame(width: ear - 12, alignment: .leading).padding(.leading, 12)
            Color.clear.frame(width: store.notchWidth)
            HStack(spacing: 4) {
                if let f = store.timer?.focus, f > 0, store.onBreak == nil, store.ghost == nil {
                    Text(String(repeating: "▲", count: f)).font(.system(size: fs(7), weight: .bold)).foregroundStyle(color)
                }
                if let start {
                    TimelineView(.periodic(from: .now, by: 30)) { ctx in
                        Text(Time.duration(ctx.date.timeIntervalSince(Time.parse(start))))
                            .font(.system(size: fs(11), weight: .semibold).monospacedDigit())
                            .foregroundStyle(color)
                    }
                }
            }
            .frame(width: ear - 12, alignment: .trailing).padding(.trailing, 12)
        }
        .font(.system(size: fs(11), weight: .medium))
        .foregroundStyle(Theme.text)
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
        case .menu: "Type a command… (↑↓ ⏎, esc) · Day Log \(store.versionLabel)"
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
            .font(.system(size: fs(12), weight: .medium))
            .foregroundStyle(Theme.note)
            .padding(.horizontal, 10).frame(height: 30)
            .background(Capsule().fill(Theme.note.opacity(0.13)))
        case .ghost:
            HStack(spacing: 6) {
                Image(systemName: "moon.zzz.fill")
                Text("ghost")
            }
            .font(.system(size: fs(12), weight: .semibold))
            .foregroundStyle(Theme.ghost)
            .padding(.horizontal, 10).frame(height: 30)
            .background(Capsule().fill(Theme.ghost.opacity(0.14)))
        case .menu:
            Text("⌘K").font(.system(size: fs(11), weight: .bold).monospacedDigit())
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
                .font(.system(size: fs(12), weight: .medium).monospacedDigit())
                .foregroundStyle(Theme.past)
                .padding(.horizontal, 10).frame(height: 30)
                .background(Capsule().fill(Theme.past.opacity(0.13)))
                .animation(.easeOut(duration: 0.1), value: store.editEnd)
            }
        case .fill:
            if let gap = store.fillItem {
                Text(gap.range)
                    .font(.system(size: fs(12), weight: .semibold).monospacedDigit())
                    .foregroundStyle(Theme.past)
                    .padding(.horizontal, 10).frame(height: 30)
                    .background(Capsule().fill(Theme.past.opacity(0.13)))
            }
        case .browse:
            EmptyView()
        }
    }

    private var focusTierAnyMode: Int {
        store.onBreak == nil && store.ghost == nil && (store.mode == .input || !store.isOpen) ? (store.timer?.focus ?? 0) : 0
    }

    private var focusTier: Int { store.mode == .input && store.ghost == nil ? (store.timer?.focus ?? 0) : 0 }

    private func field(_ prompt: String) -> some View {
        TextField("", text: $store.input, prompt: Text(prompt).foregroundStyle(Theme.muted))
            .textFieldStyle(.plain)
            .font(.system(size: fs(15)))
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
                Image(systemName: "note.text").font(.system(size: fs(11))).foregroundStyle(color)
            } else {
                Circle().fill(item.isGap ? .clear : color).overlay(Circle().strokeBorder(color, lineWidth: 1))
                    .frame(width: 7, height: 7)
            }
            Text(item.isNote ? Time.clockString(item.startDate) : item.range)
                .font(.system(size: fs(12), weight: .medium).monospacedDigit())
                .foregroundStyle(Theme.muted)
            Text(item.isGap ? "untracked" : (item.label ?? ""))
                .font(.system(size: fs(15), weight: item.isGap ? .regular : .medium))
                .italic(item.isGap)
                .foregroundStyle(item.isGap ? Theme.muted : Theme.text)
                .lineLimit(1).truncationMode(.tail)
            if let f = item.focusPeak, f > 0 {
                Text(String(repeating: "▲", count: f))
                    .font(.system(size: fs(9), weight: .bold)).foregroundStyle(Theme.taskColor(focus: f))
            }
            Spacer(minLength: 8)
            Text(item.isNote ? "" : Time.minutes(item.minutes))
                .font(.system(size: fs(13), weight: .semibold).monospacedDigit())
                .foregroundStyle(item.isGap ? Theme.muted : Theme.text)
        }
    }

    private func breakChip(_ b: BreakInfo) -> some View {
        HStack(spacing: 7) {
            Image(systemName: b.kind == "smoke" ? "smoke.fill" : "figure.walk").font(.system(size: fs(10)))
            Text(b.label)
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                Text(Time.duration(ctx.date.timeIntervalSince(Time.parse(b.start)), withSeconds: true))
                    .font(.system(size: fs(12), weight: .semibold).monospacedDigit())
            }
        }
        .font(.system(size: fs(12), weight: .medium))
        .foregroundStyle(Theme.away)
        .padding(.horizontal, 10).frame(height: 30)
        .background(Capsule().fill(Theme.away.opacity(0.14)))
    }

    private func ghostChip(_ g: GhostInfo) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "moon.zzz.fill").font(.system(size: fs(10)))
            Text(g.status).lineLimit(1).truncationMode(.tail).frame(maxWidth: 170, alignment: .leading)
            TimelineView(.periodic(from: .now, by: 30)) { ctx in
                Text(Time.duration(ctx.date.timeIntervalSince(Time.parse(g.start))))
                    .font(.system(size: fs(12), weight: .semibold).monospacedDigit())
            }
        }
        .font(.system(size: fs(12), weight: .medium))
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
                    .font(.system(size: fs(9), weight: .bold))
                    .foregroundStyle(tint)
                    .help(Store.focusNames[f])
            }
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                Text(Time.duration(ctx.date.timeIntervalSince(Time.parse(t.start)), withSeconds: true))
                    .font(.system(size: fs(12), weight: .semibold).monospacedDigit())
                    .foregroundStyle(tint)
            }
        }
        .font(.system(size: fs(12), weight: .medium))
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
                Text("No matching command").font(.system(size: fs(12))).foregroundStyle(Theme.muted)
                    .padding(.horizontal, 12).padding(.vertical, 8)
            }
            ForEach(Array(items.enumerated()), id: \.element.id) { i, cmd in
                if i == 0 || items[i - 1].group != cmd.group {
                    Text(cmd.group.rawValue)
                        .font(.system(size: fs(9), weight: .bold)).tracking(1.2)
                        .foregroundStyle(Theme.muted)
                        .padding(.horizontal, 12).padding(.top, i == 0 ? 4 : 8).padding(.bottom, 2)
                }
                HStack {
                    Text(cmd.title).font(.system(size: fs(13))).foregroundStyle(Theme.text)
                    Spacer()
                    Text(cmd.shortcut).font(.system(size: fs(12), weight: .medium).monospacedDigit())
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
            .font(.system(size: fs(12)))
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
        } else if !typed, store.mode == .input, let c = store.cutOffer {
            let from = Time.clockString(Time.parse(c.awayFrom)), to = Time.clockString(Time.parse(c.awayTo))
            Text("away \(from)–\(to)").foregroundStyle(Theme.text)
            Text("· ⌫ end task at \(from)").foregroundStyle(Theme.muted)
        } else if !typed, store.mode == .input, store.timer == nil, let g = store.guess, !store.showWhatsNew {
            if g.ask {
                Text("looks like \(g.category)?").foregroundStyle(Theme.text).fontWeight(.semibold)
                Text("· ⏎ yes · or type what you're doing").foregroundStyle(Theme.muted)
            } else {
                Text("probably \(g.category)" + (g.task.map { " · \($0)" } ?? "")).foregroundStyle(Theme.text)
                Text("· ⏎ confirm · type to fix").foregroundStyle(Theme.muted)
            }
        } else if !typed, store.mode == .input, store.showWhatsNew, let r = store.release {
            Text(r.version).foregroundStyle(Theme.text).fontWeight(.semibold)
            Text("· new: \(r.new.first ?? "")").foregroundStyle(Theme.text)
            if let t = r.try.first { Text("· try: \(t)").foregroundStyle(Theme.muted) }
        } else if typed, let p = store.preview, p.action == "log", let d = store.describe(p) {
            Text("log").foregroundStyle(Theme.task).fontWeight(.semibold)
            Text(d).foregroundStyle(Theme.text)
            Text("⏎").foregroundStyle(Theme.muted)
        } else if typed, let p = store.preview, p.action == "command" {
            Text("⏎ \(p.label)").foregroundStyle(Theme.task).fontWeight(.semibold)
            Text("· ⇧⏎ log it as a task instead").foregroundStyle(Theme.muted)
        } else if typed {
            Text(store.timer == nil ? "⏎ start timer" : "⏎ switch timer").foregroundStyle(Theme.text)
            if let also = store.preview?.also, !also.isEmpty {
                Text("· + " + also.joined(separator: ", ")).foregroundStyle(Theme.high)
            } else {
                Text("· add 15m or 3:10-3:25 to log past time").foregroundStyle(Theme.muted)
            }
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
            Text(store.timer != nil ? "type: smoke break · back · deep focus · high  ·  ⌘K all"
                                    : "type a task, or: walk · ghost · high  ·  ⌘K all").foregroundStyle(Theme.muted)
            if store.timer != nil { Text("· ⌘. stop").foregroundStyle(Theme.muted) }
        }
    }
}

// MARK: - substances: one blended glow outside the main ring

/// Substances as a single soft halo, not separate lines (his call, Oct 11: "a blend and glow").
/// Several at once blend around the shape (high's green flowing into caffeinated's brown);
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
            .gpuLight()
            .allowsHitTesting(false)
        }
    }
}

extension View {
    /// Render a light layer (blurs, glows) in one Metal pass instead of re-drawing each blur on
    /// the CPU every animation frame: what lets the drop run at the display's 120 Hz. The padding
    /// gives the blur room, since a Metal pass is clipped to its own bounds.
    func gpuLight(room: CGFloat = 28) -> some View {
        padding(room).drawingGroup().padding(-room)
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
                    .font(.system(size: fs(9), weight: .bold, design: .rounded))
                    .foregroundStyle(color)
            }
        }
    }
}

/// The bar's outline: it flows out of the top edge of the screen. Small concave shoulders where
/// it meets the edge, and Apple-style continuous ("squircle") corners at the bottom: the curve
/// starts earlier and eases in, instead of a plain circular arc. `closed: false` = no top edge.
struct NotchShape: InsettableShape {
    var radius: CGFloat
    var closed = true
    var inset: CGFloat = 0
    var shoulder: CGFloat = 0  // Oct 11: the curvy bleed into the edge read as a dull smear; straight sides

    var animatableData: CGFloat {
        get { radius }
        set { radius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let minX = rect.minX + inset, maxX = rect.maxX - inset
        let top = rect.minY, bottom = rect.maxY - inset
        let r = max(0, min(radius, (maxX - minX) / 2.6, (bottom - top) / 1.3))
        let k: CGFloat = 1.28   // how far before the corner the curve starts (continuous corners)
        let c: CGFloat = 0.36   // control-point pull
        let sh = shoulder
        var p = Path()
        // left shoulder: from the screen edge, curving down into the side
        p.move(to: CGPoint(x: minX - sh, y: top - 4))
        p.addLine(to: CGPoint(x: minX - sh, y: top))
        p.addQuadCurve(to: CGPoint(x: minX, y: top + sh), control: CGPoint(x: minX, y: top))
        // left side, bottom-left continuous corner
        p.addLine(to: CGPoint(x: minX, y: bottom - r * k))
        p.addCurve(to: CGPoint(x: minX + r * k, y: bottom),
                   control1: CGPoint(x: minX, y: bottom - r * c),
                   control2: CGPoint(x: minX + r * c, y: bottom))
        // bottom, bottom-right corner, right side
        p.addLine(to: CGPoint(x: maxX - r * k, y: bottom))
        p.addCurve(to: CGPoint(x: maxX, y: bottom - r * k),
                   control1: CGPoint(x: maxX - r * c, y: bottom),
                   control2: CGPoint(x: maxX, y: bottom - r * c))
        p.addLine(to: CGPoint(x: maxX, y: top + sh))
        // right shoulder back to the edge
        p.addQuadCurve(to: CGPoint(x: maxX + sh, y: top), control: CGPoint(x: maxX, y: top))
        p.addLine(to: CGPoint(x: maxX + sh, y: top - 4))
        if closed { p.closeSubpath() }
        return p
    }

    func inset(by amount: CGFloat) -> NotchShape {
        var s = self
        s.inset += amount
        return s
    }
}

/// Neon: a glass tube of colored light. Three layers, outermost first: a soft bloom (light
/// scattering in the air), the tube itself (colored, slightly soft), and a hot core (near-white,
/// thin, sharp). The core is what makes it read as *lit* rather than *painted*.
struct NeonTube<S: Shape>: View {
    let shape: S
    let color: Color
    var heat: Int = 0        // focus tier 0-3: a brighter, thicker tube
    var dashed = false       // the past: an unlit, dashed tube
    var dim = false          // closed pill: a little quieter

    var body: some View {
        let h = CGFloat(heat)
        let dash: [CGFloat] = dashed ? [6, 4] : []
        let lit = dashed ? 0.55 : (dim ? 0.8 : 1)
        ZStack {
            shape.stroke(color, style: StrokeStyle(lineWidth: 5 + h * 2, dash: dash))
                .blur(radius: 6 + h * 2).opacity(0.45 * lit)
            shape.stroke(color, style: StrokeStyle(lineWidth: 1.8 + h * 0.5, dash: dash))
                .blur(radius: 0.6).opacity(0.95 * lit)
            if !dashed {
                shape.stroke(Color.white.opacity(0.55 + 0.1 * h), style: StrokeStyle(lineWidth: 0.6 + h * 0.15))
                    .blendMode(.plusLighter).opacity(lit)
            }
        }
        .gpuLight()
        .allowsHitTesting(false)
    }
}

/// The precision knobs for how the pill moves. Defaults are tuned for "crisp"; override any of
/// them live without a rebuild, e.g. `defaults write com.rithvik.daylog motion.response 0.2`,
/// then press ⌥L again. Read fresh on every open/close.
struct Motion {
    var response: Double       // seconds the spring takes to arrive (speed). Lower = snappier
    var damping: Double        // 1 = no overshoot; lower = bounce/wobble (the "sloppy" feel)
    var stagger: Double        // delay between widening and dropping
    var contentDelay: Double   // when the text appears after the press
    var closeResponse: Double  // speed of going back up

    static let defaults = Motion(response: 0.22, damping: 0.9, stagger: 0.03, contentDelay: 0.08, closeResponse: 0.18)

    static var current: Motion {
        let d = UserDefaults.standard
        func v(_ k: String, _ fallback: Double) -> Double { d.object(forKey: "motion." + k) as? Double ?? fallback }
        let x = defaults
        return Motion(response: v("response", x.response), damping: v("damping", x.damping),
                      stagger: v("stagger", x.stagger), contentDelay: v("contentDelay", x.contentDelay),
                      closeResponse: v("closeResponse", x.closeResponse))
    }
}
