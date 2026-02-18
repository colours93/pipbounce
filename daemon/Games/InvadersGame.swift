import Cocoa
import ApplicationServices

let invaders = InvadersGame()

class InvadersGame: GameBase {

    // Grid
    private let cols = 8
    private let rows = 5
    private let px: CGFloat = 3          // pixel block size
    private let spriteCols = 11          // pixels per sprite width
    private let spriteRows = 8           // pixels per sprite height
    private var alienW: CGFloat { px * CGFloat(spriteCols) }   // 33
    private var alienH: CGFloat { px * CGFloat(spriteRows) }   // 24
    private let spacingX: CGFloat = 18
    private let spacingY: CGFloat = 14

    // Alien state
    private struct Alien {
        let layer: CALayer
        var alive: Bool
        let row: Int
    }
    private var aliens: [Alien] = []
    private var gridX: CGFloat = 0      // top-left of grid in AX coords
    private var gridY: CGFloat = 0
    private var gridDir: CGFloat = 1    // +1 right, -1 left
    private let baseSpeedInitial: CGFloat = 40
    private let maxSpeed: CGFloat = 300
    private var baseSpeed: CGFloat = 40
    private var aliveCount = 0
    private let totalAliens = 40  // cols * rows

    // Bullets
    private struct Bullet {
        let layer: CALayer
        var x: CGFloat       // AX coords
        var y: CGFloat
        let dy: CGFloat      // negative = up, positive = down
        let isPlayer: Bool
    }
    private var bullets: [Bullet] = []
    private let playerBulletSpeed: CGFloat = 500
    private let alienBulletSpeed: CGFloat = 200
    private let maxPlayerBullets = 3
    private var lastAlienShot: UInt64 = 0
    private var alienShotInterval: Double = 1.5
    private var lastPlayerShotTime: UInt64 = 0
    private let playerShotInterval: Double = 0.25  // 4 shots/sec

    // Ship
    private var shipX: CGFloat = 0
    private var shipY: CGFloat = 0

    // Lives
    private var lives = 3
    private var invulnerable = false
    private var invulnerableStart: UInt64 = 0
    private let invulnerableDuration: Double = 1.5
    private var blinkTimer: Int = 0

    // Scoring
    private let rowPoints = [10, 10, 20, 30, 30]  // bottom to top

    // Waves
    private var wave = 1
    private var waveStartGridY: CGFloat = 60

    // Mystery UFO
    private var ufoLayer: CALayer?
    private var ufoActive = false
    private var ufoX: CGFloat = 0
    private var ufoY: CGFloat = 30
    private var ufoDir: CGFloat = 1
    private let ufoSpeed: CGFloat = 150
    private var lastUfoSpawn: UInt64 = 0
    private var nextUfoDelay: Double = 20

    // Particles (death explosions + score pops)
    private struct Particle {
        let layer: CALayer
        var x: CGFloat
        var y: CGFloat
        var vx: CGFloat
        var vy: CGFloat
        var life: CGFloat      // seconds remaining
        let maxLife: CGFloat
    }
    private var particles: [Particle] = []

    // Game state
    private var gameWon = false

    // Input
    private var wasMouseDown = false

    // Overlay
    private var overlayWindow: NSWindow?
    private var overlayLayer: CALayer?

    private var savedScreen = CGRect.zero

    // Row colors for explosions (bottom to top)
    private let rowColors: [NSColor] = [
        NSColor(red: 0.0, green: 0.75, blue: 0.3, alpha: 1),    // green (squid)
        NSColor(red: 0.0, green: 0.65, blue: 0.4, alpha: 1),    // green (squid)
        NSColor(red: 0.0, green: 0.7, blue: 0.7, alpha: 1),     // teal (crab)
        NSColor(red: 0.5, green: 0.2, blue: 0.5, alpha: 1),     // purple (skull)
        NSColor(red: 0.6, green: 0.15, blue: 0.4, alpha: 1),    // plum (skull)
    ]

    // Animation frame tracking
    private var animFrame = 0
    private var animTickCounter = 0
    private let animTicksPerFrame = 30  // swap frames every ~240ms at 8ms tick

    // MARK: - Pixel Art Sprites

