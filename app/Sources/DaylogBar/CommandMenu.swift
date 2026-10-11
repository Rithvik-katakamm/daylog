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

            // HOW am I
            Command(id: "focus", group: .how, title: "Focus: step up a tier", shortcut: "⌘F",
                    isAvailable: { $0.timer != nil }, run: { store.cycleFocus() }),

            // GO
            Command(id: "back", group: .go, title: "Look back through the day", shortcut: "↑",
                    isAvailable: always, run: { store.enterBrowse() }),
            Command(id: "edit", group: .go, title: "Edit the running or last block", shortcut: "↓",
                    isAvailable: always, run: { store.beginEdit() }),
            Command(id: "dev", group: .go, title: "Open the Dev app (latest build)", shortcut: "⌥D",
                    isAvailable: { _ in openDevApp != nil }, run: { openDevApp?() }),
            Command(id: "work", group: .go, title: "Back to work (close)", shortcut: "Tab",
                    isAvailable: always, run: { hide() }),

            // DO
            Command(id: "stop", group: .act, title: "Stop the timer", shortcut: "⌘.",
                    isAvailable: { $0.timer != nil }, run: { store.stop() }),
            Command(id: "reset-dev", group: .act, title: "Reset dev data", shortcut: "",
                    isAvailable: { $0.env == .dev }, run: { store.resetDevData() }),
        ]
    }
}
