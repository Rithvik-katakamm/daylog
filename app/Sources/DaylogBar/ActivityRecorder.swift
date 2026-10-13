import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// Passive observations: which app is in front, and when he's away.
///
/// each `app.focus` also carries the front window's title (Accessibility permission)
/// and, for Safari/Brave/Chrome, the current tab's URL (Automation permission). A title or
/// URL change inside the same app posts a new `app.focus`, checked every 30 seconds.
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
    private var lastContext = ""  // app|title|url of the last app.focus, to spot in-app changes

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
            MainActor.assumeIsolated { self?.checkIdle(); self?.checkContext() }
        })
        focus(NSWorkspace.shared.frontmostApplication)
    }

    // MARK: events

    private func focus(_ app: NSRunningApplication?, heartbeat: Bool = false) {
        guard let app else { return }
        away = false
        let name = app.localizedName ?? app.bundleIdentifier ?? "unknown"
        var data: [String: Any] = ["app": name]
        if let id = app.bundleIdentifier { data["bundle_id"] = id }
        let title = Self.windowTitle(app), url = Self.browserURL(app.bundleIdentifier)
        if let title, !title.isEmpty { data["title"] = String(title.prefix(300)) }
        if let url, !url.isEmpty { data["url"] = String(url.prefix(500)) }
        lastContext = "\(name)|\(title ?? "")|\(url ?? "")"
        if heartbeat { data["heartbeat"] = true }
        enqueue(type: "app.focus", at: Date(), data: data)
    }

    /// Same app, different window or tab (a new Safari site, another iTerm tab): log it.
    private func checkContext() {
        guard !away, let app = NSWorkspace.shared.frontmostApplication else { return }
        let name = app.localizedName ?? app.bundleIdentifier ?? "unknown"
        let ctx = "\(name)|\(Self.windowTitle(app) ?? "")|\(Self.browserURL(app.bundleIdentifier) ?? "")"
        if ctx != lastContext { focus(app) }
    }

    /// Ask once for Accessibility (window titles). macOS shows its own prompt; if he says no,
    /// titles are simply absent and everything else keeps working.
    static func requestTitleAccess() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    private static func windowTitle(_ app: NSRunningApplication) -> String? {
        guard AXIsProcessTrusted() else { return nil }
        let ax = AXUIElementCreateApplication(app.processIdentifier)
        var win: CFTypeRef?
        guard AXUIElementCopyAttributeValue(ax, kAXFocusedWindowAttribute as CFString, &win) == .success,
              let win, CFGetTypeID(win) == AXUIElementGetTypeID() else { return nil }
        var title: CFTypeRef?
        guard AXUIElementCopyAttributeValue(win as! AXUIElement, kAXTitleAttribute as CFString, &title) == .success
        else { return nil }
        return title as? String
    }

    private static func browserURL(_ bundle: String?) -> String? {
        let tab: String
        switch bundle {
        case "com.apple.Safari": tab = "tell application \"Safari\" to if (count of windows) > 0 then return URL of current tab of front window"
        case "com.brave.Browser": tab = "tell application \"Brave Browser\" to if (count of windows) > 0 then return URL of active tab of front window"
        case "com.google.Chrome": tab = "tell application \"Google Chrome\" to if (count of windows) > 0 then return URL of active tab of front window"
        default: return nil
        }
        var err: NSDictionary?
        return NSAppleScript(source: tab)?.executeAndReturnError(&err).stringValue
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
                    try await API.post("observations", next, env: .real)  // never into the dev DB
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
