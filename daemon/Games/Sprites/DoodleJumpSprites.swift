import Cocoa

enum DoodleJumpSprites {
    // Palette
    private static let G: UInt32 = 0x3ACC50  // bright grass green
    private static let Y: UInt32 = 0x7ACC3A  // yellow-green grass
    private static let E: UInt32 = 0x8B6930  // earthy brown
    private static let S: UInt32 = 0x6B4F20  // darker brown base
    private static let T: UInt32 = 0x5A4318  // stone texture dark
    private static let O: UInt32 = 0          // transparent

    // Moving platform palette
    private static let N: UInt32 = 0x9B7B4A  // tan base
    private static let W: UInt32 = 0xCCB030  // warning yellow
    private static let R: UInt32 = 0x6B4F20  // brown stripe

    // Normal platform 24x5: grassy top, earthy body, stone base
    static let normal: [[UInt32]] = [
        [O,G,Y,G,O,G,G,Y,G,O,O,G,Y,G,O,G,G,Y,O,G,Y,G,G,O],
        [E,E,E,E,E,E,E,E,E,E,E,E,E,E,E,E,E,E,E,E,E,E,E,E],
        [E,E,E,E,E,E,E,E,E,E,E,E,E,E,E,E,E,E,E,E,E,E,E,E],
        [S,S,S,S,T,S,S,S,T,S,S,S,S,S,T,S,S,S,S,T,S,S,S,S],
        [T,S,S,T,T,S,S,T,T,T,S,S,T,T,T,S,S,T,T,T,S,S,T,T],
    ]

    // Moving platform 24x5: diagonal warning stripes
    static let moving: [[UInt32]] = [
        [N,N,W,W,N,N,W,W,N,N,W,W,N,N,W,W,N,N,W,W,N,N,W,W],
        [W,N,N,W,W,N,N,W,W,N,N,W,W,N,N,W,W,N,N,W,W,N,N,W],
        [W,W,N,N,W,W,N,N,W,W,N,N,W,W,N,N,W,W,N,N,W,W,N,N],
        [R,W,W,N,R,W,W,N,R,W,W,N,R,W,W,N,R,W,W,N,R,W,W,N],
        [R,R,W,W,R,R,W,W,R,R,W,W,R,R,W,W,R,R,W,W,R,R,W,W],
    ]

    static let normalImage: CGImage? = GameBase.renderPixelArt(normal, scale: 3)
    static let movingImage: CGImage? = GameBase.renderPixelArt(moving, scale: 3)
}
