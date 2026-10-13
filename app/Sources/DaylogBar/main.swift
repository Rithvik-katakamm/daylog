import AppKit
import Combine
import Carbon.HIToolbox
import SwiftUI

/// A borderless panel that can still take keyboard input (like Spotlight).
final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Two channels, one codebase (see docs/infra/install.md):
/// - **Stable** `Daylog.app` (com.rithvik.daylog): what he uses. ⌥L opens it; ⌥D hands off to Dev.
///   Built from a tagged release, talks to the real server, records Mac activity.
/// - **Dev** `Daylog Dev.app` (com.rithvik.daylog.dev): the latest build, for trying and testing
///   new work. Dev database only, DEV tag, no global hotkeys, no activity recording, and a
///   private test channel so an agent can drive it without touching his keyboard or focus.
enum Flavor {
    static let stableID = "com.rithvik.daylog"
    static let devID = "com.rithvik.daylog.dev"
    static let isDev = Bundle.main.bundleIdentifier == devID
    /// Headless testing (his default, Oct 13): the Dev app runs with every window off-screen and no sound,
    /// so tests never appear on his screens. Started by `devctl start` (DAYLOG_HEADLESS=1). See docs/testing/.
    static let headless = isDev && ProcessInfo.processInfo.environment["DAYLOG_HEADLESS"] == "1"
    static let offscreen = NSPoint(x: -30000, y: -30000)

    /// Stable → Dev: "toggle your bar". Dev ← agent: test commands.
    static let devToggle = Notification.Name("com.rithvik.daylog.dev.toggle")
    static let devTest = Notification.Name("com.rithvik.daylog.dev.test")
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = Store()
    let recorder = ActivityRecorder()
    var panel: KeyPanel!
    var hotKey: HotKey?
    var devHotKey: HotKey?
    var ringPanel: NSPanel!
    var clickMonitor: Any?
    var keyMonitor: Any?

    /// A transparent stage; SwiftUI draws the capsules inside it. It only grows tall while
    /// the command menu is open, so it never sits over the screen when it doesn't need to.
    static let windowSize = NSSize(width: 620, height: 170)
    static let menuWindowSize = NSSize(width: 620, height: 470)
    private var modeWatch: AnyCancellable?
    private var restWatch: AnyCancellable?

