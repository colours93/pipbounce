import Cocoa

enum SFX { case hit, score, death, shoot, bounce }

class SoundKit {
    static let shared = SoundKit()
    private var sounds: [SFX: NSSound] = [:]

    private init() {}

    func preload() {
        let mapping: [(SFX, String)] = [
            (.hit, "Tink"), (.score, "Pop"), (.death, "Basso"),
            (.shoot, "Funk"), (.bounce, "Purr")
        ]
        for (sfx, name) in mapping {
            if let s = NSSound(named: NSSound.Name(name)) {
                sounds[sfx] = s
            }
        }
    }

    func play(_ sfx: SFX) {
        guard let s = sounds[sfx] else { return }
        if s.isPlaying { s.stop() }
        s.play()
    }
}
