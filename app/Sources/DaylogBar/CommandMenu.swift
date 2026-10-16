import Foundation

/// Every command in the bar, in one list. The menu (⌘K or `/`) renders it, and it
/// mirrors `docs/ui/keys.md`. When you add a command, add it here and in that doc.
///
/// Groups follow the color model's dimensions:
/// WHAT you're doing · HOW you are · GO somewhere (navigate) · DO something.
struct Command: Identifiable {
    enum Group: String, CaseIterable { case what = "WHAT", how = "HOW", go = "GO", act = "DO" }

    let id: String
    let group: Group
    let title: String
    let shortcut: String          // shown in the menu; "" = menu-only
    let isAvailable: @MainActor (Store) -> Bool
    let run: @MainActor () -> Void
}

@MainActor
enum Commands {
    /// Built once at launch. `hide` and `openDevApp` come from the window owner;
    /// `openDevApp` is nil inside the Dev app itself.
    static func all(store: Store, hide: @escaping () -> Void,
                    openDevApp: (() -> Void)?) -> [Command] {
        let always: @MainActor (Store) -> Bool = { _ in true }
        return [
            // WHAT am I doing / typing
            Command(id: "note", group: .what, title: "Note: a thought, timestamped", shortcut: "⌘N",
                    isAvailable: always, run: { store.beginNote() }),
            Command(id: "ghost", group: .what, title: "Ghost mode (off the clock)", shortcut: "⌘O",
                    isAvailable: { $0.ghost == nil }, run: { store.ghostKey() }),
            Command(id: "online", group: .what, title: "Back online", shortcut: "⌘O",
                    isAvailable: { $0.ghost != nil }, run: { store.ghostKey() }),

            Command(id: "walk", group: .what, title: "Walk break (task pauses)", shortcut: "⌘B",
                    isAvailable: { !$0.canComeBack && $0.ghost == nil }, run: { store.breakKey(smoke: false) }),
            Command(id: "smoke", group: .what, title: "Smoke break (come back high)", shortcut: "⌘⇧B",
                    isAvailable: { !$0.canComeBack && $0.ghost == nil }, run: { store.breakKey(smoke: true) }),
            Command(id: "unbreak", group: .what, title: "Back from break (resume the task)", shortcut: "⌘B",
                    isAvailable: { $0.canComeBack }, run: { store.breakKey(smoke: false) }),

            // HOW am I
            Command(id: "focus", group: .how, title: "Focus: step up a tier", shortcut: "⌘F",
                    isAvailable: { $0.timer != nil }, run: { store.cycleFocus() }),
            Command(id: "focus-off", group: .how, title: "Focus off", shortcut: "⌘⇧F",
                    isAvailable: { ($0.timer?.focus ?? 0) > 0 }, run: { store.focusOff() }),
            Command(id: "high", group: .how, title: "High (green ring)", shortcut: "⌘H",
                    isAvailable: always, run: { store.toggleState("high") }),
            Command(id: "intoxicated", group: .how, title: "Intoxicated (rose ring)", shortcut: "⌘I",
                    isAvailable: always, run: { store.toggleState("intoxicated") }),
            Command(id: "caffeinated", group: .how, title: "Caffeinated (brown ring)", shortcut: "⌘C",
                    isAvailable: always, run: { store.toggleState("caffeinated") }),

            // GO
            Command(id: "back", group: .go, title: "Look back through the day", shortcut: "↑",
                    isAvailable: always, run: { store.enterBrowse() }),
            Command(id: "edit", group: .go, title: "Edit the running or last block", shortcut: "↓",
                    isAvailable: always, run: { store.beginEdit() }),
            Command(id: "dev", group: .go, title: "Open the Dev app (latest build)", shortcut: "⌥D",
                    isAvailable: { _ in openDevApp != nil }, run: { openDevApp?() }),
            Command(id: "whats-new", group: .go, title: "What's new in this version", shortcut: "",
                    isAvailable: always, run: { store.whatsNew() }),
            Command(id: "work", group: .go, title: "Back to work (close)", shortcut: "Tab",
                    isAvailable: always, run: { hide() }),
            Command(id: "text-bigger", group: .go, title: "Text bigger", shortcut: "⌘=",
                    isAvailable: always, run: { store.resizeText(1) }),
            Command(id: "text-smaller", group: .go, title: "Text smaller", shortcut: "⌘−",
                    isAvailable: always, run: { store.resizeText(-1) }),
            Command(id: "text-reset", group: .go, title: "Text size: default", shortcut: "⌘0",
                    isAvailable: { $0.textScale != 1 }, run: { store.resizeText(0) }),
            Command(id: "screen-laptop", group: .go, title: "Pill on: MacBook (in the notch)", shortcut: "",
                    isAvailable: { $0.pillScreen != .laptop }, run: { store.pillScreen = .laptop }),
            Command(id: "screen-monitor", group: .go, title: "Pill on: monitor", shortcut: "",
                    isAvailable: { $0.pillScreen != .monitor }, run: { store.pillScreen = .monitor }),
            Command(id: "screen-follow", group: .go, title: "Pill follows my cursor", shortcut: "",
                    isAvailable: { $0.pillScreen != .follow }, run: { store.pillScreen = .follow }),
            Command(id: "rest-pill", group: .go, title: "Always on: center pill", shortcut: "",
                    isAvailable: { $0.restStyle != .pill }, run: { store.restStyle = .pill }),
            Command(id: "rest-ring", group: .go, title: "Always on: side ring", shortcut: "",
                    isAvailable: { $0.restStyle != .ring }, run: { store.restStyle = .ring }),
            Command(id: "rest-both", group: .go, title: "Always on: pill + ring", shortcut: "",
                    isAvailable: { $0.restStyle != .both }, run: { store.restStyle = .both }),
            Command(id: "rest-off", group: .go, title: "Always on: off (hide when closed)", shortcut: "",
                    isAvailable: { $0.restStyle != .off }, run: { store.restStyle = .off }),

            // DO
            Command(id: "stop", group: .act, title: "Stop the timer", shortcut: "⌘.",
                    isAvailable: { $0.timer != nil }, run: { store.stop() }),
            Command(id: "reset-dev", group: .act, title: "Reset dev data", shortcut: "",
                    isAvailable: { $0.env == .dev }, run: { store.resetDevData() }),
            Command(id: "dev-demo", group: .act, title: "Dev demo: pill states + the model, live", shortcut: "",
                    isAvailable: { $0.env == .dev }, run: { hide(); DevDemoWindow.show(store: store) }),
        ]
    }
}