    private enum Sprites {
        // --- Squid (11x8, 2 frames) - Green palette with shading ---
        static let squidFrame1: CGImage? = GameBase.renderPixelArt([
            [0x000000, 0x000000, 0x000000, 0x000000, 0x000000, 0x1A6B2A, 0x000000, 0x000000, 0x000000, 0x000000, 0x000000],
            [0x000000, 0x000000, 0x000000, 0x000000, 0x1A6B2A, 0x2EAD40, 0x1A6B2A, 0x000000, 0x000000, 0x000000, 0x000000],
            [0x000000, 0x000000, 0x000000, 0x1A6B2A, 0x2EAD40, 0x3DD952, 0x2EAD40, 0x1A6B2A, 0x000000, 0x000000, 0x000000],
            [0x000000, 0x0F4D1A, 0x1A6B2A, 0xFFFFFF, 0x2EAD40, 0x3DD952, 0x2EAD40, 0xFFFFFF, 0x1A6B2A, 0x0F4D1A, 0x000000],
            [0x000000, 0x1A6B2A, 0x2EAD40, 0x3DD952, 0x3DD952, 0x50FF66, 0x3DD952, 0x3DD952, 0x2EAD40, 0x1A6B2A, 0x000000],
            [0x000000, 0x000000, 0x1A6B2A, 0x000000, 0x2EAD40, 0x000000, 0x2EAD40, 0x000000, 0x1A6B2A, 0x000000, 0x000000],
            [0x000000, 0x0F4D1A, 0x000000, 0x000000, 0x000000, 0x000000, 0x000000, 0x000000, 0x000000, 0x0F4D1A, 0x000000],
            [0x000000, 0x000000, 0x0F4D1A, 0x000000, 0x000000, 0x000000, 0x000000, 0x000000, 0x0F4D1A, 0x000000, 0x000000],
        ], scale: 3)

        static let squidFrame2: CGImage? = GameBase.renderPixelArt([
            [0x000000, 0x000000, 0x000000, 0x000000, 0x000000, 0x1A6B2A, 0x000000, 0x000000, 0x000000, 0x000000, 0x000000],
            [0x000000, 0x000000, 0x000000, 0x000000, 0x1A6B2A, 0x2EAD40, 0x1A6B2A, 0x000000, 0x000000, 0x000000, 0x000000],
            [0x000000, 0x000000, 0x000000, 0x1A6B2A, 0x2EAD40, 0x3DD952, 0x2EAD40, 0x1A6B2A, 0x000000, 0x000000, 0x000000],
            [0x000000, 0x0F4D1A, 0x1A6B2A, 0xFFFFFF, 0x2EAD40, 0x3DD952, 0x2EAD40, 0xFFFFFF, 0x1A6B2A, 0x0F4D1A, 0x000000],
            [0x000000, 0x1A6B2A, 0x2EAD40, 0x3DD952, 0x3DD952, 0x50FF66, 0x3DD952, 0x3DD952, 0x2EAD40, 0x1A6B2A, 0x000000],
            [0x000000, 0x000000, 0x1A6B2A, 0x000000, 0x2EAD40, 0x000000, 0x2EAD40, 0x000000, 0x1A6B2A, 0x000000, 0x000000],
            [0x000000, 0x000000, 0x0F4D1A, 0x000000, 0x000000, 0x000000, 0x000000, 0x000000, 0x0F4D1A, 0x000000, 0x000000],
            [0x000000, 0x0F4D1A, 0x000000, 0x000000, 0x000000, 0x000000, 0x000000, 0x000000, 0x000000, 0x0F4D1A, 0x000000],
        ], scale: 3)

        // --- Crab (11x8, 2 frames) - Teal/cyan palette with depth ---
        static let crabFrame1: CGImage? = GameBase.renderPixelArt([
            [0x000000, 0x000000, 0x1A8A8A, 0x000000, 0x000000, 0x000000, 0x000000, 0x000000, 0x1A8A8A, 0x000000, 0x000000],
            [0x000000, 0x000000, 0x000000, 0x1A8A8A, 0x000000, 0x000000, 0x000000, 0x1A8A8A, 0x000000, 0x000000, 0x000000],
            [0x000000, 0x000000, 0x1A8A8A, 0x2EC4C4, 0x3DE0E0, 0x3DE0E0, 0x3DE0E0, 0x2EC4C4, 0x1A8A8A, 0x000000, 0x000000],
            [0x000000, 0x1A8A8A, 0x2EC4C4, 0xFFFFFF, 0x3DE0E0, 0x50FFFF, 0x3DE0E0, 0xFFFFFF, 0x2EC4C4, 0x1A8A8A, 0x000000],
            [0x126060, 0x1A8A8A, 0x2EC4C4, 0x3DE0E0, 0x50FFFF, 0x50FFFF, 0x50FFFF, 0x3DE0E0, 0x2EC4C4, 0x1A8A8A, 0x126060],
            [0x126060, 0x000000, 0x1A8A8A, 0x2EC4C4, 0x3DE0E0, 0x3DE0E0, 0x3DE0E0, 0x2EC4C4, 0x1A8A8A, 0x000000, 0x126060],
            [0x126060, 0x000000, 0x1A8A8A, 0x000000, 0x000000, 0x000000, 0x000000, 0x000000, 0x1A8A8A, 0x000000, 0x126060],
            [0x000000, 0x000000, 0x000000, 0x1A8A8A, 0x126060, 0x000000, 0x126060, 0x1A8A8A, 0x000000, 0x000000, 0x000000],
        ], scale: 3)

