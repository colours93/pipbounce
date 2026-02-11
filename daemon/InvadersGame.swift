import Cocoa
import ApplicationServices

let invaders = InvadersGame()

class InvadersGame: MiniGame {
    var active = false
    var lastBounds = CGRect.zero

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
    private let baseSpeed: CGFloat = 40
    private let maxSpeed: CGFloat = 300
    private var aliveCount = 0

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
    private let alienShotInterval: Double = 1.5

    // Ship
    private var shipX: CGFloat = 0
    private var shipY: CGFloat = 0

    // Scoring
    private var score = 0
    private let rowPoints = [10, 10, 20, 30, 30]  // bottom to top
    private var scoreOverlay: NSWindow?
    private var scoreLabel: NSTextField?

    // Game state
    private var gameOver = false
    private var gameWon = false
    private var gameEndMach: UInt64 = 0

    // Input
    private var wasMouseDown = false

    // Overlay
    private var overlayWindow: NSWindow?
    private var overlayLayer: CALayer?

    // Timer & refs
    private var gameTimer: DispatchSourceTimer?
    private var cachedAXWindow: AXUIElement?
    private var cachedPipSize = CGSize.zero
    private var borderRef: RGBBorder?
    private var lastMach: UInt64 = 0
    private var screenH: CGFloat = 0

    // Mach time
    private static var timebaseInfo: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    private func machToSeconds(_ ticks: UInt64) -> CGFloat {
        let info = Self.timebaseInfo
        return CGFloat(Double(ticks) * Double(info.numer) / Double(info.denom) / 1_000_000_000)
    }

    // Row colors (bottom to top): dark terminal aesthetic
    private let rowColors: [NSColor] = [
        NSColor(red: 0.0, green: 0.45, blue: 0.2, alpha: 1),    // green
        NSColor(red: 0.0, green: 0.35, blue: 0.25, alpha: 1),   // teal
        NSColor(red: 0.2, green: 0.2, blue: 0.35, alpha: 1),    // slate
        NSColor(red: 0.35, green: 0.1, blue: 0.25, alpha: 1),   // plum
        NSColor(red: 0.45, green: 0.05, blue: 0.1, alpha: 1),   // blood
    ]

    // 11x8 pixel bitmaps — 3 alien types (classic silhouettes)
    // Type 0 (rows 0-1): squid
    // Type 1 (rows 2-3): crab
    // Type 2 (row 4):    skull
    private let sprites: [[UInt16]] = [
        // Squid
        [
            0b00000100000,
            0b00001110000,
            0b00011111000,
            0b01101110110,
            0b01111111110,
            0b00101010100,
            0b01000000010,
            0b00100000100,
        ],
        // Crab
        [
            0b00100000100,
            0b00010001000,
            0b00111111100,
            0b01101110110,
            0b11111111111,
            0b10111111101,
            0b10100000101,
            0b00011011000,
        ],
        // Skull
        [
            0b00011111000,
            0b01111111110,
            0b11111111111,
            0b11100010111,
            0b11111111111,
            0b00011011000,
            0b00110001100,
            0b11000000011,
        ],
    ]

    private func spriteType(forRow row: Int) -> Int {
        switch row {
        case 0, 1: return 0
        case 2, 3: return 1
        default:   return 2
        }
    }

