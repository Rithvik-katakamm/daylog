import Foundation
import SwiftUI

/// The app's state. Views read from here; actions go to the server, then refresh.
/// The UI updates optimistically where it can, so a click never waits on the network.
@MainActor
final class Store: ObservableObject {
    @Published var timer: TimerInfo?
    @Published var ghost: GhostInfo?  // ghost mode: offline, logging nothing
    @Published var onBreak: BreakInfo?  // ⌘B walk / ⌘⇧B smoke
    @Published var cutOffer: CutOffer?  // RIT-39: a long away inside the running timer
    @Published var version = "dev"      // RIT-124: the running release
    @Published var release: ReleaseInfo?  // owner-only: what's new in it
    @Published var showWhatsNew = false   // one time per release, on the next open
    @Published var guess: Guess?          // RIT-122: the labeler's guess when nothing runs
    private var guessShownThisOpen = false
    @Published var states: Set<String> = []  // substances that are on: outer rings

    /// What stays on screen while the bar is closed (his call, Oct 11: try both, then pick).
    enum RestStyle: String, CaseIterable { case pill, ring, both, off }
    @Published var restStyle: RestStyle = RestStyle(rawValue: UserDefaults.standard.string(forKey: "restStyle") ?? "")
        ?? (Flavor.isDev ? .off : .pill) {  // only one pill in the notch: the real one
        didSet { UserDefaults.standard.set(restStyle.rawValue, forKey: "restStyle") }
    }
    /// Text size (⌘= / ⌘− / ⌘0). Views read Theme.textScale; this publishes the change.
    @Published var textScale: CGFloat = Theme.textScale {
        didSet {
            Theme.textScale = textScale
            UserDefaults.standard.set(Double(textScale), forKey: "textScale")
        }
    }

    func resizeText(_ step: Int) {
        let next = step == 0 ? 1 : min(1.4, max(0.8, textScale + CGFloat(step) * 0.1))
        textScale = (next * 10).rounded() / 10
        flashBriefly("text size \(Int(textScale * 100))%")
    }

    /// Which screen the pill lives on: the MacBook (notch), the external monitor, or wherever the
    /// cursor is when you open it.
    enum PillScreen: String { case follow, laptop, monitor }
    @Published var pillScreen: PillScreen = PillScreen(rawValue: UserDefaults.standard.string(forKey: "pillScreen") ?? "")
        ?? .follow {
        didSet { UserDefaults.standard.set(pillScreen.rawValue, forKey: "pillScreen"); onPlacementChange?() }
    }
    var onPlacementChange: (() -> Void)?

    /// The screen's notch (0 = none) and menu-bar height, so the closed bar can hug the notch.
    @Published var notchWidth: CGFloat = 0
    @Published var topInset: CGFloat = 24
    var showsPill: Bool { restStyle == .pill || restStyle == .both }
    var showsRing: Bool { restStyle == .ring || restStyle == .both }
    @Published var summary: Summary?
    @Published var serverDown = false
    @Published var error: String?
    @Published var focusRequest = 0  // bump to focus the input field
    @Published var input = "" {
        didSet {
            if Flavor.isDev, input != oldValue { debugTrace("input \"\(oldValue)\"->\"\(input)\"") }
            if mode == .input { schedulePreview() }
            if mode == .menu { menuIndex = 0 }  // filtering resets the selection
        }
    }
    @Published var preview: LinePreview?
    @Published var flash: String?  // brief confirmation after an action
    @Published var isOpen = false   // drives the grow/shrink animation
    /// Real or dev (⌥D). Dev talks to a separate server and database; colors stay identical.
    @Published var env: API.Env = .real { didSet { API.env = env } }

    // Scrolling back through the past with ↑/↓.
    enum Mode: Equatable { case input, browse, fill, note, ghost, edit, menu }

    // MARK: command menu (⌘K or /): the field becomes a filter over `commands`
    var commands: [Command] = []
    @Published var menuIndex = 0

    var menuItems: [Command] {
        let q = input.trimmingCharacters(in: .whitespaces).lowercased()
        return commands.filter { c in
            c.isAvailable(self) && (q.isEmpty || c.title.lowercased().contains(q)
                                    || c.group.rawValue.lowercased().contains(q))
        }
    }

