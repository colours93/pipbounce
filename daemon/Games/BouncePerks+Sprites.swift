import Cocoa

// MARK: - Perk Pixel Art Icons (16×16, rendered at 3x = 48×48)

extension Perk {
    var icon: CGImage? {
        switch self {
        case .thicc:      return PerkSprites.thicc
        case .slowmo:     return PerkSprites.slowmo
        case .freeze:     return PerkSprites.freeze
        case .drunk:      return PerkSprites.drunk
        case .ghost:      return PerkSprites.ghost
        case .earthquake: return PerkSprites.earthquake
        case .homing:     return PerkSprites.homing
        case .gravityWell: return PerkSprites.gravityWell
        case .shrinkRay:  return PerkSprites.shrinkRay
        case .multiHit:   return PerkSprites.multiHit
        case .ricochet:   return PerkSprites.ricochet
        case .steelFist:  return PerkSprites.steelFist
        }
    }

    var color: NSColor {
        switch self {
        case .thicc:      return NSColor(hex: 0xFF8833)
        case .slowmo:     return NSColor(hex: 0x44DDFF)
        case .freeze:     return NSColor(hex: 0xAADDFF)
        case .drunk:      return NSColor(hex: 0xBBDD33)
        case .ghost:      return NSColor(hex: 0xCCCCCC)
        case .earthquake: return NSColor(hex: 0xAA6633)
        case .homing:     return NSColor(hex: 0xFF4444)
        case .gravityWell: return NSColor(hex: 0x9944FF)
        case .shrinkRay:  return NSColor(hex: 0x33DD66)
        case .multiHit:   return NSColor(hex: 0xFFDD44)
        case .ricochet:   return NSColor(hex: 0x4488FF)
        case .steelFist:  return NSColor(hex: 0xBBBBCC)
        }
    }
}

private extension NSColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1.0)
    }
}

// All sprites as static computed properties to avoid startup cost
enum PerkSprites {
    private static let s = 3 // scale

