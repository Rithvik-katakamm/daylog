import AppKit

/// Deliberate, consistent sounds: every action of a kind always makes the same sound.
/// They come from macOS's built-in palette (/System/Library/Sounds). The full sound design
/// is its own card; a synthesized watch tick was tried and dropped on Oct 10.
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

    private var volume: Float { 0.35 }

    @MainActor private static var cache: [String: NSSound] = [:]
    @MainActor private func load() -> NSSound? { NSSound(named: NSSound.Name(name)) }

    @MainActor func play() {
        guard !Flavor.headless else { return }  // headless tests are silent
        let s = Sound.cache[name] ?? load()
        Sound.cache[name] = s
        s?.stop()
        s?.volume = volume
        s?.play()
    }

}