    func openMenu() {
        input = ""; preview = nil; menuIndex = 0
        mode = .menu
        Sound.mode.play()
        focusRequest += 1
    }

    func menuMove(_ delta: Int) {
        let n = menuItems.count
        guard n > 0 else { return }
        menuIndex = (menuIndex + delta + n) % n
    }

    func runSelectedCommand() {
        let items = menuItems
        guard items.indices.contains(menuIndex) else { return }
        let cmd = items[menuIndex]
        mode = .input; input = ""
        cmd.run()
    }

    func resetDevData() {
        guard env == .dev else { return }
        Task {
            do { try await API.post("dev/reset", env: .dev); flashBriefly("dev data reset") }
            catch { self.error = error.localizedDescription }
            await refreshAll()
        }
    }

    /// ↓ edit: the block being fixed (usually the running timer), and its new end.
    struct EditTarget: Equatable {
        let id: String
        let label: String
        let start: Date
        let originalEnd: Date
        let running: Bool
    }
    @Published var editTarget: EditTarget?
    @Published var editEnd = Date()
    @Published var mode: Mode = .input {
        didSet { if Flavor.isDev, mode != oldValue { debugTrace("mode \(oldValue)->\(mode)") } }
    }
    @Published var history: [HistoryItem] = []
    @Published var index = 0
    @Published var movedOlder = true  // direction of the last move, for the slide animation
    @Published var fillItem: HistoryItem?
    private var oldestDay: Date?
    private let maxDaysBack = 30

    var current: HistoryItem? { history.indices.contains(index) ? history[index] : nil }

    private var previewTask: Task<Void, Never>?
    var onSubmitted: (() -> Void)?  // the window closes itself after a submit

    private func schedulePreview() {
        previewTask?.cancel()
        let text = input.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { preview = nil; return }
        previewTask = Task {
            try? await Task.sleep(for: .milliseconds(60))  // debounce keystrokes
            guard !Task.isCancelled else { return }
            if let p: LinePreview = try? await API.get("parse", query: ["text": text]), !Task.isCancelled {
                preview = p
            }
        }
    }

    // MARK: scroll back

    func enterBrowse() {
        Task {
            let today = Calendar.current.startOfDay(for: Date())
            oldestDay = nil
            history = []
            await loadDay(today)
            while history.isEmpty, await loadOlderDay() {}
            guard !history.isEmpty else { flashBriefly("nothing logged yet"); return }
            index = 0
            movedOlder = true
            mode = .browse
            Sound.mode.play()
        }
    }

    func older() {
        if index + 1 < history.count {
            movedOlder = true; index += 1
        } else {
            Task {
                let before = history.count
                while history.count == before, await loadOlderDay() {}
                if index + 1 < history.count { movedOlder = true; index += 1 }
            }
        }
    }

    func newer() {
        if index > 0 { movedOlder = false; index -= 1 } else { mode = .input }
    }

    /// ⏎ on a gap: type what you were doing then.
    func beginFill() {
        guard let c = current, c.isGap else { return }
        fillItem = c
        input = ""
        mode = .fill
        focusRequest += 1
    }

    /// Esc steps back one level instead of closing.
    func back() {
        switch mode {
        case .fill: mode = .browse; fillItem = nil; input = ""
        case .note, .ghost, .edit, .menu: mode = .input; input = ""; editTarget = nil
        default: mode = .input
        }
    }

    /// ⌘O: go ghost (type an optional status), or come back if already a ghost.
    func ghostKey() {
        if ghost != nil {
            ghost = nil
            Sound.saved.play()
            flash = "Back online"
            Task {
                do { try await API.delete("ghost") } catch { self.error = error.localizedDescription }
                await refreshAll()
                try? await Task.sleep(for: .seconds(0.9))
                onSubmitted?(); flash = nil
            }
            return
        }
        input = ""; preview = nil
        mode = .ghost
        Sound.mode.play()
        focusRequest += 1
    }

    private func submitGhost() {
        let status = input.trimmingCharacters(in: .whitespacesAndNewlines)
        input = ""
        timer = nil  // optimistic: going dark stops the clock
        ghost = GhostInfo(id: "pending", status: status.isEmpty ? "offline" : status, start: Time.string(Date()))
        Sound.ghost.play()
        flash = "Ghost mode · nothing is being logged"
        Task {
            do { try await API.post("ghost", ["status": status, "source": "button"]) }
            catch { self.error = error.localizedDescription }
            await refreshAll()
            try? await Task.sleep(for: .seconds(1.1))
            onSubmitted?(); flash = nil
        }
    }