    private func buildSpriteLayer(row: Int) -> CALayer {
        let container = CALayer()
        container.bounds = CGRect(origin: .zero, size: CGSize(width: alienW, height: alienH))
        let bitmap = sprites[spriteType(forRow: row)]
        let color = rowColors[row].cgColor
        let eyeColor = NSColor(red: 0.0, green: 0.8, blue: 0.35, alpha: 0.9).cgColor

        for py in 0..<spriteRows {
            let bits = bitmap[py]
            for pxCol in 0..<spriteCols {
                let bit = (bits >> (spriteCols - 1 - pxCol)) & 1
                if bit == 1 {
                    let block = CALayer()
                    // CALayer y is flipped (0=bottom), sprite y=0 is top
                    block.frame = CGRect(x: CGFloat(pxCol) * px,
                                         y: CGFloat(spriteRows - 1 - py) * px,
                                         width: px, height: px)
                    // Eyes glow green: row 3 for squid/crab, row 3 for skull
                    let isEyeRow = (spriteType(forRow: row) <= 1 && py == 3) ||
                                   (spriteType(forRow: row) == 2 && py == 3)
                    let isEyePixel = isEyeRow && bit == 1 &&
                                     (pxCol == 2 || pxCol == 3 || pxCol == 7 || pxCol == 8)
                    block.backgroundColor = isEyePixel ? eyeColor : color
                    container.addSublayer(block)
                }
            }
        }
        return container
    }

    // MARK: - MiniGame Protocol

    func start(screen: CGRect, pip: PipWindowInfo, border: RGBBorder) {
        score = 0
        gameOver = false
        gameWon = false
        wasMouseDown = false
        bullets = []
        aliens = []
        aliveCount = 0

        cachedAXWindow = pip.axWindow
        cachedPipSize = pip.bounds.size
        borderRef = border
        screenH = (NSScreen.main ?? NSScreen.screens[0]).frame.height
        lastMach = mach_absolute_time()
        lastAlienShot = lastMach

        // Ship position (AX coords)
        shipY = screen.maxY - cachedPipSize.height - 60
        shipX = screen.midX - cachedPipSize.width / 2

        // Center alien grid (AX coords)
        let gridW = CGFloat(cols) * alienW + CGFloat(cols - 1) * spacingX
        gridX = (screen.width - gridW) / 2
        gridY = 60  // near top
        gridDir = 1

        if Thread.isMainThread {
            createOverlays(screen: screen)
        } else {
            DispatchQueue.main.sync { self.createOverlays(screen: screen) }
        }

        active = true
        print("Invaders started")

        let t = DispatchSource.makeTimerSource(flags: .strict, queue: .main)
        t.schedule(deadline: .now(), repeating: .milliseconds(2), leeway: .microseconds(100))
        t.setEventHandler { [weak self] in self?.gameTick() }
        gameTimer = t
        t.resume()
    }

    func stop() {
        gameTimer?.cancel()
        gameTimer = nil
        active = false

        // Restore PiP to bottom-right
        if let axWindow = cachedAXWindow {
            let screen = getScreenFrame()
            var restorePos = CGPoint(x: screen.maxX - cachedPipSize.width - 20,
                                     y: screen.maxY - cachedPipSize.height - 20)
            if let val = AXValueCreate(.cgPoint, &restorePos) {
                AXUIElementSetAttributeValue(axWindow, kAXPositionAttribute as CFString, val)
            }
        }
        cachedAXWindow = nil

        borderRef?.hide()
        borderRef = nil

        let ow = overlayWindow, sw = scoreOverlay
        let cleanup = {
            ow?.orderOut(nil)
            sw?.orderOut(nil)
        }
        if Thread.isMainThread { cleanup() }
        else { DispatchQueue.main.async { cleanup() } }

        overlayWindow = nil
        overlayLayer = nil
        scoreOverlay = nil
        scoreLabel = nil
        aliens = []
        bullets = []
        print("Invaders stopped")
    }

    // MARK: - Overlay Creation

