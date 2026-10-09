import Foundation
import SwiftUI

/// The app's state. Views read from here; actions go to the server, then refresh.
/// The UI updates optimistically where it can, so a click never waits on the network.
@MainActor
final class Store: ObservableObject {
    @Published var timer: TimerInfo?
    @Published var summary: Summary?
    @Published var serverDown = false
    @Published var error: String?
    @Published var focusRequest = 0  // bump to focus the input field
    @Published var input = "" { didSet { if mode == .input { schedulePreview() } } }
    @Published var preview: LinePreview?
    @Published var flash: String?  // brief confirmation after an action
    @Published var isOpen = false   // drives the grow/shrink animation

    // Scrolling back through the past with ↑/↓.
    enum Mode: Equatable { case input, browse, fill, note }
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
        case .note: mode = .input; input = ""
        default: mode = .input
        }
    }

    /// ⌘N: jot a thought at this moment, tagged with the running task. Doesn't switch tasks.
    func beginNote() {
        input = ""
        preview = nil
        mode = .note
        focusRequest += 1
    }

    private func submitNote() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        input = ""
        flash = "Noted"
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

    func resetMode() {
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
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let willLog = !forceTimer && preview?.action == "log"
        if !willLog {  // optimistic: show the timer immediately
            let label = forceTimer ? (preview?.label ?? text) : text
            timer = TimerInfo(id: "pending", label: label, start: Time.string(Date()))
        }
        flash = willLog ? describe(preview).map { "Logged \($0)" } : nil
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