    func applicationDidFinishLaunching(_ note: Notification) {
        makePanel()
        makeRingPanel()
        restWatch = store.$restStyle.removeDuplicates().sink { [weak self] _ in
            DispatchQueue.main.async { self?.applyRest() }
        }
        store.onSubmitted = { [weak self] in self?.hide() }
        store.onPlacementChange = { [weak self] in DispatchQueue.main.async { self?.placePanel() } }
        modeWatch = store.$mode.removeDuplicates().sink { [weak self] m in
            DispatchQueue.main.async { self?.placePanel(menu: m == .menu) }
        }
        store.commands = Commands.all(
            store: store,
            hide: { [weak self] in self?.hide() },
            openDevApp: Flavor.isDev ? nil : { [weak self] in self?.hide(); Self.openDevApp() })

        if Flavor.isDev {
            redirectLogs()
            store.env = .dev
            let dnc = DistributedNotificationCenter.default()
            dnc.addObserver(forName: Flavor.devToggle, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.toggle() }
            }
            dnc.addObserver(forName: Flavor.devTest, object: nil, queue: .main) { [weak self] n in
                let info = n.userInfo as? [String: String] ?? [:]
                print("test-recv raw=\(String(describing: n.userInfo)) parsed=\(info)"); fflush(stdout)
                MainActor.assumeIsolated { self?.runTestCommand(info) }
            }
            print("dev app ready"); fflush(stdout)
        } else {
            hotKey = HotKey(id: 1) { [weak self] in MainActor.assumeIsolated { self?.toggle() } }
            devHotKey = HotKey(keyCode: UInt32(kVK_ANSI_D), id: 2) { MainActor.assumeIsolated { Self.openDevApp() } }
            ActivityRecorder.requestTitleAccess()  // window titles (asks once)
            recorder.start()  // only stable records what's in front of you
            Self.watchForCD()
        }
        store.startPolling()
    }

    // MARK: CD on unlock

    /// When he's back at the Mac (unlock or wake), start the autorelease job: it pulls main from GitHub and
    /// releases it if the tests pass. Never on a timer: a closed Mac runs nothing, and polling costs battery.
    static func watchForCD() {
        let kick = {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            p.arguments = ["kickstart", "gui/\(getuid())/com.rithvik.daylog.autorelease"]  // no-op if already running
            try? p.run()
        }
        DistributedNotificationCenter.default().addObserver(
            forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { _ in kick() }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in kick() }
    }

    // MARK: Dev app handoff (stable's ⌥D)

    static func openDevApp() {
        let devURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications/Daylog Dev.app")
        let post = { DistributedNotificationCenter.default()
            .postNotificationName(Flavor.devToggle, object: nil, userInfo: nil, deliverImmediately: true) }
        if NSRunningApplication.runningApplications(withBundleIdentifier: Flavor.devID).isEmpty {
            guard FileManager.default.fileExists(atPath: devURL.path) else {
                print("dev app not built: run scripts/dev.sh"); fflush(stdout); return
            }
            NSWorkspace.shared.openApplication(at: devURL, configuration: .init()) { _, _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: post)
            }
        } else {
            post()
        }
    }

    private func redirectLogs() {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/daylog")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        freopen(dir.appendingPathComponent("app-dev.log").path, "a", stdout)
    }

    // MARK: test channel (Dev app only): drive the bar without the real keyboard or focus

    /// Commands: open · close · key (code, mods) · type (text) · state.
    /// Keys go through the same `handleKey` as real keypresses; text goes straight into the field.
    private func runTestCommand(_ info: [String: String]) {
        switch info["cmd"] {
        case "open": if !(store.isOpen && panel.isVisible) { show(activate: false) }
        case "close": hide(restoreFocus: false)
        case "key":
            let code = UInt16(info["code"] ?? "") ?? 0
            var mods: NSEvent.ModifierFlags = []
            for m in (info["mods"] ?? "").split(separator: ",") {
                switch m { case "cmd": mods.insert(.command); case "shift": mods.insert(.shift)
                           case "opt": mods.insert(.option); case "ctrl": mods.insert(.control); default: break }
            }
            if !handleKey(code, mods) && code == 36 { store.submit() }  // ⏎ in the typing line
        case "type": store.input += info["text"] ?? ""
        case "snap": snapshot(name: info["name"] ?? "latest")
        default: break
        }
        // Report state after every command, so tests can assert on it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let s = self?.store else { return }
            print("test-state mode=\(s.mode) input=\"\(s.input)\" open=\(s.isOpen) menuIndex=\(s.menuIndex) "
                  + "items=\(s.mode == .menu ? s.menuItems.map(\.id).joined(separator: ",") : "-") "
                  + "timer=\(s.timer?.label ?? "-") focus=\(s.timer?.focus ?? 0) "
                  + "break=\(s.onBreak?.kind ?? "-") states=\(s.states.sorted().joined(separator: ",")) "
                  + "ghost=\(s.ghost?.status ?? "-") rest=\(s.restStyle.rawValue)")
            fflush(stdout)
        }
    }

    /// Headless check: save a PNG of the bar exactly as drawn (the panel is off-screen, so this is how
    /// a test "sees" it). Written to ~/Library/Logs/daylog/snapshots/<name>.png.
    private func snapshot(name: String) {
        guard let view = panel.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/daylog/snapshots")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let safe = name.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        let url = dir.appendingPathComponent("\(safe.isEmpty ? "latest" : safe).png")
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        print("test-snap \(url.path)"); fflush(stdout)
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
        // Above the menu bar, at the screen-saver layer. Oct 13: the menu-bar level (79f84da) wasn't
        // enough. Modern macOS slides each desktop's menu bar with the three-finger swipe, so a pill at
        // that level slid away with the old desktop (his photo, IMG_2496). This layer belongs to no
        // desktop, so the pill should stay pinned on the notch while the desktops move under it.
        // Needs a real swipe to verify (gestures can't be scripted); roll back with release.sh v0.15.
        panel.level = .screenSaver
        let host = NSHostingView(rootView: BarView(store: store))
        host.layer?.backgroundColor = .clear
        panel.contentView = host
    }

    /// The side ring: its own tiny window on the right edge. It never takes clicks or the keyboard.
    private func makeRingPanel() {
        ringPanel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 96, height: 96),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        floating(ringPanel)
        ringPanel.ignoresMouseEvents = true
        let host = NSHostingView(rootView: SideRing(store: store).environment(\.colorScheme, .dark))
        host.layer?.backgroundColor = .clear
        ringPanel.contentView = host
    }

    /// Always-on display while the bar is closed: the center pill, the side ring, both, or off.
    private func applyRest() {
        if store.showsRing {
            let screen = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
            ringPanel.setFrameOrigin(Flavor.headless ? Flavor.offscreen : NSPoint(x: screen.maxX - 96 + 12, y: screen.midY - 48))
            ringPanel.orderFrontRegardless()
        } else {
            ringPanel.orderOut(nil)
        }
        if !store.isOpen {
            if store.showsPill {
                placePanel()
                panel.ignoresMouseEvents = true  // a glance, not a target: clicks go to the app below
                panel.orderFrontRegardless()
            } else {
                panel.orderOut(nil)
            }
        }
    }

    // MARK: placement: top-center, just under the menu bar, on the screen your cursor is on

    private func placePanel(menu: Bool = false) {
        let cursor = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
        let laptop = NSScreen.screens.first { $0.safeAreaInsets.top > 0 }
        let monitor = NSScreen.screens.first { $0.safeAreaInsets.top == 0 }
        let scr: NSScreen = switch store.pillScreen {
            case .laptop: laptop ?? cursor ?? NSScreen.screens[0]
            case .monitor: monitor ?? cursor ?? NSScreen.screens[0]
            case .follow: cursor ?? NSScreen.main ?? NSScreen.screens[0]
        }
        let f = scr.frame
        // The notch: macOS reports the usable areas left and right of it; the gap is the camera.
        var notch: CGFloat = 0
        if let l = scr.auxiliaryTopLeftArea, let r = scr.auxiliaryTopRightArea {
            notch = max(0, f.width - l.width - r.width)
        }
        // The full menu bar height (38pt on a 14" MacBook Pro; the notch itself is 32), so the closed
        // pill's bottom edge lines up with the menu bar and wraps just past the notch.
        let menuBar = max(f.maxY - scr.visibleFrame.maxY, scr.safeAreaInsets.top, 24)
        if store.notchWidth != notch { store.notchWidth = notch }
        if store.topInset != menuBar { store.topInset = menuBar }
        let size = menu ? Self.menuWindowSize : Self.windowSize
        // Flush with the very top of the screen, over the menu bar, centered on the notch.
        panel.setFrame(NSRect(x: f.midX - size.width / 2, y: f.maxY - size.height,
                              width: size.width, height: size.height), display: true)
        if Flavor.headless { panel.setFrameOrigin(Flavor.offscreen) }  // drawn, never on a screen
    }

    // MARK: show / hide

    func toggle() {
        // Trust what's on screen, not just our flag, so the two can never drift apart.
        let open = store.isOpen && panel.isVisible
        print("toggle: \(open ? "close" : "open")"); fflush(stdout)
        open ? hide() : show()
    }

    /// The app you were in when you opened the bar. Closing hands the keyboard back to it.
    private var previousApp: NSRunningApplication?

    /// `activate: false` shows the bar without taking focus (used by the test channel).
    private func show(activate: Bool = true) {
        removeMonitors()  // never stack monitors if show() runs twice
        panel.ignoresMouseEvents = false
        placePanel()
        // Start moving on the very next frame: show + animate first, take the keyboard right after.
        // (Activating the app first cost a frame or two before anything moved.)
        panel.orderFrontRegardless()
        store.isOpen = true  // SwiftUI grows the bar down from the top of the screen
        if activate {
            let front = NSWorkspace.shared.frontmostApplication
            if front?.bundleIdentifier != Bundle.main.bundleIdentifier { previousApp = front }
            // Take the keyboard so you can type immediately (no click needed).
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKey()
        }
        if activate { Sound.open.play() }
        // Focus the field once SwiftUI has laid it out.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in self?.store.focusRequest += 1 }
        Task { await store.refreshAll(); await store.refreshHealth(); store.noteGuessShown() }
        guard activate else { return }
        // Click anywhere outside daylog to dismiss. The click already picked the app you
        // want, so don't hand focus back to the old one.
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide(restoreFocus: false) }
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self else { return e }
            return MainActor.assumeIsolated { self.handleKey(e.keyCode, e.modifierFlags) } ? nil : e
        }
    }

    /// Every bar shortcut, in one place. Returns true if the key was handled.
    /// Real keypresses and the Dev app's test channel both come through here.
    @discardableResult
    func handleKey(_ code: UInt16, _ flags: NSEvent.ModifierFlags) -> Bool {
        let store = self.store
        let cmd = flags.contains(.command)
        let shift = flags.contains(.shift)
        let noMods = flags.intersection([.command, .option, .control, .shift]).isEmpty
        switch (code, store.mode) {
        // Command menu: ⌘K anywhere, or / on an empty line.
        case (40, let m) where cmd && m != .menu: store.openMenu()
        case (44, .input) where noMods && store.input.isEmpty: store.openMenu()
        case (126, .menu): store.menuMove(-1)
        case (125, .menu): store.menuMove(1)
        case (36, .menu): store.runSelectedCommand()
        case (53, .input): hide()                                          // esc: close
        case (48, _): hide()                                               // tab: back to work
        case (125, .input) where store.input.isEmpty: store.beginEdit()    // ↓ edit last block
        case (125, .edit), (126, .edit):                                   // ↓↑ move the end
            let step = shift ? 15 : 5
            store.nudgeEnd(minutes: code == 126 ? step : -step)
        case (53, _): store.back()                                         // esc: step back
        case (126, .browse): store.older()                                 // ↑ earlier
        case (125, .browse): store.newer()                                 // ↓ later
        case (126, .input) where store.input.isEmpty: store.enterBrowse()  // ↑ look back
        case (36, .browse): store.beginFill()
        // ⏎ in the non-typing modes is handled here, not by the text field, so it works
        // even if the field hasn't taken focus yet.
        case (36, .edit), (36, .note), (36, .ghost), (36, .fill): store.submit()
        case (36, .input) where shift: store.submit(forceTimer: true)      // ⇧⏎ force a timer
        case (45, .input) where cmd: store.beginNote()                     // ⌘N
        case (31, .input) where cmd: store.ghostKey()                      // ⌘O
        case (3, .input) where cmd && shift: store.focusOff()              // ⌘⇧F focus off
        case (3, .input) where cmd: store.cycleFocus()                     // ⌘F
        case (11, .input) where cmd: store.breakKey(smoke: shift)          // ⌘B walk · ⌘⇧B smoke
        case (4, .input) where cmd: store.toggleState("high")              // ⌘H high (bar wins over Hide)
        case (34, .input) where cmd: store.toggleState("intoxicated")      // ⌘I
        case (8, .input) where cmd: store.toggleState("caffeinated")       // ⌘C coffee (bar wins over Copy)
        case (47, _) where cmd: store.stop()                               // ⌘. stop
        case (24, _) where cmd: store.resizeText(1)                        // ⌘= bigger text
        case (27, _) where cmd: store.resizeText(-1)                       // ⌘− smaller
        case (29, _) where cmd: store.resizeText(0)                        // ⌘0 reset
        case (51, .browse) where cmd: store.deleteCurrent()                // ⌘⌫ delete
        case (51, .input) where noMods && store.input.isEmpty && store.cutOffer != nil:
            store.acceptCut()                                              // ⌫ cut at away
        default: return false
        }
        return true
    }

    private func hide(restoreFocus: Bool = true) {
        store.isOpen = false
        removeMonitors()
        // Give the keyboard back to whatever you were doing before opening the bar.
        if restoreFocus, let app = previousApp { app.activate() }
        // Let the shrink animation play, then take the window away.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in  // let it retract first
            guard let self, !self.store.isOpen else { return }
            if self.store.showsPill {
                self.panel.ignoresMouseEvents = true  // stays as the dimmed pill
            } else {
                self.panel.orderOut(nil)
            }
            self.store.resetMode()  // next open starts fresh: typing mode, empty field
        }
    }

    private func removeMonitors() {
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