        static let crabFrame2: CGImage? = GameBase.renderPixelArt([
            [0x000000, 0x000000, 0x1A8A8A, 0x000000, 0x000000, 0x000000, 0x000000, 0x000000, 0x1A8A8A, 0x000000, 0x000000],
            [0x1A8A8A, 0x000000, 0x000000, 0x1A8A8A, 0x000000, 0x000000, 0x000000, 0x1A8A8A, 0x000000, 0x000000, 0x1A8A8A],
            [0x1A8A8A, 0x000000, 0x1A8A8A, 0x2EC4C4, 0x3DE0E0, 0x3DE0E0, 0x3DE0E0, 0x2EC4C4, 0x1A8A8A, 0x000000, 0x1A8A8A],
            [0x1A8A8A, 0x1A8A8A, 0x2EC4C4, 0xFFFFFF, 0x3DE0E0, 0x50FFFF, 0x3DE0E0, 0xFFFFFF, 0x2EC4C4, 0x1A8A8A, 0x1A8A8A],
            [0x000000, 0x1A8A8A, 0x2EC4C4, 0x3DE0E0, 0x50FFFF, 0x50FFFF, 0x50FFFF, 0x3DE0E0, 0x2EC4C4, 0x1A8A8A, 0x000000],
            [0x000000, 0x000000, 0x1A8A8A, 0x2EC4C4, 0x3DE0E0, 0x3DE0E0, 0x3DE0E0, 0x2EC4C4, 0x1A8A8A, 0x000000, 0x000000],
            [0x000000, 0x000000, 0x1A8A8A, 0x000000, 0x000000, 0x000000, 0x000000, 0x000000, 0x1A8A8A, 0x000000, 0x000000],
            [0x000000, 0x000000, 0x126060, 0x1A8A8A, 0x000000, 0x000000, 0x000000, 0x1A8A8A, 0x126060, 0x000000, 0x000000],
        ], scale: 3)

        // --- Skull (11x8, 2 frames) - Purple/plum tones ---
        static let skullFrame1: CGImage? = GameBase.renderPixelArt([
            [0x000000, 0x000000, 0x000000, 0x4A1A6B, 0x6B2E9E, 0x7D3DB5, 0x6B2E9E, 0x4A1A6B, 0x000000, 0x000000, 0x000000],
            [0x000000, 0x000000, 0x4A1A6B, 0x6B2E9E, 0x7D3DB5, 0x9955CC, 0x7D3DB5, 0x6B2E9E, 0x4A1A6B, 0x000000, 0x000000],
            [0x000000, 0x4A1A6B, 0x6B2E9E, 0x7D3DB5, 0x9955CC, 0xAA66DD, 0x9955CC, 0x7D3DB5, 0x6B2E9E, 0x4A1A6B, 0x000000],
            [0x000000, 0x4A1A6B, 0x6B2E9E, 0xFF3333, 0x000000, 0x7D3DB5, 0x000000, 0xFF3333, 0x6B2E9E, 0x4A1A6B, 0x000000],
            [0x000000, 0x4A1A6B, 0x6B2E9E, 0x7D3DB5, 0x9955CC, 0xAA66DD, 0x9955CC, 0x7D3DB5, 0x6B2E9E, 0x4A1A6B, 0x000000],
            [0x000000, 0x000000, 0x000000, 0x4A1A6B, 0x6B2E9E, 0x000000, 0x6B2E9E, 0x4A1A6B, 0x000000, 0x000000, 0x000000],
            [0x000000, 0x000000, 0x4A1A6B, 0x000000, 0x4A1A6B, 0x000000, 0x4A1A6B, 0x000000, 0x4A1A6B, 0x000000, 0x000000],
            [0x3A0F52, 0x4A1A6B, 0x000000, 0x000000, 0x000000, 0x000000, 0x000000, 0x000000, 0x000000, 0x4A1A6B, 0x3A0F52],
        ], scale: 3)

