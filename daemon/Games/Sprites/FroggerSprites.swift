import Cocoa

enum FroggerSprites {
    // ── Cyberpunk Hoverbike variants: 10x8 pixels, displayed at 2x = 20x16 ──

    static let motorcyclePink: CGImage? = {
        let _ : UInt32 = 0
        let N : UInt32 = 0xFF0066  // hot pink neon
        let Nd: UInt32 = 0xCC0044  // dark pink neon
        let B : UInt32 = 0x1A1A2A  // carbon fiber body
        let D : UInt32 = 0x252535  // carbon fiber dark
        let K : UInt32 = 0x111118  // near-black (rider)
        let V : UInt32 = 0x334455  // visor tint
        let T : UInt32 = 0xFF4400  // thruster glow
        let Tb: UInt32 = 0xFF8844  // thruster bright
        let pixels: [[UInt32]] = [
            [0, 0, 0, 0, K, K, 0, 0, 0, 0],
            [0, 0, 0, K, V, V, K, 0, 0, 0],
            [0, 0, 0, 0, K, K, N, 0, 0, 0],
            [0, 0, N, B, K, K, B, N, 0, 0],
            [0, 0, 0, B, D, D, B, 0, 0, 0],
            [Tb, T, D, B, Nd,Nd, B, D, 0, 0],
            [0, T, D, N, D, D, N, D, 0, 0],
            [0, 0, Nd, 0, Nd,Nd, 0, Nd, 0, 0],
        ]
        return GameBase.renderPixelArt(pixels, scale: 2)
    }()

    static let motorcycleCyan: CGImage? = {
        let _ : UInt32 = 0
        let N : UInt32 = 0x00FFEE  // cyan neon
        let Nd: UInt32 = 0x00BBAA  // dark cyan neon
        let B : UInt32 = 0x1A1A2A
        let D : UInt32 = 0x252535
        let K : UInt32 = 0x111118
        let V : UInt32 = 0x334455
        let T : UInt32 = 0x00CCBB  // cyan thruster
        let Tb: UInt32 = 0x44FFEE  // cyan thruster bright
        let pixels: [[UInt32]] = [
            [0, 0, 0, 0, K, K, 0, 0, 0, 0],
            [0, 0, 0, K, V, V, K, 0, 0, 0],
            [0, 0, 0, 0, K, K, N, 0, 0, 0],
            [0, 0, N, B, K, K, B, N, 0, 0],
            [0, 0, 0, B, D, D, B, 0, 0, 0],
            [Tb, T, D, B, Nd,Nd, B, D, 0, 0],
            [0, T, D, N, D, D, N, D, 0, 0],
            [0, 0, Nd, 0, Nd,Nd, 0, Nd, 0, 0],
        ]
        return GameBase.renderPixelArt(pixels, scale: 2)
    }()

    static let motorcycleYellow: CGImage? = {
        let _ : UInt32 = 0
        let N : UInt32 = 0xFFCC00  // yellow neon
        let Nd: UInt32 = 0xDD9900  // dark yellow neon
        let B : UInt32 = 0x1A1A2A
        let D : UInt32 = 0x252535
        let K : UInt32 = 0x111118
        let V : UInt32 = 0x334455
        let T : UInt32 = 0xDDAA00  // yellow thruster
        let Tb: UInt32 = 0xFFDD44  // yellow thruster bright
        let pixels: [[UInt32]] = [
            [0, 0, 0, 0, K, K, 0, 0, 0, 0],
            [0, 0, 0, K, V, V, K, 0, 0, 0],
            [0, 0, 0, 0, K, K, N, 0, 0, 0],
            [0, 0, N, B, K, K, B, N, 0, 0],
            [0, 0, 0, B, D, D, B, 0, 0, 0],
            [Tb, T, D, B, Nd,Nd, B, D, 0, 0],
            [0, T, D, N, D, D, N, D, 0, 0],
            [0, 0, Nd, 0, Nd,Nd, 0, Nd, 0, 0],
        ]
        return GameBase.renderPixelArt(pixels, scale: 2)
    }()

    static let motorcycles: [CGImage?] = [motorcyclePink, motorcycleCyan, motorcycleYellow]

    // ── Cyberpunk Cyber-Sedan variants: 20x8 pixels, displayed at 2x = 40x16 ──
    static func makeCar(body: UInt32, dark: UInt32, roof: UInt32, neon: UInt32) -> CGImage? {
        let _ : UInt32 = 0
        let B  = body
        let D  = dark
        let R  = roof
        let L  = neon
        let W : UInt32 = 0x223355  // tinted windshield (dark)
        let Wh: UInt32 = 0x334466  // tinted windshield reflection
        let K : UInt32 = 0x111118  // tire
        let G : UInt32 = 0x252535  // wheel well
        let H : UInt32 = 0x555566  // hubcap
        let Y : UInt32 = 0x00FFEE  // cyan LED headlight
        let Yg: UInt32 = 0x00BBAA  // headlight glow
        let T : UInt32 = 0xFF0044  // taillight (neon red)
        let C : UInt32 = 0x333344  // dark chrome bumper
        let pixels: [[UInt32]] = [
            [0, 0, 0, 0, 0, R, R, R, R, R, R, R, R, R, 0, 0, 0, 0, 0, 0],
            [0, 0, 0, 0, R, R, B, B, B, B, B, B, B, R, R, 0, 0, 0, 0, 0],
            [0, 0, 0, R, W, W, Wh,W, W, W, W, W, Wh,W, W, R, 0, 0, 0, 0],
            [0, 0, C, B, B, B, B, B, B, B, B, B, B, B, B, B, B, C, Yg, 0],
            [0, T, B, B, B, B, B, B, D, D, B, B, B, B, B, B, B, B, Y, 0],
            [0, T, L, L, L, L, L, L, L, L, L, L, L, L, L, L, L, L, Y, 0],
            [0, 0, D, G, K, K, G, D, D, D, D, D, D, G, K, K, G, D, 0, 0],
            [0, 0, 0, K, K, H, K, 0, 0, 0, 0, 0, 0, K, H, K, K, 0, 0, 0],
        ]
        return GameBase.renderPixelArt(pixels, scale: 2)
    }