    // Expanding arrows outward — Orange
    static let thicc: CGImage? = GameBase.renderPixelArt([
        [0,0,0,0,0,0,0,0xFF8833,0xFF8833,0,0,0,0,0,0,0],
        [0,0,0,0,0,0,0xFF8833,0xFFAA55,0xFFAA55,0xFF8833,0,0,0,0,0,0],
        [0,0,0,0,0,0xFF8833,0,0,0,0,0xFF8833,0,0,0,0,0],
        [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
        [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
        [0,0,0xFF8833,0,0,0,0,0,0,0,0,0,0,0xFF8833,0,0],
        [0,0xFF8833,0,0,0,0,0,0,0,0,0,0,0,0,0xFF8833,0],
        [0xFF8833,0xFFAA55,0,0,0,0,0,0,0,0,0,0,0,0xFFAA55,0xFF8833,0],
        [0xFF8833,0xFFAA55,0,0,0,0,0,0,0,0,0,0,0,0xFFAA55,0xFF8833,0],
        [0,0xFF8833,0,0,0,0,0,0,0,0,0,0,0,0,0xFF8833,0],
        [0,0,0xFF8833,0,0,0,0,0,0,0,0,0,0,0xFF8833,0,0],
        [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
        [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
        [0,0,0,0,0,0xFF8833,0,0,0,0,0xFF8833,0,0,0,0,0],
        [0,0,0,0,0,0,0xFF8833,0xFFAA55,0xFFAA55,0xFF8833,0,0,0,0,0,0],
        [0,0,0,0,0,0,0,0xFF8833,0xFF8833,0,0,0,0,0,0,0],
    ], scale: s)

    // Clock with slow hands — Cyan
    static let slowmo: CGImage? = GameBase.renderPixelArt([
        [0,0,0,0,0,0x44DDFF,0x44DDFF,0x44DDFF,0x44DDFF,0x44DDFF,0x44DDFF,0,0,0,0,0],
        [0,0,0,0x44DDFF,0x44DDFF,0,0,0,0,0,0,0x44DDFF,0x44DDFF,0,0,0],
        [0,0,0x44DDFF,0,0,0,0,0,0,0,0,0,0,0x44DDFF,0,0],
        [0,0x44DDFF,0,0,0,0,0,0,0,0,0,0,0,0,0x44DDFF,0],
        [0,0x44DDFF,0,0,0,0,0,0x88EEFF,0,0,0,0,0,0,0x44DDFF,0],
        [0x44DDFF,0,0,0,0,0,0,0x88EEFF,0,0,0,0,0,0,0,0x44DDFF],
        [0x44DDFF,0,0,0,0,0,0,0x88EEFF,0,0,0,0,0,0,0,0x44DDFF],
        [0x44DDFF,0,0,0,0,0,0,0x88EEFF,0x88EEFF,0x88EEFF,0,0,0,0,0,0x44DDFF],
        [0x44DDFF,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0x44DDFF],
        [0x44DDFF,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0x44DDFF],
        [0x44DDFF,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0x44DDFF],
        [0,0x44DDFF,0,0,0,0,0,0,0,0,0,0,0,0,0x44DDFF,0],
        [0,0x44DDFF,0,0,0,0,0,0,0,0,0,0,0,0,0x44DDFF,0],
        [0,0,0x44DDFF,0,0,0,0,0,0,0,0,0,0,0x44DDFF,0,0],
        [0,0,0,0x44DDFF,0x44DDFF,0,0,0,0,0,0,0x44DDFF,0x44DDFF,0,0,0],
        [0,0,0,0,0,0x44DDFF,0x44DDFF,0x44DDFF,0x44DDFF,0x44DDFF,0x44DDFF,0,0,0,0,0],
    ], scale: s)

    // Snowflake — Ice blue
    static let freeze: CGImage? = GameBase.renderPixelArt([
        [0,0,0,0,0,0,0,0xAADDFF,0xAADDFF,0,0,0,0,0,0,0],
        [0,0,0,0,0,0,0,0xCCEEFF,0,0,0,0,0,0,0,0],
        [0,0,0xAADDFF,0,0,0,0,0xAADDFF,0,0,0,0,0xAADDFF,0,0,0],
        [0,0,0,0xCCEEFF,0,0,0,0xAADDFF,0,0,0,0xCCEEFF,0,0,0,0],
        [0,0,0,0,0xAADDFF,0,0,0xAADDFF,0,0,0xAADDFF,0,0,0,0,0],
        [0,0,0,0,0,0xCCEEFF,0,0xAADDFF,0,0xCCEEFF,0,0,0,0,0,0],
        [0,0,0,0,0,0,0xAADDFF,0xAADDFF,0xAADDFF,0,0,0,0,0,0,0],
        [0xAADDFF,0xCCEEFF,0xAADDFF,0xAADDFF,0xAADDFF,0xAADDFF,0xAADDFF,0xFFFFFF,0xAADDFF,0xAADDFF,0xAADDFF,0xAADDFF,0xAADDFF,0xCCEEFF,0xAADDFF,0],
        [0,0,0,0,0,0,0xAADDFF,0xAADDFF,0xAADDFF,0,0,0,0,0,0,0],
        [0,0,0,0,0,0xCCEEFF,0,0xAADDFF,0,0xCCEEFF,0,0,0,0,0,0],
        [0,0,0,0,0xAADDFF,0,0,0xAADDFF,0,0,0xAADDFF,0,0,0,0,0],
        [0,0,0,0xCCEEFF,0,0,0,0xAADDFF,0,0,0,0xCCEEFF,0,0,0,0],
        [0,0,0xAADDFF,0,0,0,0,0xAADDFF,0,0,0,0,0xAADDFF,0,0,0],
        [0,0,0,0,0,0,0,0xCCEEFF,0,0,0,0,0,0,0,0],
        [0,0,0,0,0,0,0,0xAADDFF,0xAADDFF,0,0,0,0,0,0,0],
        [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
    ], scale: s)

    // Wobbly spiral — Yellow-green
    static let drunk: CGImage? = GameBase.renderPixelArt([
        [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
        [0,0,0,0,0,0xBBDD33,0xBBDD33,0xBBDD33,0xBBDD33,0xBBDD33,0,0,0,0,0,0],
        [0,0,0,0xBBDD33,0xBBDD33,0,0,0,0,0,0xBBDD33,0,0,0,0,0],
        [0,0,0xBBDD33,0,0,0,0,0,0,0,0,0xBBDD33,0,0,0,0],
        [0,0,0xBBDD33,0,0,0,0xDDEE66,0xDDEE66,0xDDEE66,0,0,0xBBDD33,0,0,0],
        [0,0,0,0,0,0xDDEE66,0,0,0,0,0xDDEE66,0,0xBBDD33,0,0],
        [0,0,0,0,0,0xDDEE66,0,0,0,0,0,0,0xBBDD33,0,0,0],
        [0,0,0,0,0,0,0,0xFFFF88,0,0,0,0xDDEE66,0,0,0,0],
        [0,0,0,0,0,0,0,0,0,0,0xDDEE66,0,0,0,0,0],
        [0,0,0xBBDD33,0,0,0,0,0,0,0xDDEE66,0,0,0,0,0,0],
        [0,0xBBDD33,0,0,0,0xDDEE66,0,0xDDEE66,0,0,0,0,0,0,0,0],
        [0,0xBBDD33,0,0,0,0,0xDDEE66,0xDDEE66,0,0,0,0,0,0,0,0],
        [0,0,0xBBDD33,0,0,0,0,0,0,0,0,0,0,0,0,0],
        [0,0,0,0xBBDD33,0xBBDD33,0,0,0,0,0,0,0,0,0,0,0],
        [0,0,0,0,0,0xBBDD33,0xBBDD33,0xBBDD33,0xBBDD33,0,0,0,0,0,0,0],
        [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
    ], scale: s)

    // Fading ghost — White/gray
    static let ghost: CGImage? = GameBase.renderPixelArt([
        [0,0,0,0,0,0x999999,0xCCCCCC,0xCCCCCC,0xCCCCCC,0xCCCCCC,0x999999,0,0,0,0,0],
        [0,0,0,0,0x999999,0xCCCCCC,0xEEEEEE,0xEEEEEE,0xEEEEEE,0xEEEEEE,0xCCCCCC,0x999999,0,0,0,0],
        [0,0,0,0x999999,0xCCCCCC,0xEEEEEE,0xEEEEEE,0xEEEEEE,0xEEEEEE,0xEEEEEE,0xEEEEEE,0xCCCCCC,0x999999,0,0,0],
        [0,0,0x999999,0xCCCCCC,0xEEEEEE,0xEEEEEE,0xEEEEEE,0xEEEEEE,0xEEEEEE,0xEEEEEE,0xEEEEEE,0xEEEEEE,0xCCCCCC,0x999999,0,0],
        [0,0x999999,0xCCCCCC,0xEEEEEE,0x444444,0x222222,0xEEEEEE,0xEEEEEE,0xEEEEEE,0x444444,0x222222,0xEEEEEE,0xCCCCCC,0x999999,0,0],
        [0,0x999999,0xCCCCCC,0xEEEEEE,0x222222,0x000001,0xEEEEEE,0xEEEEEE,0xEEEEEE,0x222222,0x000001,0xEEEEEE,0xCCCCCC,0x999999,0,0],
        [0,0x999999,0xCCCCCC,0xEEEEEE,0xEEEEEE,0xEEEEEE,0xEEEEEE,0xEEEEEE,0xEEEEEE,0xEEEEEE,0xEEEEEE,0xEEEEEE,0xCCCCCC,0x999999,0,0],
        [0,0x999999,0xCCCCCC,0xEEEEEE,0xEEEEEE,0xEEEEEE,0x888888,0xEEEEEE,0xEEEEEE,0x888888,0xEEEEEE,0xEEEEEE,0xCCCCCC,0x999999,0,0],
        [0,0x999999,0xCCCCCC,0xEEEEEE,0xEEEEEE,0xEEEEEE,0xEEEEEE,0x888888,0x888888,0xEEEEEE,0xEEEEEE,0xEEEEEE,0xCCCCCC,0x999999,0,0],
        [0,0x999999,0xCCCCCC,0xEEEEEE,0xEEEEEE,0xEEEEEE,0xEEEEEE,0xEEEEEE,0xEEEEEE,0xEEEEEE,0xEEEEEE,0xEEEEEE,0xCCCCCC,0x999999,0,0],
        [0,0x999999,0xCCCCCC,0xEEEEEE,0xEEEEEE,0xEEEEEE,0xEEEEEE,0xEEEEEE,0xEEEEEE,0xEEEEEE,0xEEEEEE,0xEEEEEE,0xCCCCCC,0x999999,0,0],
        [0,0x999999,0xCCCCCC,0xEEEEEE,0xEEEEEE,0xEEEEEE,0xEEEEEE,0xEEEEEE,0xEEEEEE,0xEEEEEE,0xEEEEEE,0xEEEEEE,0xCCCCCC,0x999999,0,0],
        [0,0x999999,0xCCCCCC,0xEEEEEE,0xEEEEEE,0xEEEEEE,0xEEEEEE,0xEEEEEE,0xEEEEEE,0xEEEEEE,0xEEEEEE,0xEEEEEE,0xCCCCCC,0x999999,0,0],
        [0,0x999999,0,0xCCCCCC,0xEEEEEE,0,0xCCCCCC,0xEEEEEE,0xCCCCCC,0,0xEEEEEE,0xCCCCCC,0,0x999999,0,0],
        [0,0,0,0x999999,0,0,0x999999,0,0x999999,0,0,0x999999,0,0,0,0],
        [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
    ], scale: s)

    // Jagged crack lines — Brown
    static let earthquake: CGImage? = GameBase.renderPixelArt([
        [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
        [0xAA6633,0xAA6633,0,0,0,0,0,0,0,0,0,0,0,0,0xAA6633,0xAA6633],
        [0,0,0xAA6633,0,0,0,0,0,0,0,0,0,0,0xAA6633,0,0],
        [0,0,0,0xCC8844,0,0,0,0,0,0,0,0,0xCC8844,0,0,0],
        [0,0,0,0,0xCC8844,0,0,0,0,0,0,0xCC8844,0,0,0,0],
        [0,0,0,0,0,0xAA6633,0,0,0,0,0xAA6633,0,0,0,0,0],
        [0,0,0,0,0,0,0xCC8844,0,0,0xCC8844,0,0,0,0,0,0],
        [0,0,0,0,0,0,0,0xFFAA55,0xFFAA55,0,0,0,0,0,0,0],
        [0,0,0,0,0,0,0,0xFFAA55,0xFFAA55,0,0,0,0,0,0,0],
        [0,0,0,0,0,0,0xCC8844,0,0,0xCC8844,0,0,0,0,0,0],
        [0,0,0,0,0,0xAA6633,0,0,0,0,0xAA6633,0,0,0,0,0],
        [0,0,0,0,0xCC8844,0,0,0,0,0,0,0xCC8844,0,0,0,0],
        [0,0,0,0xCC8844,0,0,0,0,0,0,0,0,0xCC8844,0,0,0],
        [0,0,0xAA6633,0,0,0,0,0,0,0,0,0,0,0xAA6633,0,0],
        [0xAA6633,0xAA6633,0,0,0,0,0,0,0,0,0,0,0,0,0xAA6633,0xAA6633],
        [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
    ], scale: s)

    // Arrow with curve — Red
    static let homing: CGImage? = GameBase.renderPixelArt([
        [0,0,0,0,0,0,0,0,0,0,0xFF4444,0xFF4444,0,0,0,0],
        [0,0,0,0,0,0,0,0,0,0xFF4444,0xFF6666,0xFF4444,0,0,0,0],
        [0,0,0,0,0,0,0,0,0xFF4444,0xFF6666,0,0,0,0,0,0],
        [0,0,0,0,0,0,0,0xFF4444,0xFF6666,0,0,0,0,0,0,0],
        [0,0,0,0,0,0,0xFF4444,0xFF4444,0,0,0,0,0,0,0,0],
        [0,0,0,0,0,0xFF4444,0xFF4444,0,0,0,0,0,0,0,0,0],
        [0,0,0,0,0xFF4444,0xFF4444,0,0,0,0,0,0,0,0,0,0],
        [0,0,0,0xFF4444,0xFF4444,0,0,0,0,0,0,0,0,0,0,0],
        [0,0,0xFF4444,0xFF4444,0,0,0,0,0,0,0,0,0,0,0,0],
        [0,0xFF4444,0xFF4444,0,0,0,0,0,0,0,0,0,0,0,0,0],
        [0xFF4444,0xFF4444,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
        [0xFF4444,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
        [0xFF4444,0xFF4444,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
        [0,0,0xFF4444,0xFF4444,0xFF4444,0,0,0,0,0,0,0,0,0,0,0],
        [0,0,0,0,0,0xFF4444,0xFF4444,0xFF4444,0,0,0,0,0,0,0,0],
        [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
    ], scale: s)

    // Black hole spiral — Purple
    static let gravityWell: CGImage? = GameBase.renderPixelArt([
        [0,0,0,0,0,0x9944FF,0x9944FF,0x9944FF,0x9944FF,0x9944FF,0x9944FF,0,0,0,0,0],
        [0,0,0,0x9944FF,0x9944FF,0xBB77FF,0,0,0,0,0xBB77FF,0x9944FF,0x9944FF,0,0,0],
        [0,0,0x9944FF,0xBB77FF,0,0,0,0,0,0,0,0,0xBB77FF,0x9944FF,0,0],
        [0,0x9944FF,0,0,0,0,0x7722CC,0x7722CC,0x7722CC,0,0,0,0,0x9944FF,0,0],
        [0,0x9944FF,0,0,0,0x7722CC,0,0,0,0x7722CC,0,0,0,0x9944FF,0,0],
        [0x9944FF,0xBB77FF,0,0,0x7722CC,0,0,0,0,0x7722CC,0,0,0xBB77FF,0x9944FF,0,0],
        [0x9944FF,0,0,0x7722CC,0,0,0x440088,0x440088,0,0,0x7722CC,0,0,0x9944FF,0,0],
        [0x9944FF,0,0,0x7722CC,0,0,0x440088,0x220044,0x440088,0,0x7722CC,0,0,0x9944FF,0],
        [0x9944FF,0,0,0x7722CC,0,0,0x440088,0x440088,0,0,0x7722CC,0,0,0,0x9944FF,0],
        [0,0x9944FF,0,0,0x7722CC,0,0,0,0,0x7722CC,0,0,0xBB77FF,0x9944FF,0,0],
        [0,0x9944FF,0,0,0,0x7722CC,0,0,0x7722CC,0,0,0,0,0x9944FF,0,0],
        [0,0,0x9944FF,0,0,0,0x7722CC,0x7722CC,0,0,0,0,0x9944FF,0,0,0],
        [0,0,0x9944FF,0xBB77FF,0,0,0,0,0,0,0,0xBB77FF,0x9944FF,0,0,0],
        [0,0,0,0x9944FF,0x9944FF,0xBB77FF,0,0,0,0xBB77FF,0x9944FF,0x9944FF,0,0,0,0],
        [0,0,0,0,0,0x9944FF,0x9944FF,0x9944FF,0x9944FF,0x9944FF,0,0,0,0,0,0],
        [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
    ], scale: s)

    // Shrinking paddle — Green
    static let shrinkRay: CGImage? = GameBase.renderPixelArt([
        [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
        [0,0,0,0,0,0,0,0x33DD66,0x33DD66,0,0,0,0,0,0,0],
        [0,0,0,0,0,0,0x33DD66,0x66EE88,0x66EE88,0x33DD66,0,0,0,0,0,0],
        [0,0,0,0,0,0x33DD66,0x66EE88,0x66EE88,0x66EE88,0x66EE88,0x33DD66,0,0,0,0,0],
        [0,0,0,0,0,0,0x33DD66,0,0,0x33DD66,0,0,0,0,0,0],
        [0,0,0,0,0,0,0,0x33DD66,0x33DD66,0,0,0,0,0,0,0],
        [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
        [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
        [0,0,0,0x33DD66,0x33DD66,0x33DD66,0x33DD66,0x33DD66,0x33DD66,0x33DD66,0x33DD66,0x33DD66,0x33DD66,0,0,0],
        [0,0,0,0x55EE77,0x55EE77,0x55EE77,0x55EE77,0x55EE77,0x55EE77,0x55EE77,0x55EE77,0x55EE77,0x55EE77,0,0,0],
        [0,0,0,0x33DD66,0x33DD66,0x33DD66,0x33DD66,0x33DD66,0x33DD66,0x33DD66,0x33DD66,0x33DD66,0x33DD66,0,0,0],
        [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
        [0,0,0,0,0,0x33DD66,0x33DD66,0x33DD66,0x33DD66,0x33DD66,0x33DD66,0,0,0,0,0],
        [0,0,0,0,0,0x55EE77,0x55EE77,0x55EE77,0x55EE77,0x55EE77,0x55EE77,0,0,0,0,0],
        [0,0,0,0,0,0x33DD66,0x33DD66,0x33DD66,0x33DD66,0x33DD66,0x33DD66,0,0,0,0,0],
        [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
    ], scale: s)

    // "×2" text — Gold
    static let multiHit: CGImage? = GameBase.renderPixelArt([
        [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
        [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
        [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
        [0,0xFFDD44,0,0,0,0xFFDD44,0,0,0,0xFFDD44,0xFFDD44,0xFFDD44,0,0,0,0],
        [0,0,0xFFDD44,0,0xFFDD44,0,0,0,0,0,0,0,0xFFDD44,0,0,0],
        [0,0,0,0xFFEE66,0,0,0,0,0,0,0,0xFFDD44,0,0,0,0],
        [0,0,0xFFDD44,0,0xFFDD44,0,0,0,0,0,0xFFDD44,0,0,0,0],
        [0,0xFFDD44,0,0,0,0xFFDD44,0,0,0,0xFFDD44,0,0,0,0,0,0],
        [0,0,0,0,0,0,0,0,0xFFDD44,0,0,0,0,0,0,0],
        [0,0,0,0,0,0,0,0,0xFFDD44,0xFFDD44,0xFFDD44,0xFFDD44,0,0,0,0],
        [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
        [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
        [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
        [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
        [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
        [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
    ], scale: s)

    // Bouncing arrow zigzag — Electric blue
    static let ricochet: CGImage? = GameBase.renderPixelArt([
        [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
        [0,0,0x4488FF,0x4488FF,0,0,0,0,0,0,0,0,0,0,0,0],
        [0,0,0,0,0x4488FF,0,0,0,0,0,0,0,0,0,0,0],
        [0,0,0,0,0,0x4488FF,0,0,0,0,0,0,0,0,0,0],
        [0,0,0,0,0,0,0x66AAFF,0,0,0,0,0,0,0,0,0],
        [0,0,0,0,0,0,0,0x66AAFF,0,0,0,0,0,0,0,0],
        [0,0,0,0,0,0,0,0,0x4488FF,0,0,0,0,0,0,0],
        [0,0,0,0,0,0,0,0,0,0x4488FF,0,0,0,0,0,0],
        [0,0,0,0,0,0,0,0,0,0,0x66AAFF,0,0,0,0,0],
        [0,0,0,0,0,0,0,0,0,0,0,0x66AAFF,0,0,0,0],
        [0,0,0,0,0,0,0,0,0,0,0,0,0x4488FF,0,0,0],
        [0,0,0,0,0,0,0,0,0,0,0,0,0,0x4488FF,0,0],
        [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0x4488FF,0],
        [0,0,0,0,0,0,0,0,0,0,0,0,0,0x4488FF,0x4488FF,0],
        [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
        [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
    ], scale: s)

    // Iron fist — Silver
    static let steelFist: CGImage? = GameBase.renderPixelArt([
        [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
        [0,0,0,0,0,0xBBBBCC,0xBBBBCC,0xBBBBCC,0xBBBBCC,0xBBBBCC,0xBBBBCC,0,0,0,0,0],
        [0,0,0,0,0xBBBBCC,0xDDDDEE,0xDDDDEE,0xDDDDEE,0xDDDDEE,0xDDDDEE,0xBBBBCC,0,0,0,0],
        [0,0,0,0,0xBBBBCC,0xDDDDEE,0x999999,0xDDDDEE,0x999999,0xDDDDEE,0xBBBBCC,0,0,0,0],
        [0,0,0,0,0xBBBBCC,0xDDDDEE,0xDDDDEE,0xDDDDEE,0xDDDDEE,0xDDDDEE,0xBBBBCC,0,0,0,0],
        [0,0,0xBBBBCC,0xBBBBCC,0xBBBBCC,0xBBBBCC,0xBBBBCC,0xBBBBCC,0xBBBBCC,0xBBBBCC,0xBBBBCC,0xBBBBCC,0,0,0],
        [0,0xBBBBCC,0xDDDDEE,0xDDDDEE,0xDDDDEE,0xDDDDEE,0xDDDDEE,0xDDDDEE,0xDDDDEE,0xDDDDEE,0xDDDDEE,0xDDDDEE,0xBBBBCC,0,0],
        [0,0xBBBBCC,0xDDDDEE,0x999999,0xDDDDEE,0x999999,0xDDDDEE,0x999999,0xDDDDEE,0x999999,0xDDDDEE,0xDDDDEE,0xBBBBCC,0,0],
        [0,0xBBBBCC,0xDDDDEE,0xDDDDEE,0xDDDDEE,0xDDDDEE,0xDDDDEE,0xDDDDEE,0xDDDDEE,0xDDDDEE,0xDDDDEE,0xDDDDEE,0xBBBBCC,0,0],
        [0,0,0xBBBBCC,0xDDDDEE,0xDDDDEE,0xDDDDEE,0xDDDDEE,0xDDDDEE,0xDDDDEE,0xDDDDEE,0xDDDDEE,0xBBBBCC,0,0,0],
        [0,0,0,0xBBBBCC,0xDDDDEE,0xDDDDEE,0xDDDDEE,0xDDDDEE,0xDDDDEE,0xDDDDEE,0xBBBBCC,0,0,0,0],
        [0,0,0,0,0xBBBBCC,0xDDDDEE,0xDDDDEE,0xDDDDEE,0xDDDDEE,0xBBBBCC,0,0,0,0,0],
        [0,0,0,0,0,0xBBBBCC,0xBBBBCC,0xBBBBCC,0xBBBBCC,0,0,0,0,0,0],
        [0,0,0,0,0,0,0xBBBBCC,0xBBBBCC,0,0,0,0,0,0,0,0],
        [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
        [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
    ], scale: s)
}