        static let skullFrame2: CGImage? = GameBase.renderPixelArt([
            [0x000000, 0x000000, 0x000000, 0x4A1A6B, 0x6B2E9E, 0x7D3DB5, 0x6B2E9E, 0x4A1A6B, 0x000000, 0x000000, 0x000000],
            [0x000000, 0x000000, 0x4A1A6B, 0x6B2E9E, 0x7D3DB5, 0x9955CC, 0x7D3DB5, 0x6B2E9E, 0x4A1A6B, 0x000000, 0x000000],
            [0x000000, 0x4A1A6B, 0x6B2E9E, 0x7D3DB5, 0x9955CC, 0xAA66DD, 0x9955CC, 0x7D3DB5, 0x6B2E9E, 0x4A1A6B, 0x000000],
            [0x000000, 0x4A1A6B, 0x6B2E9E, 0xFF3333, 0x000000, 0x7D3DB5, 0x000000, 0xFF3333, 0x6B2E9E, 0x4A1A6B, 0x000000],
            [0x000000, 0x4A1A6B, 0x6B2E9E, 0x7D3DB5, 0x9955CC, 0xAA66DD, 0x9955CC, 0x7D3DB5, 0x6B2E9E, 0x4A1A6B, 0x000000],
            [0x000000, 0x000000, 0x000000, 0x4A1A6B, 0x6B2E9E, 0x000000, 0x6B2E9E, 0x4A1A6B, 0x000000, 0x000000, 0x000000],
            [0x000000, 0x000000, 0x000000, 0x4A1A6B, 0x000000, 0x4A1A6B, 0x000000, 0x4A1A6B, 0x000000, 0x000000, 0x000000],
            [0x000000, 0x000000, 0x4A1A6B, 0x3A0F52, 0x000000, 0x000000, 0x000000, 0x3A0F52, 0x4A1A6B, 0x000000, 0x000000],
        ], scale: 3)

        // --- UFO (16x8) - Red/pink with metallic shading, dome, portholes, antenna ---
        static let ufo: CGImage? = GameBase.renderPixelArt([
            [0x000000, 0x000000, 0x000000, 0x000000, 0x000000, 0x000000, 0x000000, 0xFFDD33, 0x000000, 0x000000, 0x000000, 0x000000, 0x000000, 0x000000, 0x000000, 0x000000],
            [0x000000, 0x000000, 0x000000, 0x000000, 0x000000, 0x000000, 0xCC3344, 0xDD5566, 0xCC3344, 0x000000, 0x000000, 0x000000, 0x000000, 0x000000, 0x000000, 0x000000],
            [0x000000, 0x000000, 0x000000, 0x000000, 0x000000, 0xAA2233, 0xCC3344, 0xEE7788, 0xCC3344, 0xAA2233, 0x000000, 0x000000, 0x000000, 0x000000, 0x000000, 0x000000],
            [0x000000, 0x000000, 0x000000, 0x881122, 0xAA2233, 0xCC3344, 0xDD5566, 0xEE7788, 0xDD5566, 0xCC3344, 0xAA2233, 0x881122, 0x000000, 0x000000, 0x000000, 0x000000],
            [0x000000, 0x000000, 0x881122, 0xAA2233, 0xCC3344, 0xFFDD33, 0xCC3344, 0xFFDD33, 0xCC3344, 0xFFDD33, 0xCC3344, 0xAA2233, 0x881122, 0x000000, 0x000000, 0x000000],
            [0x000000, 0x660011, 0x881122, 0xAA2233, 0xBB8899, 0xCC3344, 0xBB8899, 0xCC3344, 0xBB8899, 0xCC3344, 0xBB8899, 0xAA2233, 0x881122, 0x660011, 0x000000, 0x000000],
            [0x000000, 0x000000, 0x000000, 0x660011, 0x000000, 0x881122, 0x000000, 0x000000, 0x000000, 0x881122, 0x000000, 0x660011, 0x000000, 0x000000, 0x000000, 0x000000],
            [0x000000, 0x000000, 0x000000, 0x000000, 0x000000, 0x000000, 0x000000, 0x000000, 0x000000, 0x000000, 0x000000, 0x000000, 0x000000, 0x000000, 0x000000, 0x000000],
        ], scale: 3)

        // --- Player bullet (2x6) - Bright green core, lighter edges, glow ---
        static let playerBullet: CGImage? = GameBase.renderPixelArt([
            [0x88FFAA, 0x88FFAA],
            [0x44DD66, 0x44DD66],
            [0x00FF44, 0x00FF44],
            [0x00FF44, 0x00FF44],
            [0x44DD66, 0x44DD66],
            [0x88FFAA, 0x88FFAA],
        ], scale: 3)

        // --- Alien bullet (2x6) - Red core, orange edges ---
        static let alienBullet: CGImage? = GameBase.renderPixelArt([
            [0xFF8844, 0xFF8844],
            [0xFF4422, 0xFF4422],
            [0xDD1100, 0xDD1100],
            [0xDD1100, 0xDD1100],
            [0xFF4422, 0xFF4422],
            [0xFF8844, 0xFF8844],
        ], scale: 3)
    }

