import Cocoa

enum SnakeSprites {
    // 8x8 apple: red body, white highlight, dark red shading, brown stem, green leaf
    static let apple: CGImage? = {
        let O: UInt32 = 0 // transparent
        let R: UInt32 = 0xDD2222 // red
        let D: UInt32 = 0xAA1111 // dark red
        let H: UInt32 = 0xFF4444 // highlight red
        let W: UInt32 = 0xFFFFFF // white specular
        let B: UInt32 = 0x663311 // brown stem
        let G: UInt32 = 0x44BB33 // green leaf
        let pixels: [[UInt32]] = [
            [O, O, O, B, G, G, O, O],
            [O, O, O, B, O, G, O, O],
            [O, H, R, R, R, R, W, O],
            [H, R, R, R, R, R, R, O],
            [R, R, R, R, R, R, R, O],
            [R, R, R, R, R, R, D, O],
            [O, D, R, R, R, D, D, O],
            [O, O, D, D, D, D, O, O],
        ]
        return GameBase.renderPixelArt(pixels, scale: 3)
    }()

    // 7x7 head segment: bright green, diamond pattern, white highlight
    static let bodyHead: CGImage? = {
        let O: UInt32 = 0
        let G: UInt32 = 0x33DD44 // bright green
        let L: UInt32 = 0x55FF66 // light green
        let D: UInt32 = 0x22AA33 // dark green border
        let W: UInt32 = 0xCCFFCC // white-ish highlight
        let pixels: [[UInt32]] = [
            [O, O, D, D, D, O, O],
            [O, D, G, W, G, D, O],
            [D, G, L, G, L, G, D],
            [D, G, G, L, G, G, D],
            [D, G, L, G, L, G, D],
            [O, D, G, G, G, D, O],
            [O, O, D, D, D, O, O],
        ]
        return GameBase.renderPixelArt(pixels, scale: 3)
    }()

    // 7x7 mid segment: slightly desaturated green, scale pattern
    static let bodyMid: CGImage? = {
        let O: UInt32 = 0
        let G: UInt32 = 0x2BB83A // mid green
        let L: UInt32 = 0x44DD55 // lighter
        let D: UInt32 = 0x1D8A2A // dark border
        let pixels: [[UInt32]] = [
            [O, O, D, D, D, O, O],
            [O, D, G, G, G, D, O],
            [D, G, L, G, L, G, D],
            [D, G, G, L, G, G, D],
            [D, G, L, G, L, G, D],
            [O, D, G, G, G, D, O],
            [O, O, D, D, D, O, O],
        ]
        return GameBase.renderPixelArt(pixels, scale: 3)
    }()

    // 7x7 tail segment: darker muted green, thinner/fading
    static let bodyTail: CGImage? = {
        let O: UInt32 = 0
        let G: UInt32 = 0x1E7A28 // muted green
        let L: UInt32 = 0x2A9935 // slightly lighter
        let D: UInt32 = 0x145A1C // dark border
        let pixels: [[UInt32]] = [
            [O, O, O, O, O, O, O],
            [O, O, D, D, D, O, O],
            [O, D, G, G, G, D, O],
            [O, D, G, L, G, D, O],
            [O, D, G, G, G, D, O],
            [O, O, D, D, D, O, O],
            [O, O, O, O, O, O, O],
        ]
        return GameBase.renderPixelArt(pixels, scale: 3)
    }()
}