    private func createOverlays(screen: CGRect) {
        // Full-screen game overlay
        let ow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: screen.width, height: screenH),
                          styleMask: .borderless, backing: .buffered, defer: false)
        ow.isOpaque = false
        ow.backgroundColor = .clear
        ow.level = .floating
        ow.ignoresMouseEvents = true
        ow.hasShadow = false
        ow.collectionBehavior = [.canJoinAllSpaces, .stationary, .transient, .ignoresCycle]
        ow.contentView!.wantsLayer = true

        let rootLayer = ow.contentView!.layer!
        overlayLayer = rootLayer

        // Create pixel-art alien sprites
        for row in 0..<rows {
            for _ in 0..<cols {
                let layer = buildSpriteLayer(row: row)
                rootLayer.addSublayer(layer)
                aliens.append(Alien(layer: layer, alive: true, row: row))
                aliveCount += 1
            }
        }

        ow.orderFrontRegardless()
        overlayWindow = ow

        // Score overlay (same as other games)
        let sw = NSWindow(contentRect: NSRect(x: screen.midX - 80, y: screenH - 55, width: 160, height: 44),
                          styleMask: .borderless, backing: .buffered, defer: false)
        sw.isOpaque = false
        sw.backgroundColor = NSColor.black.withAlphaComponent(0.6)
        sw.level = .floating
        sw.ignoresMouseEvents = true
        sw.hasShadow = false
        sw.collectionBehavior = [.canJoinAllSpaces, .stationary, .transient, .ignoresCycle]

        let label = NSTextField(frame: NSRect(x: 0, y: 0, width: 160, height: 44))
        label.isEditable = false
        label.isBordered = false
        label.backgroundColor = .clear
        label.textColor = .white
        label.font = NSFont.monospacedSystemFont(ofSize: 24, weight: .bold)
        label.alignment = .center
        label.stringValue = "0"
        sw.contentView!.addSubview(label)
        sw.orderFrontRegardless()
        scoreOverlay = sw
        scoreLabel = label
    }

    // MARK: - Game Loop

    private func gameTick() {
        guard active, let axWindow = cachedAXWindow else { return }

        let screen = getScreenFrame()
        let size = cachedPipSize
        let now = mach_absolute_time()
        let dt = min(machToSeconds(now - lastMach), 0.05)
        lastMach = now

        // End screen
        if gameOver || gameWon {
            if machToSeconds(now - gameEndMach) > 2.5 { stop() }
            return
        }

        // --- Input ---
        guard let event = CGEvent(source: nil) else { return }
        let mousePos = event.location
        let mouseDown = NSEvent.pressedMouseButtons & 1 != 0

        // Ship follows mouse X
        shipX = max(screen.minX, min(screen.maxX - size.width, mousePos.x - size.width / 2))

        // Shoot on click
        if mouseDown && !wasMouseDown {
            let playerBulletCount = bullets.filter { $0.isPlayer }.count
            if playerBulletCount < maxPlayerBullets {
                spawnBullet(x: shipX + size.width / 2 - 2, y: shipY - 12,
                            dy: -playerBulletSpeed, isPlayer: true)
            }
        }
        wasMouseDown = mouseDown

        // --- Alien movement ---
        let speed = min(baseSpeed * (40.0 / max(CGFloat(aliveCount), 1)), maxSpeed)

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

        // --- Alien shooting ---
        let sinceLastShot = machToSeconds(now - lastAlienShot)
        if sinceLastShot > CGFloat(alienShotInterval) {
            lastAlienShot = now
            // Pick a random alive alien
            let aliveIndices = aliens.enumerated().compactMap { $0.element.alive ? $0.offset : nil }
            if let idx = aliveIndices.randomElement() {
                let row = idx / cols
                let col = idx % cols
                let ax = gridX + CGFloat(col) * (alienW + spacingX) + alienW / 2 - 2
                let ay = gridY + CGFloat(row) * (alienH + spacingY) + alienH
                spawnBullet(x: ax, y: ay, dy: alienBulletSpeed, isPlayer: false)
            }
        }

        // --- Move bullets ---
        for i in 0..<bullets.count {
            bullets[i].y += bullets[i].dy * dt
        }

        // --- Collision: player bullets vs aliens ---
        for bi in (0..<bullets.count).reversed() {
            guard bullets[bi].isPlayer else { continue }
            let bRect = CGRect(x: bullets[bi].x, y: bullets[bi].y, width: 4, height: 12)

            for ai in 0..<aliens.count {
                guard aliens[ai].alive else { continue }
                let row = ai / cols
                let col = ai % cols
                let aRect = CGRect(
                    x: gridX + CGFloat(col) * (alienW + spacingX),
                    y: gridY + CGFloat(row) * (alienH + spacingY),
                    width: alienW, height: alienH)

                if bRect.intersects(aRect) {
                    // Kill alien
                    aliens[ai].alive = false
                    aliens[ai].layer.isHidden = true
                    aliveCount -= 1
                    score += rowPoints[row]

                    // Remove bullet
                    bullets[bi].layer.removeFromSuperlayer()
                    bullets.remove(at: bi)

                    scoreLabel?.stringValue = "\(score)"

                    // Win check
                    if aliveCount <= 0 {
                        gameWon = true
                        gameEndMach = now
                        scoreLabel?.stringValue = "CLEARED! \(score)"
                        print("Invaders cleared: score=\(score)")
                    }
                    break
                }
            }
        }

        // --- Collision: alien bullets vs ship ---
        let shipRect = CGRect(x: shipX + 4, y: shipY + 4, width: size.width - 8, height: size.height - 8)
        for bi in (0..<bullets.count).reversed() {
            guard !bullets[bi].isPlayer else { continue }
            let bRect = CGRect(x: bullets[bi].x, y: bullets[bi].y, width: 4, height: 12)
            if bRect.intersects(shipRect) {
                triggerGameOver(now: now)
                break
            }
        }

        // --- Aliens reached ship level ---
        if !gameOver {
            let lowestAlienY = lowestAliveAlienY()
            if lowestAlienY + alienH >= shipY {
                triggerGameOver(now: now)
            }
        }

        // --- Remove off-screen bullets ---
        bullets.removeAll { b in
            let offscreen = b.y < -20 || b.y > screen.maxY + 20
            if offscreen { b.layer.removeFromSuperlayer() }
            return offscreen
        }

        // --- Move PiP (ship) ---
        var newPos = CGPoint(x: shipX, y: shipY)
        if let val = AXValueCreate(.cgPoint, &newPos) {
            let err = AXUIElementSetAttributeValue(axWindow, kAXPositionAttribute as CFString, val)
            if err != .success {
                stop()
                return
            }
        }

        // --- Update visuals ---
        let bounds = CGRect(origin: CGPoint(x: shipX, y: shipY), size: size)
        lastBounds = bounds

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        // Update alien positions
        for (i, alien) in aliens.enumerated() where alien.alive {
            let row = i / cols
            let col = i % cols
            let ax = gridX + CGFloat(col) * (alienW + spacingX)
            let ay = gridY + CGFloat(row) * (alienH + spacingY)
            // AX (y-down) → CALayer (y-up)
            alien.layer.frame = CGRect(x: ax, y: screenH - ay - alienH, width: alienW, height: alienH)
        }

        // Update bullet positions
        for b in bullets {
            b.layer.frame = CGRect(x: b.x, y: screenH - b.y - 12, width: 4, height: 12)
        }

        // Border
        if settings.glow, let border = borderRef {
            border.show(around: bounds)
        }

        CATransaction.commit()
    }

    // MARK: - Helpers

    private func spawnBullet(x: CGFloat, y: CGFloat, dy: CGFloat, isPlayer: Bool) {
        guard let rootLayer = overlayLayer else { return }
        let layer = CALayer()
        layer.backgroundColor = isPlayer
            ? NSColor(red: 0.0, green: 0.85, blue: 0.4, alpha: 0.9).cgColor
            : NSColor(red: 0.6, green: 0.0, blue: 0.15, alpha: 0.9).cgColor
        layer.frame = CGRect(x: x, y: screenH - y - 12, width: 4, height: 12)
        rootLayer.addSublayer(layer)
        bullets.append(Bullet(layer: layer, x: x, y: y, dy: dy, isPlayer: isPlayer))
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

    private func triggerGameOver(now: UInt64) {
        gameOver = true
        gameEndMach = now
        scoreLabel?.stringValue = "GAME OVER \(score)"
        print("Invaders game over: score=\(score)")
    }
}
