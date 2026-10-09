import Foundation
import SwiftUI

/// The app's state. Views read from here; actions go to the server, then refresh.
/// The UI updates optimistically where it can, so a click never waits on the network.
@MainActor
final class Store: ObservableObject {
    @Published var timer: TimerInfo?
    @Published var day: Date = Calendar.current.startOfDay(for: Date())
    @Published var timeline: Timeline?
    @Published var summary: Summary?
    @Published var serverDown = false
    @Published var error: String?
    @Published var focusRequest = 0  // bump to focus the input field

    var isToday: Bool { Calendar.current.isDateInToday(day) }

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
        let d = Time.dayString(day)
        do {
            async let tl: Timeline = API.get("timeline", query: ["date": d])
            async let sm: Summary = API.get("summary", query: ["date": d])
            timeline = try await tl
            summary = try await sm
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

    func start(_ label: String) {
        let label = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty else { return }
        timer = TimerInfo(id: "pending", label: label, start: Time.string(Date()))  // optimistic
        run { try await API.post("timer/start", ["label": label, "source": "button"]) }
    }

    func stop() {
        timer = nil  // optimistic
        run { try await API.post("timer/stop", ["source": "button"]) }
    }

    func logPast(_ label: String, minutes: Int) {
        let label = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty else { return }
        run { try await API.post("entries", ["label": label, "minutes": minutes, "source": "button"]) }
    }

    func log(_ label: String, from: Date, to: Date) {
        let label = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty, to > from else { return }
        run {
            try await API.post("entries", ["label": label, "start": Time.string(from),
                                           "end": Time.string(min(to, Date())), "source": "button"])
        }
    }

    func delete(_ seg: Segment) {
        guard let id = seg.id else { return }
        run { try await API.delete("entries/\(id)") }
    }

    func shiftDay(_ n: Int) {
        guard let d = Calendar.current.date(byAdding: .day, value: n, to: day) else { return }
        if d > Date() { return }
        day = d
        Task { await refreshDay() }
    }

    func goToday() {
        day = Calendar.current.startOfDay(for: Date())
        Task { await refreshDay() }
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