    private func spriteType(forRow row: Int) -> Int {
        switch row {
        case 0, 1: return 0  // squid
        case 2, 3: return 1  // crab
        default:   return 2  // skull
        }
    }

    private func spriteImage(forRow row: Int, frame: Int) -> CGImage? {
        let f = frame % 2
        switch spriteType(forRow: row) {
        case 0:  return f == 0 ? Sprites.squidFrame1 : Sprites.squidFrame2
        case 1:  return f == 0 ? Sprites.crabFrame1  : Sprites.crabFrame2
        default: return f == 0 ? Sprites.skullFrame1  : Sprites.skullFrame2
        }
    }

    private func buildSpriteLayer(row: Int) -> CALayer {
        let layer = CALayer()
        layer.bounds = CGRect(origin: .zero, size: CGSize(width: alienW, height: alienH))
        layer.contents = spriteImage(forRow: row, frame: 0)
        layer.magnificationFilter = .nearest
        layer.minificationFilter = .nearest
        return layer
    }

    private func buildUFOLayer() -> CALayer {
        let layer = CALayer()
        let w: CGFloat = 48  // 16 * 3
        let h: CGFloat = 24  // 8 * 3
        layer.bounds = CGRect(origin: .zero, size: CGSize(width: w, height: h))
        layer.contents = Sprites.ufo
        layer.magnificationFilter = .nearest
        layer.minificationFilter = .nearest
        return layer
    }

    // MARK: - GameBase Hooks

    override func onStart(screen: CGRect, pip: PipWindowInfo) {
        timerIntervalMs = 8
        gameWon = false
        wasMouseDown = false
        bullets = []
        aliens = []
        particles = []
        aliveCount = 0
        wave = 1
        lives = 3
        invulnerable = false
        baseSpeed = baseSpeedInitial
        alienShotInterval = 1.5
        waveStartGridY = 60
        ufoActive = false
        ufoLayer = nil
        lastPlayerShotTime = 0
        animFrame = 0
        animTickCounter = 0

        savedScreen = screen
        lastAlienShot = mach_absolute_time()
        lastUfoSpawn = lastAlienShot
        nextUfoDelay = Double.random(in: 20...30)

        // Ship position (AX coords)
        shipY = screen.maxY - cachedPipSize.height - 60
        shipX = screen.midX - cachedPipSize.width / 2

        // Center alien grid (AX coords)
        let gridW = CGFloat(cols) * alienW + CGFloat(cols - 1) * spacingX
        gridX = (screen.width - gridW) / 2
        gridY = waveStartGridY
        gridDir = 1

        if Thread.isMainThread {
            createOverlays(screen: screen)
        } else {
            DispatchQueue.main.sync { self.createOverlays(screen: screen) }
        }

        print("Invaders started")
    }

    override func onStop() {
        overlayWindow?.orderOut(nil)
        overlayWindow = nil
        overlayLayer = nil
        aliens = []
        bullets = []
        particles = []
        ufoLayer = nil
        ufoActive = false
        print("Invaders stopped")
    }

    // MARK: - Overlay Creation

    private func createOverlays(screen: CGRect) {
        // Full-screen game overlay
        let (ow, rootLayer) = createFullscreenOverlay(screen: screen)
        overlayLayer = rootLayer
        overlayWindow = ow

        spawnAlienGrid(rootLayer: rootLayer)

        // Score overlay (wider for wave + lives)
        createScoreOverlay(screen: screen, width: 200)
        scoreLabel?.font = NSFont.monospacedSystemFont(ofSize: 20, weight: .bold)
        scoreLabel?.stringValue = "W1  \(livesString())  0"
    }

    private func spawnAlienGrid(rootLayer: CALayer) {
        for row in 0..<rows {
            for _ in 0..<cols {
                let layer = buildSpriteLayer(row: row)
                rootLayer.addSublayer(layer)
                aliens.append(Alien(layer: layer, alive: true, row: row))
                aliveCount += 1
            }
        }
    }

    private func livesString() -> String {
        return String(repeating: "^", count: lives)
    }

    private func updateScoreDisplay() {
        scoreLabel?.stringValue = "W\(wave)  \(livesString())  \(score)"
    }

    // MARK: - Wave System

