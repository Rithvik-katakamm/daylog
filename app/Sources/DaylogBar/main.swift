import AppKit
import ApplicationServices
import SwiftUI

/// A borderless panel that can still take keyboard input (like Spotlight), without
/// activating the app, so whatever you were working in stays frontmost.
final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// The pill. Never takes focus.
final class HandlePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = Store()
    let recorder = ActivityRecorder()
    var handle: HandlePanel!
    var panel: KeyPanel!
    var hotKey: HotKey?
    var clickMonitor: Any?
    var keyMonitor: Any?

    private let handleSize = NSSize(width: 34, height: 52)
    private let panelSize = NSSize(width: 360, height: 600)

    func applicationDidFinishLaunching(_ note: Notification) {
        makeHandle()
        makePanel()
        hotKey = HotKey { [weak self] in MainActor.assumeIsolated { self?.toggle() } }
        watchOptionFn()
        recorder.start()
        store.startPolling()
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.placeHandle() }
        }
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

    private func makeHandle() {
        handle = HandlePanel(contentRect: NSRect(origin: .zero, size: handleSize),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        floating(handle)
        let view = HandleView(store: store)
            .gesture(DragGesture(minimumDistance: 3, coordinateSpace: .global)
                .onChanged { [weak self] v in self?.dragHandle(by: v.translation.height) }
                .onEnded { [weak self] _ in self?.endDrag() })
            .onTapGesture { [weak self] in self?.toggle() }
        handle.contentView = NSHostingView(rootView: view)
        placeHandle()
        handle.orderFrontRegardless()
    }

    private func makePanel() {
        panel = KeyPanel(contentRect: NSRect(origin: .zero, size: panelSize),
                         styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        floating(panel)
        panel.contentView = NSHostingView(rootView: PanelView(store: store))
    }

    // MARK: handle position (remembered, draggable vertically)

    private var dragOriginY: CGFloat?

    private var screen: NSRect { (NSScreen.main ?? NSScreen.screens[0]).visibleFrame }

    private func placeHandle() {
        let saved = UserDefaults.standard.object(forKey: "handleY") as? Double
        let y = saved.map { CGFloat($0) } ?? (screen.midY + 80)
        setHandle(y: y)
    }

    private func setHandle(y: CGFloat) {
        let clamped = min(max(y, screen.minY + 8), screen.maxY - handleSize.height - 8)
        handle.setFrameOrigin(NSPoint(x: screen.maxX - handleSize.width - 2, y: clamped))
        if panel?.isVisible == true { placePanel() }
    }

    private func dragHandle(by dy: CGFloat) {
        if dragOriginY == nil { dragOriginY = handle.frame.origin.y }
        setHandle(y: dragOriginY! - dy)  // screen y grows upward, drag y grows downward
    }

    private func endDrag() {
        UserDefaults.standard.set(Double(handle.frame.origin.y), forKey: "handleY")
        dragOriginY = nil
    }

    private func placePanel() {
        let h = handle.frame
        var y = h.midY - panelSize.height / 2
        y = min(max(y, screen.minY + 8), screen.maxY - panelSize.height - 8)
        panel.setFrame(NSRect(x: h.minX - panelSize.width - 8, y: y, width: panelSize.width,
                              height: panelSize.height), display: true)
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