    static let carRedPink:    CGImage? = makeCar(body: 0x661122, dark: 0x330A11, roof: 0x882233, neon: 0xFF0066)
    static let carBlueCyan:   CGImage? = makeCar(body: 0x112244, dark: 0x0A1133, roof: 0x223366, neon: 0x00FFEE)
    static let carBlackGreen: CGImage? = makeCar(body: 0x1A1A22, dark: 0x0D0D11, roof: 0x2A2A33, neon: 0x00FF66)
    static let carPurpleMag:  CGImage? = makeCar(body: 0x331144, dark: 0x1A0A22, roof: 0x442266, neon: 0xFF00CC)
    static let carSilverBlue: CGImage? = makeCar(body: 0x778899, dark: 0x445566, roof: 0x99AABB, neon: 0x4488FF)

    static let cars: [CGImage?] = [carRedPink, carBlueCyan, carBlackGreen, carPurpleMag, carSilverBlue]

    // ── Cyberpunk Armored Cyber-Hauler variants: 32x8 pixels, displayed at 2x ──
    static func makeTruck(cab: UInt32, cabDark: UInt32, cargo: UInt32, cargoDark: UInt32, neon: UInt32) -> CGImage? {
        let _ : UInt32 = 0
        let A  = cab
        let Ad = cabDark
        let B  = cargo
        let Bd = cargoDark
        let L  = neon
        let W : UInt32 = 0x223355  // tinted windshield
        let Wh: UInt32 = 0x334466  // windshield reflection
        let K : UInt32 = 0x111118  // tire
        let G : UInt32 = 0x252535  // wheel well
        let H : UInt32 = 0x555566  // hubcap
        let Y : UInt32 = 0x00FFEE  // cyan LED headlight
        let Yg: UInt32 = 0x00BBAA  // headlight glow
        let T : UInt32 = 0xFF0044  // taillight neon
        let C : UInt32 = 0x333344  // dark chrome bumper
        let Th: UInt32 = 0xFF6622  // thruster glow
        let Tb: UInt32 = 0xFF8844  // thruster bright
        let pixels: [[UInt32]] = [
            [0, 0, L, 0, L, 0, L, 0, L, 0, L, 0, L, 0, L, 0, L, 0, L, 0, 0, 0, 0, 0, 0, Tb,Th, 0, A, A, Yg, 0],
            [0, T, B, B, B, B, B, B, B, B, B, B, B, B, B, B, B, B, B, B, B, 0, 0, Th, A, A, A, A, A, A, Y, 0],
            [0, T, B, B, B, B, B, B, B, B, B, B, B, B, B, B, B, B, B, B, B, 0, W, Wh, W, A, A, A, A, A, Y, 0],
            [0, 0, B, B, B, B, B, B, B, B, B, B, B, B, B, B, B, B, B, B, B, 0, A, A, A, A, A, A, A, A, C, 0],
            [0, 0, Bd,Bd,Bd,Bd,Bd,Bd,Bd,Bd,Bd,Bd,Bd,Bd,Bd,Bd,Bd,Bd,Bd,Bd,Bd, 0, Ad,Ad,Ad,Ad,Ad,Ad,Ad,Ad, C, 0],
            [0, 0, L, L, L, L, L, L, L, L, L, L, L, L, L, L, L, L, L, L, L, 0, L, L, L, L, L, L, L, L, 0, 0],
            [0, 0, Bd, G, K, K, G, Bd,Bd, G, K, K, G, Bd,Bd,Bd,Bd,Bd,Bd,Bd, 0, 0, Ad, G, K, K, G, Ad, 0, 0, 0, 0],
            [0, 0, 0, K, K, H, K, 0, 0, K, H, K, K, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, K, K, H, K, 0, 0, 0, 0, 0],
        ]
        return GameBase.renderPixelArt(pixels, scale: 2)
    }

    static let truckMilitary:   CGImage? = makeTruck(cab: 0x2A2A22, cabDark: 0x1A1A14, cargo: 0x222218, cargoDark: 0x15150F, neon: 0xFF2200)
    static let truckCorporate:  CGImage? = makeTruck(cab: 0x999999, cabDark: 0x666666, cargo: 0xAAAAAA, cargoDark: 0x777777, neon: 0x00FFEE)
    static let truckIndustrial: CGImage? = makeTruck(cab: 0x887722, cabDark: 0x554411, cargo: 0xAA9933, cargoDark: 0x776622, neon: 0xFF8800)

    static let trucks: [CGImage?] = [truckMilitary, truckCorporate, truckIndustrial]
}