    private func startNextWave() {
        wave += 1
        baseSpeed = min(baseSpeed * 1.15, 200)
        alienShotInterval = max(alienShotInterval * 0.85, 0.3)
        waveStartGridY = min(waveStartGridY + 15, 200)

        // Clear old alien layers
        for alien in aliens {
            alien.layer.removeFromSuperlayer()
        }
        aliens = []
        aliveCount = 0

        // Clear bullets
        for b in bullets { b.layer.removeFromSuperlayer() }
        bullets = []

        // Reset grid
        let screen = savedScreen
        let gridW = CGFloat(cols) * alienW + CGFloat(cols - 1) * spacingX
        gridX = (screen.width - gridW) / 2
        gridY = waveStartGridY
        gridDir = 1

        if let rootLayer = overlayLayer {
            spawnAlienGrid(rootLayer: rootLayer)
        }

        updateScoreDisplay()
    }

    // MARK: - Game Loop

    override func gameTick() {
        guard active, let _ = cachedAXWindow else { return }

        let screen = getScreenFrame()
        savedScreen = screen
        let now = mach_absolute_time()
        let dt = deltaTime()

        // Refresh PiP size from AX
        refreshPipSize()
        let size = cachedPipSize

        // End screen
        if checkGameOverTimeout() { return }

        // --- Input ---
        guard let mousePos = mousePosition() else { return }
        let mouseDown = isMouseDown

        // Ship follows mouse X
        shipX = max(screen.minX, min(screen.maxX - size.width, mousePos.x - size.width / 2))

        // Hold-to-rapid-fire
        if mouseDown {
            let sinceLastPlayerShot = machToSeconds(now - lastPlayerShotTime)
            let canShoot = !wasMouseDown || sinceLastPlayerShot >= CGFloat(playerShotInterval)
            let playerBulletCount = bullets.filter { $0.isPlayer }.count
            if canShoot && playerBulletCount < maxPlayerBullets && !invulnerable {
                spawnBullet(x: shipX + size.width / 2 - 2, y: shipY - 12,
                            dy: -playerBulletSpeed, isPlayer: true)
                lastPlayerShotTime = now
            }
        }
        wasMouseDown = mouseDown

        // --- Invulnerability ---
        if invulnerable {
            let elapsed = machToSeconds(now - invulnerableStart)
            if elapsed >= CGFloat(invulnerableDuration) {
                invulnerable = false
            }
            blinkTimer += 1
        }

        // --- Animation frame ---
        animTickCounter += 1
        if animTickCounter >= animTicksPerFrame {
            animTickCounter = 0
            animFrame += 1
        }

        // --- Alien movement ---
        let ratio = 1.0 - CGFloat(aliveCount) / CGFloat(totalAliens)
        let speed = min(baseSpeed + (maxSpeed - baseSpeed) * ratio, maxSpeed)

        gridX += gridDir * speed * dt

        // Check if any alive alien hits screen edge
        var needReverse = false
        for (i, alien) in aliens.enumerated() where alien.alive {
            let col = i % cols
            let ax = gridX + CGFloat(col) * (alienW + spacingX)
            if ax <= screen.minX + 10 && gridDir < 0 { needReverse = true; break }
            if ax + alienW >= screen.maxX - 10 && gridDir > 0 { needReverse = true; break }
        }
        if needReverse {
            gridDir *= -1
            gridY += 20  // step down
        }

        // --- Alien shooting (only lowest alive in each column) ---
        let sinceLastShot = machToSeconds(now - lastAlienShot)
        if sinceLastShot > CGFloat(alienShotInterval) {
            lastAlienShot = now
            // Find lowest alive alien per column
            var lowestPerCol = [Int: Int]()  // col -> alien index
            for (i, alien) in aliens.enumerated() where alien.alive {
                let row = i / cols
                let col = i % cols
                if let existing = lowestPerCol[col] {
                    let existingRow = existing / cols
                    if row > existingRow { lowestPerCol[col] = i }
                } else {
                    lowestPerCol[col] = i
                }
            }
            // Pick a random column's lowest alien
            if let idx = lowestPerCol.values.randomElement() {
                let row = idx / cols
                let col = idx % cols
                let ax = gridX + CGFloat(col) * (alienW + spacingX) + alienW / 2 - 2
                let ay = gridY + CGFloat(row) * (alienH + spacingY) + alienH
                spawnBullet(x: ax, y: ay, dy: alienBulletSpeed, isPlayer: false)
            }
        }

        // --- Mystery UFO ---
        let sinceUfo = machToSeconds(now - lastUfoSpawn)
        if !ufoActive && sinceUfo > CGFloat(nextUfoDelay) {
            spawnUFO(screen: screen)
            lastUfoSpawn = now
            nextUfoDelay = Double.random(in: 20...30)
        }
        if ufoActive {
            ufoX += ufoDir * ufoSpeed * dt
            if ufoX < screen.minX - 50 || ufoX > screen.maxX + 50 {
                ufoLayer?.removeFromSuperlayer()
                ufoLayer = nil
                ufoActive = false
            }
        }

        // --- Move bullets ---
        for i in 0..<bullets.count {
            bullets[i].y += bullets[i].dy * dt
        }

        // --- Collision: player bullets vs aliens ---
        for bi in (0..<bullets.count).reversed() {
            guard bi < bullets.count, bullets[bi].isPlayer else { continue }
            let bRect = CGRect(x: bullets[bi].x, y: bullets[bi].y, width: bulletW, height: bulletH)

            var hit = false
            for ai in 0..<aliens.count {
                guard aliens[ai].alive else { continue }
                let row = ai / cols
                let col = ai % cols
                let aRect = CGRect(
                    x: gridX + CGFloat(col) * (alienW + spacingX),
                    y: gridY + CGFloat(row) * (alienH + spacingY),
                    width: alienW, height: alienH)

                if bRect.intersects(aRect) {
                    let killX = aRect.midX
                    let killY = aRect.midY
                    let points = rowPoints[row]

                    aliens[ai].alive = false
                    aliens[ai].layer.removeFromSuperlayer()
                    aliveCount -= 1
                    score += points

                    bullets[bi].layer.removeFromSuperlayer()
                    bullets.remove(at: bi)

                    // Death explosion
                    spawnExplosion(x: killX, y: killY, color: rowColors[row])
                    // Score pop
                    spawnScorePop(x: killX, y: killY, points: points)

                    updateScoreDisplay()

                    // Wave clear check
                    if aliveCount <= 0 {
                        startNextWave()
                    }
                    hit = true
                    break
                }
            }

            // Player bullet vs UFO
            if !hit && ufoActive, bi < bullets.count, bullets[bi].isPlayer {
                let ufoRect = CGRect(x: ufoX, y: ufoY, width: 48, height: 24)
                let bRect2 = CGRect(x: bullets[bi].x, y: bullets[bi].y, width: bulletW, height: bulletH)
                if bRect2.intersects(ufoRect) {
                    let ufoPoints = [50, 100, 150, 300].randomElement()!
                    score += ufoPoints
                    spawnExplosion(x: ufoX + 24, y: ufoY + 12,
                                   color: NSColor(red: 1, green: 0.3, blue: 0.3, alpha: 1))
                    spawnScorePop(x: ufoX + 24, y: ufoY + 12, points: ufoPoints)
                    ufoLayer?.removeFromSuperlayer()
                    ufoLayer = nil
                    ufoActive = false
                    bullets[bi].layer.removeFromSuperlayer()
                    bullets.remove(at: bi)
                    updateScoreDisplay()
                }
            }
        }

        // --- Collision: alien bullets vs ship ---
        if !invulnerable {
            let shipRect = CGRect(x: shipX + 4, y: shipY + 4, width: size.width - 8, height: size.height - 8)
            for bi in (0..<bullets.count).reversed() {
                guard !bullets[bi].isPlayer else { continue }
                let bRect = CGRect(x: bullets[bi].x, y: bullets[bi].y, width: bulletW, height: bulletH)
                if bRect.intersects(shipRect) {
                    bullets[bi].layer.removeFromSuperlayer()
                    bullets.remove(at: bi)
                    hitPlayer(now: now, screen: screen)
                    break
                }
            }
        }

        // --- Aliens reached ship level ---
        if !gameOver && !invulnerable {
            let lowestAlienY = lowestAliveAlienY()
            if lowestAlienY + alienH >= shipY {
                hitPlayer(now: now, screen: screen)
            }
        }

        // --- Remove off-screen bullets ---
        bullets.removeAll { b in
            let offscreen = b.y < -20 || b.y > screen.maxY + 20
            if offscreen { b.layer.removeFromSuperlayer() }
            return offscreen
        }

        // --- Update particles ---
        updateParticles(dt: dt)

        // --- Move PiP (ship) ---
        movePip(to: CGPoint(x: shipX, y: shipY))

        // --- Update visuals ---
        let bounds = CGRect(origin: CGPoint(x: shipX, y: shipY), size: size)

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        // Update alien positions and animation frames
        for (i, alien) in aliens.enumerated() where alien.alive {
            let row = i / cols
            let col = i % cols
            let ax = gridX + CGFloat(col) * (alienW + spacingX)
            let ay = gridY + CGFloat(row) * (alienH + spacingY)
            alien.layer.frame = CGRect(x: ax, y: screenH - ay - alienH, width: alienW, height: alienH)
            alien.layer.contents = spriteImage(forRow: row, frame: animFrame)
        }

        // Update bullet positions
        for b in bullets {
            b.layer.frame = CGRect(x: b.x, y: screenH - b.y - bulletH, width: bulletW, height: bulletH)
        }

        // Update UFO position
        if ufoActive, let ufo = ufoLayer {
            ufo.frame = CGRect(x: ufoX, y: screenH - ufoY - 14, width: 48, height: 24)
        }

        // Update particle positions
        for p in particles {
            p.layer.position = CGPoint(x: p.x, y: screenH - p.y)
            p.layer.opacity = Float(p.life / p.maxLife)
        }

        // Border — blink border during invulnerability instead of moving PiP offscreen
        let blinkHidden = invulnerable && blinkTimer % 8 < 4
        if settings.glow, let border = borderRef {
            if blinkHidden {
                border.hide()
            } else {
                border.show(around: bounds)
            }
        }

        CATransaction.commit()

        lastBounds = bounds
    }

