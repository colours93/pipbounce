import Cocoa

enum FlappySprites {
    // Palette
    private static let H: UInt32 = 0x8ED43C  // highlight green
    private static let L: UInt32 = 0x5FA316  // light green
    private static let M: UInt32 = 0x4E8C12  // medium green
    private static let D: UInt32 = 0x33660A  // dark green (shadow/edge)
    private static let B: UInt32 = 0x264D08  // border dark
    private static let O: UInt32 = 0          // transparent

    // Pipe cap 22x8: wider cap with lip, highlight top, shadow bottom, dark edges
    static let pipeCap: [[UInt32]] = [
        [B,B,B,B,B,B,B,B,B,B,B,B,B,B,B,B,B,B,B,B,B,B],
        [B,D,H,H,H,L,L,L,L,L,L,L,L,L,L,L,L,L,H,H,D,B],
        [B,D,H,H,L,L,L,L,L,L,L,L,L,L,L,L,L,L,L,H,D,B],
        [B,D,L,M,M,M,M,M,M,M,M,M,M,M,M,M,M,M,M,L,D,B],
        [B,D,L,M,M,M,M,M,M,M,M,M,M,M,M,M,M,M,M,L,D,B],
        [B,D,M,M,M,M,M,M,M,M,M,M,M,M,M,M,M,M,M,M,D,B],
        [B,D,D,D,M,M,M,M,M,M,M,M,M,M,M,M,M,M,D,D,D,B],
        [B,B,B,B,B,B,B,B,B,B,B,B,B,B,B,B,B,B,B,B,B,B],
    ]

    // Pipe body 18x8: tiled vertically, left shadow, right highlight, brick lines
    static let pipeBody: [[UInt32]] = [
        [B,D,D,M,M,M,M,M,M,M,M,M,M,M,M,L,H,B],
        [B,D,D,M,M,M,M,M,M,M,M,M,M,M,M,L,H,B],
        [B,D,D,D,D,D,D,D,D,D,D,D,D,D,D,D,D,B],
        [B,D,D,M,M,M,M,M,M,M,M,M,M,M,M,L,H,B],
        [B,D,D,M,M,M,M,M,M,M,M,M,M,M,M,L,H,B],
        [B,D,D,D,D,D,D,D,D,D,D,D,D,D,D,D,D,B],
        [B,D,D,M,M,M,M,M,M,M,M,M,M,M,M,L,H,B],
        [B,D,D,M,M,M,M,M,M,M,M,M,M,M,M,L,H,B],
    ]

    static let pipeCapImage: CGImage? = GameBase.renderPixelArt(pipeCap, scale: 3)
    static let pipeBodyImage: CGImage? = GameBase.renderPixelArt(pipeBody, scale: 3)
}