    /// ⌘F: step focus up a tier on the running task (focused → deep → hyperfocus → off).
    static let focusNames = ["", "focused", "deep focus", "hyperfocus"]

    func cycleFocus() {
        guard var t = timer, t.id != "pending" else { flashBriefly("start a task first, then ⌘F"); return }
        let next = ((t.focus ?? 0) + 1) % 4
        t.focus = next
        timer = t  // optimistic: the ring changes on the keypress
        Sound.mode.play()
        flashBriefly(next == 0 ? "focus off" : "\(Store.focusNames[next])  " + String(repeating: "▲", count: next))
        Task {
            do { try await API.post("focus", ["tier": next, "source": "button"]) }
            catch { self.error = error.localizedDescription }
        }
    }

    /// ⌘⇧F: straight to focus off, without cycling through the tiers.
    func focusOff() {
        guard var t = timer, t.id != "pending", (t.focus ?? 0) > 0 else { flashBriefly("focus is already off"); return }
        t.focus = 0
        timer = t
        Sound.mode.play()
        flashBriefly("focus off")
        Task {
            do { try await API.post("focus", ["tier": 0, "source": "button"]) }
            catch { self.error = error.localizedDescription }
        }
    }

    /// ⌘H high · ⌘I intoxicated · ⌘C caffeinated: toggle a substance ring. They stack.
    static let stateNames = ["high": "high", "intoxicated": "intoxicated", "caffeinated": "caffeinated"]

    func toggleState(_ name: String) {
        let on = !states.contains(name)
        if on { states.insert(name) } else { states.remove(name) }  // optimistic
        Sound.mode.play()
        flashBriefly(on ? "\(name) on" : "\(name) off")
        Task {
            do { try await API.post("state", ["state": name, "on": on, "source": "button"]) }
            catch { self.error = error.localizedDescription }
        }
    }

    /// ⌘B: step away on a walk (⌘⇧B: a smoke break). The task pauses. Press ⌘B (either) again
    /// when you're back: the task resumes, and a smoke break comes back high.
    var canComeBack: Bool { onBreak != nil || ghost?.resume != nil }

    func breakKey(smoke: Bool) {
        if canComeBack {
            let resume = onBreak?.resume ?? ghost?.resume
            let wasSmoke = (onBreak?.kind ?? "") == "smoke"
            onBreak = nil
            if ghost?.resume != nil { ghost = nil }
            if wasSmoke { states.insert("high") }
            if let resume { timer = TimerInfo(id: "pending", label: resume, start: Time.string(Date())) }
            Sound.saved.play()
            flash = resume.map { "Back · resuming “\($0)”" } ?? "Back"
            Task {
                do { try await API.delete("break") } catch { self.error = error.localizedDescription }
                await refreshAll()
                try? await Task.sleep(for: .seconds(1.0))
                onSubmitted?(); flash = nil
            }
            return
        }
        if ghost != nil { flashBriefly("you're a ghost: ⌘O to come back first"); return }
        let kind = smoke ? "smoke" : "walk"
        onBreak = BreakInfo(id: "pending", kind: kind, label: smoke ? "smoke break" : "walk",
                            start: Time.string(Date()), resume: timer?.label)
        timer = nil
        Sound.ghost.play()
        flash = smoke ? "Smoke break · ⌘B when you're back (comes back high)" : "Walk · ⌘B when you're back"
        Task {
            do { try await API.post("break", ["kind": kind, "source": "button"]) }
            catch { self.error = error.localizedDescription }
            await refreshAll()
            try? await Task.sleep(for: .seconds(1.1))
            onSubmitted?(); flash = nil
        }
    }

    /// ⌘N: jot a thought at this moment, tagged with the running task. Doesn't switch tasks.
    func beginNote() {
        input = ""
        preview = nil
        mode = .note
        Sound.mode.play()
        focusRequest += 1
    }