    // MARK: - Helpers

    private let bulletW: CGFloat = 6   // 2 * 3
    private let bulletH: CGFloat = 18  // 6 * 3

    private func spawnBullet(x: CGFloat, y: CGFloat, dy: CGFloat, isPlayer: Bool) {
        guard let rootLayer = overlayLayer else { return }
        let layer = CALayer()
        layer.contents = isPlayer ? Sprites.playerBullet : Sprites.alienBullet
        layer.magnificationFilter = .nearest
        layer.minificationFilter = .nearest
        layer.frame = CGRect(x: x, y: screenH - y - bulletH, width: bulletW, height: bulletH)
        rootLayer.addSublayer(layer)
        bullets.append(Bullet(layer: layer, x: x, y: y, dy: dy, isPlayer: isPlayer))
    }

    private func spawnExplosion(x: CGFloat, y: CGFloat, color: NSColor) {
        guard let rootLayer = overlayLayer else { return }
        let count = Int.random(in: 8...14)
        for _ in 0..<count {
            let layer = CALayer()
            let s: CGFloat = CGFloat.random(in: 2...5)
            layer.bounds = CGRect(origin: .zero, size: CGSize(width: s, height: s))
            layer.backgroundColor = color.cgColor
            rootLayer.addSublayer(layer)

            let vx = CGFloat.random(in: -150...150)
            let vy = CGFloat.random(in: -150...150)
            particles.append(Particle(layer: layer, x: x, y: y, vx: vx, vy: vy,
                                       life: 0.45, maxLife: 0.45))
        }
    }

