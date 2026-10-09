import AppKit
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

    /// A transparent stage; the visible capsules are drawn inside it by SwiftUI.
    static let windowSize = NSSize(width: 620, height: 150)

    func applicationDidFinishLaunching(_ note: Notification) {
        makePanel()
        store.onSubmitted = { [weak self] in self?.hide() }
        hotKey = HotKey { [weak self] in MainActor.assumeIsolated { self?.toggle() } }
        recorder.start()
        store.startPolling()
    }

    // MARK: windows

    private func floating(_ p: NSPanel) {
        p.level = .floating
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false  // SwiftUI draws soft shadows under the capsules instead
        p.hidesOnDeactivate = false
        p.isMovableByWindowBackground = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    }

    private func makePanel() {
        panel = KeyPanel(contentRect: NSRect(origin: .zero, size: Self.windowSize),
                         styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        floating(panel)
        let host = NSHostingView(rootView: BarView(store: store))
        host.layer?.backgroundColor = .clear
        panel.contentView = host
    }

    // MARK: placement: bottom-center, above the Dock, on the screen your cursor is on

    private func placePanel() {
        let screen = (NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
                      ?? NSScreen.screens[0]).visibleFrame
        let size = Self.windowSize
        panel.setFrame(NSRect(x: screen.midX - size.width / 2, y: screen.minY + 14,
                              width: size.width, height: size.height), display: true)
    }

    // MARK: show / hide

    func toggle() {
        store.isOpen ? hide() : show()
    }

    private func show() {
        placePanel()
        panel.makeKeyAndOrderFront(nil)
        store.isOpen = true  // SwiftUI grows the bar out of the bottom of the screen
        store.focusRequest += 1
        Task { await store.refreshAll() }
        // Click anywhere outside daylog to dismiss.
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        }
        // Esc dismisses (unless a field is handling it).
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            if e.keyCode == 53 { MainActor.assumeIsolated { self?.hide() }; return nil }
            if e.keyCode == 47 && e.modifierFlags.contains(.command) {  // ⌘.: stop the timer
                MainActor.assumeIsolated { self?.store.stop() }
                return nil
            }
            if e.keyCode == 36 && e.modifierFlags.contains(.shift) {  // ⇧⏎: force a timer
                MainActor.assumeIsolated { self?.store.submit(forceTimer: true) }
                return nil
            }
            return e
        }
    }

    private func hide() {
        store.isOpen = false
        // Let the shrink animation play, then take the window away.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self, !self.store.isOpen else { return }
            self.panel.orderOut(nil)
        }
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
