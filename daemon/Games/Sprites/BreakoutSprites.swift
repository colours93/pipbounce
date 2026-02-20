import Cocoa

enum BreakoutSprites {
    // Paddle: 40x4 metallic with green bumper dots, scale 3 -> 120x12
    static let paddle: CGImage? = {
        var rows = [[UInt32]](repeating: [UInt32](repeating: 0, count: 40), count: 4)
        // Row 0 (top): bright highlight
        for x in 0..<40 {
            rows[0][x] = 0xCCCCCC  // light silver highlight
        }
        // Bevel: darken edges
        rows[0][0] = 0x888888; rows[0][1] = 0xAAAAAA
        rows[0][38] = 0xAAAAAA; rows[0][39] = 0x888888
        // Row 1: lighter mid
        for x in 0..<40 { rows[1][x] = 0x999999 }
        rows[1][0] = 0x666666; rows[1][39] = 0x666666
        // Row 2: medium mid
        for x in 0..<40 { rows[2][x] = 0x777777 }
        rows[2][0] = 0x555555; rows[2][39] = 0x555555
        // Row 3 (bottom): shadow
        for x in 0..<40 { rows[3][x] = 0x444444 }
        rows[3][0] = 0x333333; rows[3][39] = 0x333333
        // Bumper dots (bright green) at x=2 and x=37, rows 1-2
        for y in 1...2 {
            rows[y][2] = 0x00DD55
            rows[y][37] = 0x00DD55
        }
        return GameBase.renderPixelArt(rows, scale: 3)
    }()

    // Brick helpers
    private static func makeBrick(highlight: UInt32, body: UInt32, shadow: UInt32, specular: UInt32) -> [[UInt32]] {
        var rows = [[UInt32]](repeating: [UInt32](repeating: 0, count: 20), count: 7)
        // Row 0: highlight
        for x in 0..<20 { rows[0][x] = highlight }
        // Rows 1-4: body with subtle horizontal texture (alternating slightly)
        for y in 1...4 {
            let c = (y % 2 == 0) ? body : body &- 0x0A0A0A
            for x in 0..<20 { rows[y][x] = c }
        }
        // Row 5: slightly darker transition
        for x in 0..<20 { rows[5][x] = body &- 0x151515 }
        // Row 6: shadow
        for x in 0..<20 { rows[6][x] = shadow }
        // Specular dot at (2,1)
        rows[1][2] = specular
        return rows
    }

    private static func makeDamaged(_ base: [[UInt32]]) -> [[UInt32]] {
        var d = base
        // Crack pattern: some pixels go darker or transparent
        let cracks: [(Int,Int)] = [
            (1,5),(1,6),(2,6),(2,7),(3,7),(3,8),(3,9),(4,8),(4,9),(5,9),(5,10),
            (2,13),(3,13),(3,14),(4,14),(4,15),(5,14)
        ]
        for (y,x) in cracks {
            if y < d.count && x < d[y].count {
                d[y][x] = 0x1A1A1A  // very dark crack
            }
        }
        return d
    }

    // Green (row 0)
    static let brickGreen: CGImage? = {
        let px = makeBrick(highlight: 0x33CC66, body: 0x005A26, shadow: 0x003318, specular: 0xBBFFDD)
        return GameBase.renderPixelArt(px, scale: 3)
    }()
    static let brickGreenDmg: CGImage? = {
        let px = makeDamaged(makeBrick(highlight: 0x33CC66, body: 0x005A26, shadow: 0x003318, specular: 0xBBFFDD))
        return GameBase.renderPixelArt(px, scale: 3)
    }()

    // Cyan (row 1)
    static let brickCyan: CGImage? = {
        let px = makeBrick(highlight: 0x44CCCC, body: 0x004D4D, shadow: 0x002D2D, specular: 0xBBFFFF)
        return GameBase.renderPixelArt(px, scale: 3)
    }()
    static let brickCyanDmg: CGImage? = {
        let px = makeDamaged(makeBrick(highlight: 0x44CCCC, body: 0x004D4D, shadow: 0x002D2D, specular: 0xBBFFFF))
        return GameBase.renderPixelArt(px, scale: 3)
    }()

    // Slate-blue (row 2)
    static let brickSlate: CGImage? = {
        let px = makeBrick(highlight: 0x6670AA, body: 0x33384D, shadow: 0x1E2133, specular: 0xCCCCFF)
        return GameBase.renderPixelArt(px, scale: 3)
    }()
    static let brickSlateDmg: CGImage? = {
        let px = makeDamaged(makeBrick(highlight: 0x6670AA, body: 0x33384D, shadow: 0x1E2133, specular: 0xCCCCFF))
        return GameBase.renderPixelArt(px, scale: 3)
    }()

    // Purple (row 3)
    static let brickPurple: CGImage? = {
        let px = makeBrick(highlight: 0x9944AA, body: 0x4D1A4D, shadow: 0x2E0F2E, specular: 0xEEBBFF)
        return GameBase.renderPixelArt(px, scale: 3)
    }()
    static let brickPurpleDmg: CGImage? = {
        let px = makeDamaged(makeBrick(highlight: 0x9944AA, body: 0x4D1A4D, shadow: 0x2E0F2E, specular: 0xEEBBFF))
        return GameBase.renderPixelArt(px, scale: 3)
    }()

    // Red (row 4)
    static let brickRed: CGImage? = {
        let px = makeBrick(highlight: 0xCC3344, body: 0x660D1A, shadow: 0x3D0810, specular: 0xFFBBCC)
        return GameBase.renderPixelArt(px, scale: 3)
    }()
    static let brickRedDmg: CGImage? = {
        let px = makeDamaged(makeBrick(highlight: 0xCC3344, body: 0x660D1A, shadow: 0x3D0810, specular: 0xFFBBCC))
        return GameBase.renderPixelArt(px, scale: 3)
    }()

    // Indexed access: [row] -> (normal, damaged)
    static let brickImages: [(normal: CGImage?, damaged: CGImage?)] = [
        (brickGreen, brickGreenDmg),
        (brickCyan, brickCyanDmg),
        (brickSlate, brickSlateDmg),
        (brickPurple, brickPurpleDmg),
        (brickRed, brickRedDmg),
    ]
}
