import Cocoa
import ApplicationServices

let asteroids = AsteroidsGame()

class AsteroidsGame: MiniGame {
    var active = false
    var lastBounds = CGRect.zero

    // Ship physics
    private var shipPos = CGPoint.zero
    private var shipVel = CGPoint.zero
    private let thrustAccel: CGFloat = 400
    private let friction: CGFloat = 0.985
    private let maxSpeed: CGFloat = 500

    // Asteroids
    private enum AsteroidSize: Int {
        case large = 0, medium = 1, small = 2
        var radius: CGFloat {
            switch self {
            case .large:  return 25
            case .medium: return 15
            case .small:  return 8
            }
        }
        var points: Int {
            switch self {
            case .large:  return 20
            case .medium: return 50
            case .small:  return 100
            }
        }
    }

    private struct Asteroid {
        let layer: CALayer
        var x: CGFloat
        var y: CGFloat
        var vx: CGFloat
        var vy: CGFloat
        var size: AsteroidSize
    }
    private var asteroidList: [Asteroid] = []

    // Bullets
    private struct Bullet {
        let layer: CALayer
        var x: CGFloat
        var y: CGFloat
        var vx: CGFloat
        var vy: CGFloat
        var spawnMach: UInt64
    }
    private var bullets: [Bullet] = []
    private let bulletSpeed: CGFloat = 600
    private let maxBullets = 5
    private let bulletLifetime: Double = 2.0

    // Wave
    private var wave = 0
    private var waveCleared = false
    private var waveClearMach: UInt64 = 0
    private let wavePauseSeconds: Double = 1.5

    // Score
    private var score = 0
    private var scoreOverlay: NSWindow?
    private var scoreLabel: NSTextField?

    // Game state
    private var gameOver = false
    private var gameEndMach: UInt64 = 0
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

    // MARK: - MiniGame Protocol

