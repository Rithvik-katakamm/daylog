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
    @Published var input = "" { didSet { schedulePreview() } }
    @Published var preview: LinePreview?
    @Published var flash: String?  // brief confirmation after an action

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

    /// ⏎: a time in the text logs it; otherwise starts a timer. ⇧⏎ forces a timer.
    func submit(forceTimer: Bool = false) {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let willLog = !forceTimer && preview?.action == "log"
        if !willLog {  // optimistic: show the timer immediately
            let label = forceTimer ? (preview?.label ?? text) : text
            timer = TimerInfo(id: "pending", label: label, start: Time.string(Date()))
        }
        flash = willLog ? describe(preview) : nil
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
