import Foundation
import SwiftUI

/// The app's state. Views read from here; actions go to the server, then refresh.
/// The UI updates optimistically where it can, so a click never waits on the network.
@MainActor
final class Store: ObservableObject {
    @Published var timer: TimerInfo?
    @Published var ghost: GhostInfo?  // ghost mode: offline, logging nothing
    @Published var summary: Summary?
    @Published var serverDown = false
    @Published var error: String?
    @Published var focusRequest = 0  // bump to focus the input field
    @Published var input = "" { didSet { if mode == .input { schedulePreview() } } }
    @Published var preview: LinePreview?
    @Published var flash: String?  // brief confirmation after an action
    @Published var isOpen = false   // drives the grow/shrink animation

    // Scrolling back through the past with ↑/↓.
    enum Mode: Equatable { case input, browse, fill, note, ghost, edit }

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
    @Published var mode: Mode = .input
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
        case .note, .ghost, .edit: mode = .input; input = ""; editTarget = nil
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
        flash = "Noted"
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
        Sound.watchStep()  // tick, tock: you're winding the clock back
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

    private func flashBriefly(_ text: String) {
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
        guard !text.isEmpty else { return }
        let willLog = !forceTimer && preview?.action == "log"
        if !willLog {  // optimistic: show the timer immediately
            let label = forceTimer ? (preview?.label ?? text) : text
            timer = TimerInfo(id: "pending", label: label, start: Time.string(Date()))
        }
        flash = willLog ? describe(preview).map { "Logged \($0)" } : nil
        if !willLog { ghost = nil }  // starting a task brings you back from ghost mode
        Sound.saved.play()
        input = ""
        preview = nil
        run { try await API.post("log", ["text": text, "timer": forceTimer, "source": "button"]) }
        Task {
            try? await Task.sleep(for: .seconds(flash != nil ? 1.2 : 0.5))
            onSubmitted?()
            flash = nil
        }
    }

    func describe(_ p: LinePreview?) -> String? {
        guard let p, p.action == "log", let s = p.start, let e = p.end else { return nil }
        let end = p.untilNow == true ? "now" : Time.clockString(Time.parse(e))
        return "“\(p.label)”  \(Time.clockString(Time.parse(s)))–\(end)  (\(Time.minutes(p.minutes ?? 0)))"
    }

    private var poller: Task<Void, Never>?

    func startPolling() {
        poller?.cancel()
        poller = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshNow()
                try? await Task.sleep(for: .seconds(15))
            }
        }
    }

    func refreshNow() async {
        do {
            let now: NowState = try await API.get("now")
            if now.timer != timer { timer = now.timer }
            if now.ghost != ghost { ghost = now.ghost }
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

    func refreshAll() async {
        await refreshNow()
        await refreshDay()
    }

    // MARK: actions

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
