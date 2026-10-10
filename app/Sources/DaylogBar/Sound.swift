import AppKit

/// Deliberate, consistent sounds: every action of a kind always makes the same sound.
/// Most come from macOS's built-in palette (/System/Library/Sounds). The watch ticks are
/// daylog's own, synthesized by app/make_sounds.py and shipped inside the app bundle.
enum Sound {
    case open, mode, saved, ghost, tick, tock

    private var name: String {
        switch self {
        case .open: "Pop"
        case .mode: "Tink"
        case .saved: "Bottle"
        case .ghost: "Submarine"
        case .tick: "tick"
        case .tock: "tock"
        }
    }

    private var volume: Float {
        switch self {
        case .tick, .tock: 0.5  // tiny and dry, so it can repeat fast without grating
        default: 0.35
        }
    }

    @MainActor private static var cache: [String: NSSound] = [:]
    @MainActor private static var tickNext = true

    @MainActor private func load() -> NSSound? {
        switch self {
        case .tick, .tock:
            guard let url = Bundle.main.url(forResource: name, withExtension: "wav") else { return nil }
            return NSSound(contentsOf: url, byReference: true)
        default:
            return NSSound(named: NSSound.Name(name))
        }
    }

    @MainActor func play() {
        let s = Sound.cache[name] ?? load()
        Sound.cache[name] = s
        s?.stop()
        s?.volume = volume
        s?.play()
    }

    /// One step of a mechanical watch: alternates tick, tock, tick, tock.
    @MainActor static func watchStep() {
        (tickNext ? Sound.tick : Sound.tock).play()
        tickNext.toggle()
    }
}