    private func spawnScorePop(x: CGFloat, y: CGFloat, points: Int) {
        guard let rootLayer = overlayLayer else { return }
        let textLayer = CATextLayer()
        textLayer.string = "+\(points)"
        textLayer.fontSize = 14
        textLayer.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .bold)
        textLayer.foregroundColor = NSColor.white.cgColor
        textLayer.alignmentMode = .center
        textLayer.bounds = CGRect(origin: .zero, size: CGSize(width: 50, height: 18))
        textLayer.contentsScale = 2
        rootLayer.addSublayer(textLayer)

        particles.append(Particle(layer: textLayer, x: x, y: y, vx: 0, vy: -60,
                                   life: 0.5, maxLife: 0.5))
    }

    private func spawnUFO(screen: CGRect) {
        guard let rootLayer = overlayLayer else { return }
        let layer = buildUFOLayer()
        rootLayer.addSublayer(layer)
        ufoLayer = layer
        ufoActive = true
        ufoY = 30
        // Random direction
        if Bool.random() {
            ufoX = screen.minX - 40
            ufoDir = 1
        } else {
            ufoX = screen.maxX + 40
            ufoDir = -1
        }
    }

    private func updateParticles(dt: CGFloat) {
        for i in (0..<particles.count).reversed() {
            particles[i].x += particles[i].vx * dt
            particles[i].y += particles[i].vy * dt
            particles[i].life -= dt
            if particles[i].life <= 0 {
                particles[i].layer.removeFromSuperlayer()
                particles.remove(at: i)
            }
        }
    }

    private func lowestAliveAlienY() -> CGFloat {
        var lowest: CGFloat = 0
        for (i, alien) in aliens.enumerated() where alien.alive {
            let row = i / cols
            let ay = gridY + CGFloat(row) * (alienH + spacingY)
            if ay > lowest { lowest = ay }
        }
        return lowest
    }

    private func hitPlayer(now: UInt64, screen: CGRect) {
        lives -= 1
        if lives <= 0 {
            triggerGameOver(message: "GAME OVER \(score)")
            print("Invaders game over: score=\(score)")
        } else {
            // Flash border red
            borderRef?.hide()
            invulnerable = true
            invulnerableStart = now
            blinkTimer = 0
            // Reset ship to center
            shipX = screen.midX - cachedPipSize.width / 2
            updateScoreDisplay()
        }
    }
}
