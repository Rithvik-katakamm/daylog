import AppKit
import ApplicationServices
import SwiftUI

/// A borderless panel that can still take keyboard input (like Spotlight), without
/// activating the app, so whatever you were working in stays frontmost.
final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = Store()
    let recorder = ActivityRecorder()
    var panel: KeyPanel!
    var hotKey: HotKey?
    var clickMonitor: Any?
    var keyMonitor: Any?

    static let panelSize = NSSize(width: 480, height: 190)

    func applicationDidFinishLaunching(_ note: Notification) {
        makePanel()
        store.onSubmitted = { [weak self] in self?.hide() }
        hotKey = HotKey { [weak self] in MainActor.assumeIsolated { self?.toggle() } }
        watchOptionFn()
        recorder.start()
        store.startPolling()
    }

    // MARK: ⌥ + fn (like Wispr Flow's fn key)

    private var optionFnDown = false
    private var flagMonitors: [Any] = []

    /// fn can't be a Carbon hotkey, so watch modifier changes directly. Seeing keys
    /// in other apps needs Accessibility permission for Daylog; we ask once.
    private func watchOptionFn() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
        let handler: (NSEvent) -> Void = { [weak self] e in
            let mods = e.modifierFlags.intersection([.command, .option, .control, .shift, .function])
            let down = mods == [.option, .function]
            MainActor.assumeIsolated {
                guard let self else { return }
                if down && !self.optionFnDown { self.toggle() }  // fire once per press
                self.optionFnDown = down
            }
        }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: handler) { flagMonitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged, handler: { handler($0); return $0 }) {
            flagMonitors.append(m)
        }
    }

    // MARK: windows

    private func floating(_ p: NSPanel) {
        p.level = .floating
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.hidesOnDeactivate = false
        p.isMovableByWindowBackground = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    }

    private func makePanel() {
        panel = KeyPanel(contentRect: NSRect(origin: .zero, size: Self.panelSize),
                         styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        floating(panel)
        panel.contentView = NSHostingView(rootView: PanelView(store: store))
    }

    // MARK: placement: top-center of the screen you're on, like Spotlight

    private func placePanel() {
        let screen = (NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
                      ?? NSScreen.screens[0]).visibleFrame
        let size = Self.panelSize
        let x = screen.midX - size.width / 2
        let y = screen.maxY - screen.height * 0.22 - size.height
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
    }

    // MARK: show / hide

    func toggle() {
        panel.isVisible ? hide() : show()
    }

    private func show() {
        placePanel()
        panel.makeKeyAndOrderFront(nil)
        store.focusRequest += 1
        Task { await store.refreshAll() }
        // Click anywhere outside daylog to dismiss.
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        }
        // Esc dismisses (unless a field is handling it).
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            if e.keyCode == 53 { MainActor.assumeIsolated { self?.hide() }; return nil }
            if e.keyCode == 36 && e.modifierFlags.contains(.shift) {  // ⇧⏎: force a timer
                MainActor.assumeIsolated { self?.store.submit(forceTimer: true) }
                return nil
            }
            return e
        }
    }

    private func hide() {
        panel.orderOut(nil)
        if let m = clickMonitor { NSEvent.removeMonitor(m); clickMonitor = nil }
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)  // no Dock icon, no menu bar
    app.run()
}