    private func submitNote() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        input = ""
        flash = "Noted · \(Time.clockString(Date()))"
        Sound.saved.play()
        Task {
            do { try await API.post("notes", ["text": text, "source": "button"]) }
            catch { self.error = error.localizedDescription }
            try? await Task.sleep(for: .seconds(0.9))
            onSubmitted?()
            flash = nil
        }
    }

    func deleteCurrent() {
        guard let c = current, let id = c.id, ["entry", "timer", "note"].contains(c.kind) else { return }
        Task {
            do { try await API.delete("entries/\(id)") } catch { self.error = error.localizedDescription }
            await reloadKeepingPlace()
        }
    }

    // MARK: edit (↓): rename a block or cut it back to when it really ended

    func beginEdit() {
        Task {
            var target: EditTarget?
            if let t = timer, t.id != "pending" {
                target = EditTarget(id: t.id, label: t.label, start: Time.parse(t.start),
                                    originalEnd: Date(), running: true)
            } else if let page: HistoryPage = try? await API.get("history"),
                      let last = page.items.first(where: { $0.kind == "entry" || $0.kind == "timer" }),
                      let id = last.id {
                target = EditTarget(id: id, label: last.label ?? "", start: last.startDate,
                                    originalEnd: last.endDate, running: false)
            }
            guard let target else { flashBriefly("nothing to edit yet"); return }
            editTarget = target
            editEnd = target.originalEnd
            mode = .edit
            input = target.label
            Sound.mode.play()
            focusRequest += 1
        }
    }

    /// Move the end in steps, snapping to the step grid, never before the start or past now.
    func nudgeEnd(minutes: Int) {
        guard let t = editTarget else { return }
        let step = TimeInterval(abs(minutes) * 60)
        let t0 = editEnd.timeIntervalSinceReferenceDate
        let snapped = minutes < 0 ? (ceil(t0 / step) - 1) * step : (floor(t0 / step) + 1) * step
        let earliest = t.start.addingTimeInterval(60)
        editEnd = min(max(Date(timeIntervalSinceReferenceDate: snapped), earliest), Date())
        // Silent on purpose (his call, Oct 10): sound gets redesigned as a whole (RIT-37).
    }

    private func submitEdit() {
        guard let t = editTarget else { return }
        let label = input.trimmingCharacters(in: .whitespacesAndNewlines)
        var body: [String: Any] = ["source": "button"]
        if !label.isEmpty && label != t.label { body["label"] = label }
        if abs(editEnd.timeIntervalSince(t.originalEnd)) >= 30 { body["end"] = Time.string(editEnd) }
        guard body.count > 1 else { back(); return }  // nothing changed
        if body["end"] != nil && t.running { timer = nil }  // optimistic: cutting back stops it
        flash = "Updated “\(label.isEmpty ? t.label : label)” · \(Time.clockString(t.start))–\(Time.clockString(editEnd))"
        Sound.saved.play()
        input = ""
        Task {
            do { try await API.post("entries/\(t.id)/amend", body) }
            catch { self.error = error.localizedDescription }
            await refreshAll()
            try? await Task.sleep(for: .seconds(1.2))
            onSubmitted?(); flash = nil
        }
    }

    func resetMode() {
        guessShownThisOpen = false
        if showWhatsNew, let r = release {  // seen once: don't show it again for this release
            UserDefaults.standard.set(r.version, forKey: "seenVersion")
            showWhatsNew = false
        }
        editTarget = nil
        mode = .input; fillItem = nil; history = []; index = 0; input = ""; preview = nil
    }

    private func submitFill() {
        guard let gap = fillItem else { return }
        let label = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty else { return }
        input = ""
        Task {
            do {
                try await API.post("entries", ["label": label, "start": gap.start, "end": gap.end, "source": "button"])
                flashBriefly("Logged “\(label)”  \(gap.range)")
                Sound.saved.play()
            } catch {
                self.error = error.localizedDescription
            }
            fillItem = nil
            await reloadKeepingPlace()
            mode = .browse
            await refreshAll()
        }
    }

    private func reloadKeepingPlace() async {
        let keepUntil = oldestDay ?? Calendar.current.startOfDay(for: Date())
        history = []
        oldestDay = nil
        await loadDay(Calendar.current.startOfDay(for: Date()))
        while let d = oldestDay, d > keepUntil, await loadOlderDay() {}
        index = min(index, max(history.count - 1, 0))
    }

    private func loadDay(_ day: Date) async {
        if let page: HistoryPage = try? await API.get("history", query: ["date": Time.dayString(day)]) {
            history += page.items
            oldestDay = day
        }
    }

    /// Returns false when there's nothing older left to load.
    private func loadOlderDay() async -> Bool {
        let from = oldestDay ?? Calendar.current.startOfDay(for: Date())
        guard let prev = Calendar.current.date(byAdding: .day, value: -1, to: from),
              let limit = Calendar.current.date(byAdding: .day, value: -maxDaysBack, to: Date()),
              prev > limit else { return false }
        await loadDay(prev)
        return true
    }

    func flashBriefly(_ text: String) {
        flash = text
        Task { try? await Task.sleep(for: .seconds(1.6)); if flash == text { flash = nil } }
    }

    /// ⏎: a time in the text logs it; otherwise starts a timer. ⇧⏎ forces a timer.
    func submit(forceTimer: Bool = false) {
        if mode == .fill { submitFill(); return }
        if mode == .note { submitNote(); return }
        if mode == .ghost { submitGhost(); return }
        if mode == .edit { submitEdit(); return }
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty, guess != nil { acceptGuess(); return }  // RIT-122: ⏎ confirms the guess
        guard !text.isEmpty else { return }
        // Only trust a preview made for exactly this line (typing fast can outrun it).
        let fresh = preview?.text?.trimmingCharacters(in: .whitespacesAndNewlines) == text ? preview : nil
        if !forceTimer, fresh?.action == "command" || (fresh == nil && preview?.action == "command") {
            submitCommand(text, say: fresh?.label ?? preview?.label ?? text)
            return
        }
        let willLog = !forceTimer && preview?.action == "log"
        if !willLog {  // optimistic: show the timer immediately
            let label = forceTimer ? (preview?.label ?? text) : text
            timer = TimerInfo(id: "pending", label: label, start: Time.string(Date()))
        }
        flash = willLog ? describe(preview).map { "Logged \($0)" } : nil
        if !willLog { ghost = nil; onBreak = nil }  // starting a task brings you back
        Sound.saved.play()
        input = ""
        preview = nil
        if !willLog, let g = guess {  // RIT-122: typing over a guess corrects it (a label for the guessed block)
            guess = nil
            Task { _ = try? await API.post("label", ["action": "correct", "text": text, "start": g.start, "end": g.end,
                                                    "guess": guessDict(g), "source": "bar"]) }
        }
        run { try await API.post("log", ["text": text, "timer": forceTimer, "source": "button"]) }
        Task {
            try? await Task.sleep(for: .seconds(flash != nil ? 1.2 : 0.5))
            onSubmitted?()
            flash = nil
        }
    }

    /// A typed command ("smoke break", "back", "deep focus", "high"): the server decides and does it,
    /// then the bar shows the result. No optimistic guess, so it can't flash the wrong state.
    private func submitCommand(_ text: String, say: String) {
        input = ""; preview = nil
        Sound.mode.play()
        flash = say.prefix(1).uppercased() + say.dropFirst()
        Task {
            do { try await API.post("log", ["text": text, "source": "button"]) }
            catch { self.error = error.localizedDescription; self.flash = nil }
            await refreshAll()
            try? await Task.sleep(for: .seconds(0.9))
            if self.error == nil { onSubmitted?() }
            flash = nil
        }
    }

    func describe(_ p: LinePreview?) -> String? {
        guard let p, p.action == "log", let s = p.start, let e = p.end else { return nil }
        let end = p.untilNow == true ? "now" : Time.clockString(Time.parse(e))
        return "“\(p.label)”  \(Time.clockString(Time.parse(s)))–\(end)  (\(Time.minutes(p.minutes ?? 0)))"
    }

    private var poller: Task<Void, Never>?

    /// Dev-build-only: who changed state (first app frames of the call stack).
    private func debugTrace(_ what: String) {
        let frames = Thread.callStackSymbols.dropFirst(2).filter { $0.contains("Daylog") }.prefix(4)
            .map { $0.split(separator: " ").dropFirst(3).prefix(1).joined() }
        print("trace \(what) <- \(frames.joined(separator: " < "))"); fflush(stdout)
    }

    func startPolling() {
        poller?.cancel()
        poller = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshNow()
                // Every 4s, so a change an agent makes (MCP set_status) shows up almost live. /now
                // answers in ~3 ms locally, so this costs nothing noticeable.
                try? await Task.sleep(for: .seconds(4))
            }
        }
    }

    func refreshNow() async {
        do {
            let now: NowState = try await API.get("now")
            if now.timer != timer { timer = now.timer }
            if now.ghost != ghost { ghost = now.ghost }
            if now.onBreak != onBreak { onBreak = now.onBreak }
            if now.cutOffer != cutOffer { cutOffer = now.cutOffer }
            if now.guess != guess { guess = now.guess }
            let on = Set((now.states ?? []).map(\.state))
            if on != states { states = on }
            serverDown = false
        } catch {
            serverDown = true
        }
    }

    func refreshDay() async {
        do {
            summary = try await API.get("summary")
            serverDown = false
        } catch {
            serverDown = true
        }
    }

    /// RIT-124: on each open, learn the running version; the first open after a new release shows
    /// "what's new" once (owner-only: the server sends notes only to his install).
    func refreshHealth() async {
        guard let h: Health = try? await API.get("health") else { return }
        version = h.version ?? "dev"
        release = h.release
        if let r = h.release, !r.new.isEmpty, UserDefaults.standard.string(forKey: "seenVersion") != r.version {
            showWhatsNew = true
        }
    }

    /// RIT-124: the ⌘K header's version, e.g. "v0.17 · released 3:26 PM" (or "Oct 12" if older than today).
    var versionLabel: String {
        guard let s = release?.released_at, let d = ISO8601DateFormatter().date(from: s) else { return version }
        let f = DateFormatter()
        f.dateFormat = Calendar.current.isDateInToday(d) ? "h:mm a" : "MMM d, h:mm a"
        return "\(version) · released \(f.string(from: d))"
    }

    /// ⌘K "What's new": show the line again, or just the version when there are no notes.
    func whatsNew() {
        if let r = release, !r.new.isEmpty { showWhatsNew = true } else { flashBriefly("Day Log \(version)") }
    }

    /// RIT-122: log that a guess was shown (once per open), so acceptance can be measured.
    func noteGuessShown() {
        guard isOpen, !guessShownThisOpen, let g = guess else { return }
        guessShownThisOpen = true
        Task { _ = try? await API.post("label", ["action": "shown", "guess": guessDict(g), "source": "bar"]) }
    }

    /// ⏎ on an empty line: yes, that's what I was doing. A label (claim) for the guessed block.
    func acceptGuess() {
        guard let g = guess else { return }
        Sound.saved.play()
        flash = "labeled: \(g.category)" + (g.task.map { " · \($0)" } ?? "")
        guess = nil
        Task {
            _ = try? await API.post("label", ["action": "confirm", "category": g.category, "task": g.task ?? NSNull(),
                                             "start": g.start, "end": g.end, "guess": guessDict(g), "source": "bar"])
            await refreshAll()
            try? await Task.sleep(for: .seconds(0.9))
            onSubmitted?(); flash = nil
        }
    }

    private func guessDict(_ g: Guess) -> [String: Any] {
        ["category": g.category, "task": g.task ?? NSNull(), "confidence": g.confidence,
         "start": g.start, "end": g.end, "ask": g.ask]
    }

    func refreshAll() async {
        await refreshNow()
        await refreshDay()
    }

    // MARK: actions

    /// RIT-39: accept the cut offer (⌫ on an empty line). The task ends when he walked away.
    func acceptCut() {
        guard cutOffer != nil else { return }
        Sound.saved.play()
        timer = nil; cutOffer = nil  // optimistic
        run { try await API.post("timer/cut", ["source": "bar"]) }
    }

    func stop() {
        guard timer != nil else { return }
        Sound.saved.play()
        timer = nil  // optimistic
        run { try await API.post("timer/stop", ["source": "button"]) }
    }

    private func run(_ op: @escaping () async throws -> Any) {
        Task {
            do {
                _ = try await op()
                error = nil
            } catch {
                self.error = error.localizedDescription
            }
            await refreshAll()
        }
    }
}
