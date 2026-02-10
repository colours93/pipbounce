import Foundation

class Settings {
    var enabled = true
    var cooldown: TimeInterval = 0.4
    var margin: CGFloat = 20
    var cornerSize: CGFloat = 100
    var glow = true
    var glowColor = "rainbow"        // rainbow, blue, red, purple, green
    var hotkeyCode: UInt16 = 2       // "d" key
    var hotkeyFlags: UInt32 = 0x108  // cmd+shift
}

let settings = Settings()
