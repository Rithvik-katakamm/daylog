import AppKit
import CoreGraphics
import Foundation

/// Passive observations: which app is in front, and when he's away.
///
/// It posts `app.focus` on every app switch, plus a heartbeat every 5 minutes so the
/// server knows the recorder is still alive. It posts `away.start` on lock, sleep or
/// 5 minutes idle. Each event carries its own timestamp, so if the server is down the
/// queue just waits and sends later with the original times intact.
@MainActor
final class ActivityRecorder {
    private let heartbeat: TimeInterval = 5 * 60
    private let idleThreshold: TimeInterval = 5 * 60
    private var away = false
    private var queue: [[String: Any]] = []
    private var sending = false
    private var timers: [Timer] = []

    func start() {
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { self?.focus(app) }
        }
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification,
                     NSWorkspace.sessionDidResignActiveNotification] {
            ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.goAway(reason: name.rawValue) }
            }
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification,
                     NSWorkspace.sessionDidBecomeActiveNotification] {
            ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.comeBack() }
            }
        }
        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.goAway(reason: "locked") }
        }
        dnc.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.comeBack() }
        }

        timers.append(Timer.scheduledTimer(withTimeInterval: heartbeat, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.beat() }
        })
        timers.append(Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkIdle() }
        })
        focus(NSWorkspace.shared.frontmostApplication)
    }

    // MARK: events

    private func focus(_ app: NSRunningApplication?, heartbeat: Bool = false) {
        guard let app else { return }
        away = false
        var data: [String: Any] = ["app": app.localizedName ?? app.bundleIdentifier ?? "unknown"]
        if let id = app.bundleIdentifier { data["bundle_id"] = id }
        if heartbeat { data["heartbeat"] = true }
        enqueue(type: "app.focus", at: Date(), data: data)
    }

    private func goAway(reason: String, since: Date = Date()) {
        guard !away else { return }
        away = true
        enqueue(type: "away.start", at: since, data: ["reason": reason])
    }

    private func comeBack() {
        guard away else { return }
        focus(NSWorkspace.shared.frontmostApplication)
    }

    private func beat() {
        guard !away else { return }
        focus(NSWorkspace.shared.frontmostApplication, heartbeat: true)
    }

    private func checkIdle() {
        // Seconds since any keyboard/mouse input. Needs no special permission.
        let anyInput = CGEventType(rawValue: ~0)!
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
        if idle >= idleThreshold && !away {
            goAway(reason: "idle", since: Date().addingTimeInterval(-idle))
        } else if idle < idleThreshold && away {
            comeBack()
        }
    }

    // MARK: delivery

    private func enqueue(type: String, at date: Date, data: [String: Any]) {
        queue.append(["type": type, "start": Time.string(date), "data": data, "source": "mac"])
        if queue.count > 5000 { queue.removeFirst(queue.count - 5000) }
        flush()
    }

    private func flush() {
        guard !sending, !queue.isEmpty else { return }
        sending = true
        Task {
            while let next = queue.first {
                do {
                    try await API.post("observations", next)
                    queue.removeFirst()
                } catch let f as API.Failure where (400..<500).contains(f.status) {
                    queue.removeFirst()  // the server rejected it; retrying won't help
                } catch {
                    break  // server unreachable: keep the queue, retry soon
                }
            }
            sending = false
            if !queue.isEmpty {
                try? await Task.sleep(for: .seconds(30))
                flush()
            }
        }
    }
}
