import AppKit

/// Deliberate, consistent sounds: every action of a kind always makes the same sound.
/// (Before this, the only sounds were macOS's error beeps on unhandled keys.)
enum Sound {
    case open, mode, saved, ghost

    private var name: String {
        switch self {
        case .open: "Pop"
        case .mode: "Tink"
        case .saved: "Bottle"
        case .ghost: "Submarine"
        }
    }

    @MainActor private static var cache: [String: NSSound] = [:]

    @MainActor func play() {
        let s = Sound.cache[name] ?? NSSound(named: NSSound.Name(name))
        Sound.cache[name] = s
        s?.stop()
        s?.volume = 0.35
        s?.play()
    }
}