    func start(screen: CGRect, pip: PipWindowInfo, border: RGBBorder) {
        score = 0
        wave = 0
        gameOver = false
        waveCleared = false
        wasMouseDown = false
        bullets = []
        asteroidList = []

        cachedAXWindow = pip.axWindow
        cachedPipSize = pip.bounds.size
        borderRef = border
        screenH = (NSScreen.main ?? NSScreen.screens[0]).frame.height
        lastMach = mach_absolute_time()

        // Start ship in center of screen
        shipPos = CGPoint(x: screen.midX - cachedPipSize.width / 2,
                          y: screen.midY - cachedPipSize.height / 2)
        shipVel = .zero

        if Thread.isMainThread {
            createOverlays(screen: screen)
        } else {
            DispatchQueue.main.sync { self.createOverlays(screen: screen) }
        }

        // Spawn first wave
        spawnWave(screen: screen)

        active = true
        print("Asteroids started")

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
        asteroidList = []
        bullets = []
        print("Asteroids stopped")
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

        ow.orderFrontRegardless()
        overlayWindow = ow

        // Score overlay
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

    // MARK: - Wave Spawning

    private func spawnWave(screen: CGRect) {
        wave += 1
        let count = 3 + wave  // wave 1 = 4, wave 2 = 5, etc.

        for _ in 0..<count {
            spawnAsteroid(size: .large, screen: screen, avoidCenter: true)
        }

        waveCleared = false
    }

    private func spawnAsteroid(size: AsteroidSize, screen: CGRect,
                               x: CGFloat? = nil, y: CGFloat? = nil,
                               avoidCenter: Bool = false) {
        guard let rootLayer = overlayLayer else { return }

        let r = size.radius
        let diameter = r * 2

        // Position: either specified or random edge spawn
        var ax: CGFloat
        var ay: CGFloat

        if let px = x, let py = y {
            ax = px
            ay = py
        } else {
            // Spawn from a random screen edge
            let edge = Int.random(in: 0..<4)
            switch edge {
            case 0: // top
                ax = CGFloat.random(in: screen.minX...screen.maxX)
                ay = screen.minY - diameter
            case 1: // bottom
                ax = CGFloat.random(in: screen.minX...screen.maxX)
                ay = screen.maxY
            case 2: // left
                ax = screen.minX - diameter
                ay = CGFloat.random(in: screen.minY...screen.maxY)
            default: // right
                ax = screen.maxX
                ay = CGFloat.random(in: screen.minY...screen.maxY)
            }
        }

        // Random velocity
        let speed = CGFloat.random(in: 50...120)
        let angle = CGFloat.random(in: 0...(2 * .pi))
        let vx = cos(angle) * speed
        let vy = sin(angle) * speed

        // Create layer
        let layer = CALayer()
        layer.bounds = CGRect(origin: .zero, size: CGSize(width: diameter, height: diameter))

        switch size {
        case .large:
            layer.backgroundColor = NSColor(red: 0.18, green: 0.18, blue: 0.18, alpha: 1).cgColor
            layer.borderColor = NSColor(red: 0.0, green: 0.4, blue: 0.2, alpha: 0.6).cgColor
            layer.borderWidth = 1.5
            layer.cornerRadius = CGFloat.random(in: 6...14)
        case .medium:
            layer.backgroundColor = NSColor(red: 0.12, green: 0.12, blue: 0.12, alpha: 1).cgColor
            layer.borderColor = NSColor(red: 0.0, green: 0.45, blue: 0.2, alpha: 0.7).cgColor
            layer.borderWidth = 1.2
            layer.cornerRadius = CGFloat.random(in: 4...10)
        case .small:
            layer.backgroundColor = NSColor(red: 0.06, green: 0.06, blue: 0.06, alpha: 1).cgColor
            layer.borderColor = NSColor(red: 0.0, green: 0.85, blue: 0.4, alpha: 0.9).cgColor
            layer.borderWidth = 1.0
            layer.cornerRadius = CGFloat.random(in: 2...5)
        }

        rootLayer.addSublayer(layer)
        asteroidList.append(Asteroid(layer: layer, x: ax, y: ay, vx: vx, vy: vy, size: size))
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
        if gameOver {
            if machToSeconds(now - gameEndMach) > 2.0 { stop() }
            return
        }

        // Wave clear pause
        if waveCleared {
            if machToSeconds(now - waveClearMach) > CGFloat(wavePauseSeconds) {
                spawnWave(screen: screen)
            }
            // Still update visuals during pause
            updateVisuals(screen: screen, size: size, axWindow: axWindow)
            return
        }

        // --- Input ---
        guard let event = CGEvent(source: nil) else { return }
        let mousePos = event.location
        let mouseDown = NSEvent.pressedMouseButtons & 1 != 0

        // --- Ship thrust toward mouse ---
        let shipCenterX = shipPos.x + size.width / 2
        let shipCenterY = shipPos.y + size.height / 2
        let dx = mousePos.x - shipCenterX
        let dy = mousePos.y - shipCenterY
        let dist = sqrt(dx * dx + dy * dy)

        if dist > 5 {
            let nx = dx / dist
            let ny = dy / dist
            shipVel.x += nx * thrustAccel * dt
            shipVel.y += ny * thrustAccel * dt
        }

        // Friction
        shipVel.x *= friction
        shipVel.y *= friction

        // Speed cap
        let speed = sqrt(shipVel.x * shipVel.x + shipVel.y * shipVel.y)
        if speed > maxSpeed {
            let scale = maxSpeed / speed
            shipVel.x *= scale
            shipVel.y *= scale
        }

        // Move ship
        shipPos.x += shipVel.x * dt
        shipPos.y += shipVel.y * dt

        // Screen wrapping for ship
        if shipPos.x + size.width < 0 { shipPos.x = screen.maxX }
        if shipPos.x > screen.maxX { shipPos.x = -size.width }
        if shipPos.y + size.height < 0 { shipPos.y = screen.maxY }
        if shipPos.y > screen.maxY { shipPos.y = -size.height }

        // --- Shoot on click ---
        if mouseDown && !wasMouseDown {
            let playerBulletCount = bullets.count
            if playerBulletCount < maxBullets && dist > 1 {
                let bx = shipCenterX - 2
                let by = shipCenterY - 2
                let bvx = (dx / dist) * bulletSpeed
                let bvy = (dy / dist) * bulletSpeed
                spawnBullet(x: bx, y: by, vx: bvx, vy: bvy, spawnTime: now)
            }
        }
        wasMouseDown = mouseDown

        // --- Move asteroids ---
        for i in 0..<asteroidList.count {
            asteroidList[i].x += asteroidList[i].vx * dt
            asteroidList[i].y += asteroidList[i].vy * dt

            // Screen wrapping
            let r = asteroidList[i].size.radius
            let d = r * 2
            if asteroidList[i].x + d < 0 { asteroidList[i].x = screen.maxX }
            if asteroidList[i].x > screen.maxX { asteroidList[i].x = -d }
            if asteroidList[i].y + d < 0 { asteroidList[i].y = screen.maxY }
            if asteroidList[i].y > screen.maxY { asteroidList[i].y = -d }
        }

        // --- Move bullets ---
        for i in 0..<bullets.count {
            bullets[i].x += bullets[i].vx * dt
            bullets[i].y += bullets[i].vy * dt
        }

        // --- Remove expired/off-screen bullets ---
        bullets.removeAll { b in
            let age = machToSeconds(now - b.spawnMach)
            let offscreen = b.x < -20 || b.x > screen.maxX + 20 ||
                            b.y < -20 || b.y > screen.maxY + 20
            let expired = age > CGFloat(bulletLifetime)
            if offscreen || expired { b.layer.removeFromSuperlayer() }
            return offscreen || expired
        }

        // --- Collision: bullets vs asteroids ---
        var newAsteroids: [Asteroid] = []
        for bi in (0..<bullets.count).reversed() {
            let bRect = CGRect(x: bullets[bi].x, y: bullets[bi].y, width: 4, height: 4)
            var hit = false

            for ai in (0..<asteroidList.count).reversed() {
                let a = asteroidList[ai]
                let d = a.size.radius * 2
                let aRect = CGRect(x: a.x, y: a.y, width: d, height: d)

                if bRect.intersects(aRect) {
                    // Score
                    score += a.size.points
                    scoreLabel?.stringValue = "\(score)"

                    // Split asteroid
                    let splitAsteroids = splitAsteroid(a, screen: screen)
                    newAsteroids.append(contentsOf: splitAsteroids)

                    // Remove asteroid
                    a.layer.removeFromSuperlayer()
                    asteroidList.remove(at: ai)

                    // Remove bullet
                    bullets[bi].layer.removeFromSuperlayer()
                    bullets.remove(at: bi)

                    hit = true
                    break
                }
            }
            if hit { continue }
        }
        asteroidList.append(contentsOf: newAsteroids)

        // --- Collision: ship vs asteroids ---
        let shipRect = CGRect(x: shipPos.x + 4, y: shipPos.y + 4,
                              width: size.width - 8, height: size.height - 8)
        for a in asteroidList {
            let d = a.size.radius * 2
            let aRect = CGRect(x: a.x + 4, y: a.y + 4, width: d - 8, height: d - 8)
            if shipRect.intersects(aRect) {
                gameOver = true
                gameEndMach = now
                scoreLabel?.stringValue = "GAME OVER \(score)"
                print("Asteroids game over: score=\(score)")
                break
            }
        }

        // --- Wave clear check ---
        if !gameOver && asteroidList.isEmpty {
            waveCleared = true
            waveClearMach = now
            scoreLabel?.stringValue = "WAVE \(wave)! \(score)"
            print("Asteroids wave \(wave) cleared: score=\(score)")
        }

        // --- Update visuals ---
        updateVisuals(screen: screen, size: size, axWindow: axWindow)
    }

    // MARK: - Helpers

    private func updateVisuals(screen: CGRect, size: CGSize, axWindow: AXUIElement) {
        // Move PiP via AX
        var newPos = shipPos
        if let val = AXValueCreate(.cgPoint, &newPos) {
            let err = AXUIElementSetAttributeValue(axWindow, kAXPositionAttribute as CFString, val)
            if err != .success {
                stop()
                return
            }
        }

        let bounds = CGRect(origin: shipPos, size: size)
        lastBounds = bounds

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        // Update asteroid positions (AX y-down -> CALayer y-up)
        for a in asteroidList {
            let d = a.size.radius * 2
            a.layer.frame = CGRect(x: a.x, y: screenH - a.y - d, width: d, height: d)
        }

        // Update bullet positions
        for b in bullets {
            b.layer.frame = CGRect(x: b.x, y: screenH - b.y - 4, width: 4, height: 4)
        }

        // Border
        if settings.glow, let border = borderRef {
            border.show(around: bounds)
        }

        CATransaction.commit()
    }

    private func spawnBullet(x: CGFloat, y: CGFloat, vx: CGFloat, vy: CGFloat, spawnTime: UInt64) {
        guard let rootLayer = overlayLayer else { return }
        let layer = CALayer()
        layer.backgroundColor = NSColor(red: 0.0, green: 0.85, blue: 0.4, alpha: 0.9).cgColor
        layer.frame = CGRect(x: x, y: screenH - y - 4, width: 4, height: 4)
        rootLayer.addSublayer(layer)
        bullets.append(Bullet(layer: layer, x: x, y: y, vx: vx, vy: vy, spawnMach: spawnTime))
    }

    private func splitAsteroid(_ a: Asteroid, screen: CGRect) -> [Asteroid] {
        guard let rootLayer = overlayLayer else { return [] }

        let nextSize: AsteroidSize?
        switch a.size {
        case .large:  nextSize = .medium
        case .medium: nextSize = .small
        case .small:  nextSize = nil
        }

        guard let ns = nextSize else { return [] }

        var result: [Asteroid] = []
        for _ in 0..<2 {
            let r = ns.radius
            let d = r * 2

            // Slightly randomized velocity, faster than parent
            let speedMult: CGFloat = 1.4
            let baseVx = a.vx * speedMult
            let baseVy = a.vy * speedMult
            let jitterAngle = CGFloat.random(in: -0.6...0.6)
            let cos_a = cos(jitterAngle)
            let sin_a = sin(jitterAngle)
            let nvx = baseVx * cos_a - baseVy * sin_a
            let nvy = baseVx * sin_a + baseVy * cos_a

            let layer = CALayer()
            layer.bounds = CGRect(origin: .zero, size: CGSize(width: d, height: d))

            switch ns {
            case .large:
                layer.backgroundColor = NSColor(red: 0.18, green: 0.18, blue: 0.18, alpha: 1).cgColor
                layer.borderColor = NSColor(red: 0.0, green: 0.4, blue: 0.2, alpha: 0.6).cgColor
                layer.borderWidth = 1.5
                layer.cornerRadius = CGFloat.random(in: 6...14)
            case .medium:
                layer.backgroundColor = NSColor(red: 0.12, green: 0.12, blue: 0.12, alpha: 1).cgColor
                layer.borderColor = NSColor(red: 0.0, green: 0.45, blue: 0.2, alpha: 0.7).cgColor
                layer.borderWidth = 1.2
                layer.cornerRadius = CGFloat.random(in: 4...10)
            case .small:
                layer.backgroundColor = NSColor(red: 0.06, green: 0.06, blue: 0.06, alpha: 1).cgColor
                layer.borderColor = NSColor(red: 0.0, green: 0.85, blue: 0.4, alpha: 0.9).cgColor
                layer.borderWidth = 1.0
                layer.cornerRadius = CGFloat.random(in: 2...5)
            }

            rootLayer.addSublayer(layer)
            result.append(Asteroid(layer: layer, x: a.x, y: a.y, vx: nvx, vy: nvy, size: ns))
        }
        return result
    }
}
