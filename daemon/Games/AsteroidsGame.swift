import Cocoa
import ApplicationServices



class AsteroidsGame: GameBase {

    // Ship physics (world coordinates)
    private var shipPos = CGPoint.zero
    private var shipVel = CGPoint.zero
    private let thrustAccel: CGFloat = 400
    private let driftHalfLife: CGFloat = 1.0
    private let maxSpeed: CGFloat = 500

    // Camera (world coordinates of viewport top-left)
    private var cameraX: CGFloat = 0
    private var cameraY: CGFloat = 0
    private let cameraLerp: CGFloat = 0.08

    // World size (set at start, 3x screen)
    private var worldW: CGFloat = 0
    private var worldH: CGFloat = 0

    // Lives & invulnerability
    private var lives = 3
    private var invulnerable = false
    private var invulnerableEndMach: UInt64 = 0
    private let invulnerableDuration: Double = 2.0
    private let blinkFrequency: CGFloat = 4.0

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
        var rotation: CGFloat
        var rotationSpeed: CGFloat
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
    private let bulletLifetime: Double = 1.2

    // Auto-fire
    private var lastShotMach: UInt64 = 0
    private let autoFireInterval: Double = 0.25

    // Explosion emitter (burst on demand)
    private var explosionEmitter: CAEmitterLayer?

    // Thrust emitter (continuous while thrusting)
    private var thrustEmitter: CAEmitterLayer?

    // Space dust emitter (ambient)
    private var dustEmitter: CAEmitterLayer?

    // Wave
    private var wave = 0
    private var waveCleared = false
    private var waveClearMach: UInt64 = 0
    private let wavePauseSeconds: Double = 1.5

    // Input
    private var wasMouseDown = false

    // MARK: - Pixel Art Sprites (see AsteroidsSprites.swift)

    private enum Sprites {
        static var bullet: CGImage? { AsteroidsSprites.bullet }

        static func variants(for size: AsteroidSize) -> [CGImage] {
            switch size {
            case .large:  return AsteroidsSprites.largeVariants
            case .medium: return AsteroidsSprites.mediumVariants
            case .small:  return AsteroidsSprites.smallVariants
            }
        }

        static func displaySize(for size: AsteroidSize) -> CGSize {
            switch size {
            case .large:  return CGSize(width: 48, height: 48)
            case .medium: return CGSize(width: 30, height: 30)
            case .small:  return CGSize(width: 12, height: 12)
            }
        }
    }

    // Overlay
    private var overlayWindow: NSWindow?
    private var overlayLayer: CALayer?

    private var savedScreen = CGRect.zero

    // MARK: - Coordinate conversion

    private func worldToScreen(_ wx: CGFloat, _ wy: CGFloat) -> CGPoint {
        CGPoint(x: wx - cameraX + savedScreen.minX,
                y: wy - cameraY + savedScreen.minY)
    }

    private func screenToWorld(_ sx: CGFloat, _ sy: CGFloat) -> CGPoint {
        CGPoint(x: sx + cameraX - savedScreen.minX,
                y: sy + cameraY - savedScreen.minY)
    }

    private func wrap(_ val: CGFloat, _ max: CGFloat) -> CGFloat {
        var v = val
        while v < 0 { v += max }
        while v >= max { v -= max }
        return v
    }

    // MARK: - GameBase Hooks

    override func onStart(screen: CGRect, pip: PipWindowInfo) {
        timerIntervalMs = 8
        wave = 0
        lives = 3
        invulnerable = false
        waveCleared = false
        wasMouseDown = false
        lastShotMach = 0
        bullets = []
        asteroidList = []
        savedScreen = screen

        // World = 3x screen
        worldW = screen.width * 3
        worldH = screen.height * 3

        // Start ship in center of world
        shipPos = CGPoint(x: worldW / 2 - cachedPipSize.width / 2,
                          y: worldH / 2 - cachedPipSize.height / 2)
        shipVel = .zero

        // Center camera on ship
        cameraX = shipPos.x + cachedPipSize.width / 2 - screen.width / 2
        cameraY = shipPos.y + cachedPipSize.height / 2 - screen.height / 2

        if Thread.isMainThread {
            createOverlays(screen: screen)
        } else {
            DispatchQueue.main.sync { self.createOverlays(screen: screen) }
        }

        spawnWave(screen: screen)

        print("Asteroids started (world=\(Int(worldW))x\(Int(worldH)))")
    }

    override func onStop() {
        let ow = overlayWindow
        let cleanup = {
            ow?.orderOut(nil)
        }
        if Thread.isMainThread { cleanup() }
        else { DispatchQueue.main.async { cleanup() } }

        overlayWindow = nil
        overlayLayer = nil
        explosionEmitter = nil
        thrustEmitter = nil
        dustEmitter = nil
        asteroidList = []
        bullets = []
        print("Asteroids stopped")
    }

    // MARK: - Overlay Creation

    private func createOverlays(screen: CGRect) {
        let ow = NSWindow(contentRect: NSRect(x: screen.minX, y: 0, width: screen.width, height: screenH),
                          styleMask: .borderless, backing: .buffered, defer: false)
        ow.isOpaque = false
        ow.backgroundColor = .clear
        ow.level = .floating
        ow.ignoresMouseEvents = true
        ow.hasShadow = false
        ow.collectionBehavior = [.canJoinAllSpaces, .stationary, .transient, .ignoresCycle]
        ow.contentView!.wantsLayer = true

        let rootLayer = ow.contentView!.layer!
        rootLayer.masksToBounds = true
        overlayLayer = rootLayer

        // Explosion emitter (burst on demand, birthRate=0 normally)
        let expEmitter = CAEmitterLayer()
        expEmitter.emitterPosition = CGPoint(x: screen.width / 2, y: screen.height / 2)
        expEmitter.emitterSize = CGSize(width: 1, height: 1)
        expEmitter.emitterShape = .point
        expEmitter.renderMode = .additive
        expEmitter.birthRate = 0

        let expCell = CAEmitterCell()
        expCell.name = "explosion"
        expCell.contents = Self.makeCircleImage(diameter: 6, color: .green)
        expCell.birthRate = 150
        expCell.lifetime = 0.4
        expCell.velocity = 180
        expCell.velocityRange = 80
        expCell.emissionRange = .pi * 2
        expCell.scale = 0.5
        expCell.scaleRange = 0.3
        expCell.scaleSpeed = -0.8
        expCell.alphaSpeed = -2.5
        expEmitter.emitterCells = [expCell]
        rootLayer.addSublayer(expEmitter)
        explosionEmitter = expEmitter

        // Thrust emitter (continuous flame behind ship)
        let thrEmitter = CAEmitterLayer()
        thrEmitter.emitterPosition = .zero
        thrEmitter.emitterSize = CGSize(width: 4, height: 2)
        thrEmitter.emitterShape = .line
        thrEmitter.renderMode = .additive
        thrEmitter.birthRate = 0

        let thrOrange = CAEmitterCell()
        thrOrange.contents = Self.makeCircleImage(diameter: 6, color: NSColor(red: 1.0, green: 0.45, blue: 0.0, alpha: 1.0))
        thrOrange.birthRate = 60
        thrOrange.lifetime = 0.3
        thrOrange.velocity = 100
        thrOrange.velocityRange = 30
        thrOrange.emissionLongitude = 0
        thrOrange.emissionRange = .pi / 6
        thrOrange.scale = 0.4
        thrOrange.scaleSpeed = -1.0
        thrOrange.alphaSpeed = -3.0

        let thrYellow = CAEmitterCell()
        thrYellow.contents = Self.makeCircleImage(diameter: 4, color: NSColor(red: 1.0, green: 0.85, blue: 0.2, alpha: 1.0))
        thrYellow.birthRate = 40
        thrYellow.lifetime = 0.2
        thrYellow.velocity = 80
        thrYellow.velocityRange = 20
        thrYellow.emissionLongitude = 0
        thrYellow.emissionRange = .pi / 8
        thrYellow.scale = 0.3
        thrYellow.scaleSpeed = -1.0
        thrYellow.alphaSpeed = -4.0

        thrEmitter.emitterCells = [thrOrange, thrYellow]
        rootLayer.addSublayer(thrEmitter)
        thrustEmitter = thrEmitter

        // Space dust emitter (ambient)
        let dustEm = CAEmitterLayer()
        dustEm.emitterPosition = CGPoint(x: screen.width / 2, y: screen.height / 2)
        dustEm.emitterSize = CGSize(width: screen.width, height: screen.height)
        dustEm.emitterShape = .rectangle
        dustEm.renderMode = .oldestFirst
        dustEm.birthRate = 1

        let dustCell = CAEmitterCell()
        dustCell.contents = Self.makeCircleImage(diameter: 2, color: .white)
        dustCell.birthRate = 3
        dustCell.lifetime = 10
        dustCell.velocity = 8
        dustCell.velocityRange = 5
        dustCell.emissionRange = .pi * 2
        dustCell.scale = 0.3
        dustCell.scaleRange = 0.2
        dustCell.alphaRange = 0.1
        dustCell.color = NSColor(white: 1.0, alpha: 0.25).cgColor

        dustEm.emitterCells = [dustCell]
        rootLayer.addSublayer(dustEm)
        dustEmitter = dustEm

        ow.orderFrontRegardless()
        overlayWindow = ow

        createScoreOverlay(screen: screen, width: 180)
        scoreLabel?.attributedStringValue = Self.styledScore(livesString())
    }

    private func livesString() -> String {
        let hearts = String(repeating: "\u{2764}", count: lives)
        return "\(score) \(hearts)"
    }

    // MARK: - Wave Spawning

    private func spawnWave(screen: CGRect) {
        wave += 1
        let count = 3 + wave

        for _ in 0..<count {
            spawnAsteroid(size: .large)
        }

        waveCleared = false
    }

    private func spawnAsteroid(size: AsteroidSize, x: CGFloat? = nil, y: CGFloat? = nil) {
        guard let rootLayer = overlayLayer else { return }

        let displaySize = Sprites.displaySize(for: size)

        var ax: CGFloat
        var ay: CGFloat

        if let px = x, let py = y {
            ax = px
            ay = py
        } else {
            ax = CGFloat.random(in: 0...worldW)
            ay = CGFloat.random(in: 0...worldH)
            let shipCenter = CGPoint(x: shipPos.x + cachedPipSize.width / 2, y: shipPos.y + cachedPipSize.height / 2)
            for _ in 0..<20 {
                if Self.distance(CGPoint(x: ax, y: ay), shipCenter) > 300 {
                    break
                }
                ax = CGFloat.random(in: 0...worldW)
                ay = CGFloat.random(in: 0...worldH)
            }
        }

        let w = min(wave, 10)
        let minSpeed: CGFloat = 50 + CGFloat(w) * 5
        let maxSpd: CGFloat = 120 + CGFloat(w) * 8
        let speed = CGFloat.random(in: minSpeed...maxSpd)
        let angle = CGFloat.random(in: 0...(2 * .pi))
        let vx = cos(angle) * speed
        let vy = sin(angle) * speed

        let rotSpeed = CGFloat.random(in: -2...2)

        let layer = layerPool.dequeue()
        layer.bounds = CGRect(origin: .zero, size: displaySize)
        let variants = Sprites.variants(for: size)
        if !variants.isEmpty {
            layer.contents = variants.randomElement()!
        }
        layer.magnificationFilter = .nearest
        layer.minificationFilter = .nearest

        rootLayer.addSublayer(layer)
        asteroidList.append(Asteroid(layer: layer, x: ax, y: ay, vx: vx, vy: vy,
                                     size: size, rotation: 0, rotationSpeed: rotSpeed))
    }

    // MARK: - CAEmitterLayer Helpers

    private static func makeCircleImage(diameter: CGFloat, color: NSColor) -> CGImage? {
        let size = CGSize(width: diameter, height: diameter)
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(diameter),
                                    pixelsHigh: Int(diameter), bitsPerSample: 8,
                                    samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let ctx = NSGraphicsContext.current!.cgContext
        ctx.setFillColor(color.cgColor)
        ctx.fillEllipse(in: CGRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        return rep.cgImage
    }

    private func emitExplosion(at screenPt: CGPoint, color: NSColor) {
        guard let emitter = explosionEmitter else { return }
        // Update cell color
        if let cell = emitter.emitterCells?.first {
            cell.contents = Self.makeCircleImage(diameter: 6, color: color)
        }
        emitter.emitterPosition = screenPt
        // Burst: set birthRate high briefly, then back to 0
        emitter.birthRate = 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            emitter.birthRate = 0
        }
    }

    // MARK: - Game Loop

    override func gameTick() {
        guard active, let axWindow = cachedAXWindow else { return }

        let screen = getScreenFrame()
        savedScreen = screen
        let dt = deltaTime()
        let now = mach_absolute_time()

        refreshPipSize()
        let size = cachedPipSize

        if checkGameOverTimeout() { return }

        if waveCleared {
            if machToSeconds(now - waveClearMach) > CGFloat(wavePauseSeconds) {
                spawnWave(screen: screen)
            }
            updateCamera(screen: screen, size: size)
            updateVisuals(screen: screen, size: size, axWindow: axWindow, now: now)
            return
        }

        if invulnerable && now >= invulnerableEndMach {
            invulnerable = false
        }

        // --- Input ---
        guard let mousePos = mousePosition() else { return }

        let mouseWorld = screenToWorld(mousePos.x, mousePos.y)
        let mouseDown = isMouseDown

        let shipCenterX = shipPos.x + size.width / 2
        let shipCenterY = shipPos.y + size.height / 2
        let dx = mouseWorld.x - shipCenterX
        let dy = mouseWorld.y - shipCenterY
        let dist = sqrt(dx * dx + dy * dy)

        if dist > 5 {
            let nx = dx / dist
            let ny = dy / dist
            shipVel.x += nx * thrustAccel * dt
            shipVel.y += ny * thrustAccel * dt
        }

        let f = pow(0.5, dt / driftHalfLife)
        shipVel.x *= f
        shipVel.y *= f

        let speed = sqrt(shipVel.x * shipVel.x + shipVel.y * shipVel.y)
        if speed > maxSpeed {
            let scale = maxSpeed / speed
            shipVel.x *= scale
            shipVel.y *= scale
        }

        shipPos.x += shipVel.x * dt
        shipPos.y += shipVel.y * dt

        // World wrapping for ship
        shipPos.x = wrap(shipPos.x + size.width / 2, worldW) - size.width / 2
        shipPos.y = wrap(shipPos.y + size.height / 2, worldH) - size.height / 2

        // --- Shoot ---
        if mouseDown && dist > 1 {
            let sinceLastShot = machToSeconds(now - lastShotMach)
            let shouldShoot: Bool
            if !wasMouseDown {
                shouldShoot = true
            } else {
                shouldShoot = sinceLastShot >= CGFloat(autoFireInterval)
            }

            if shouldShoot && bullets.count < maxBullets {
                let bx = shipCenterX - 2
                let by = shipCenterY - 2
                let bvx = (dx / dist) * bulletSpeed
                let bvy = (dy / dist) * bulletSpeed
                spawnBullet(x: bx, y: by, vx: bvx, vy: bvy, spawnTime: now)
                lastShotMach = now
            }
        }
        wasMouseDown = mouseDown

        // --- Move asteroids (world wrap) ---
        for i in 0..<asteroidList.count {
            asteroidList[i].x += asteroidList[i].vx * dt
            asteroidList[i].y += asteroidList[i].vy * dt
            asteroidList[i].rotation += asteroidList[i].rotationSpeed * dt

            let d = asteroidList[i].size.radius * 2
            asteroidList[i].x = wrap(asteroidList[i].x + d / 2, worldW) - d / 2
            asteroidList[i].y = wrap(asteroidList[i].y + d / 2, worldH) - d / 2
        }

        // --- Move bullets (world wrap) ---
        for i in 0..<bullets.count {
            bullets[i].x += bullets[i].vx * dt
            bullets[i].y += bullets[i].vy * dt
            bullets[i].x = wrap(bullets[i].x, worldW)
            bullets[i].y = wrap(bullets[i].y, worldH)
        }

        // Remove expired bullets
        bullets.removeAll { b in
            let age = machToSeconds(now - b.spawnMach)
            if age > CGFloat(bulletLifetime) {
                layerPool.enqueue(b.layer)
                b.layer.removeFromSuperlayer()
                return true
            }
            return false
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

                if Self.rectsCollide(bRect, aRect) {
                    score += a.size.points
                    scoreLabel?.attributedStringValue = Self.styledScore(livesString())

                    let expColor = NSColor(red: 0.0, green: 0.85, blue: 0.4, alpha: 1)
                    let expWorld = worldToScreen(a.x + a.size.radius, a.y + a.size.radius)
                    emitExplosion(at: CGPoint(x: expWorld.x - screen.minX, y: screenH - expWorld.y), color: expColor)

                    let splitAsteroids = splitAsteroid(a)
                    newAsteroids.append(contentsOf: splitAsteroids)

                    layerPool.enqueue(a.layer)
                    a.layer.removeFromSuperlayer()
                    asteroidList.remove(at: ai)

                    layerPool.enqueue(bullets[bi].layer)
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
        if !invulnerable {
            let shipRect = CGRect(x: shipPos.x + 4, y: shipPos.y + 4,
                                  width: size.width - 8, height: size.height - 8)
            for a in asteroidList {
                let d = a.size.radius * 2
                let aRect = CGRect(x: a.x + 4, y: a.y + 4, width: d - 8, height: d - 8)
                if Self.rectsCollide(shipRect, aRect) {
                    lives -= 1
                    if lives <= 0 {
                        triggerGameOver(message: "GAME OVER \(score)")
                        print("Asteroids game over: score=\(score)")
                    } else {
                        let cx = shipPos.x + size.width / 2
                        let cy = shipPos.y + size.height / 2
                        asteroidList.removeAll { ast in
                            let astCenter = CGPoint(x: ast.x + ast.size.radius, y: ast.y + ast.size.radius)
                            let close = Self.distance(astCenter, CGPoint(x: cx, y: cy)) < 150
                            if close {
                                let ec = NSColor(red: 1.0, green: 0.4, blue: 0.1, alpha: 1)
                                let ew = self.worldToScreen(ast.x + ast.size.radius, ast.y + ast.size.radius)
                                self.emitExplosion(at: CGPoint(x: ew.x - screen.minX, y: self.screenH - ew.y), color: ec)
                                self.layerPool.enqueue(ast.layer)
                                ast.layer.removeFromSuperlayer()
                            }
                            return close
                        }
                        shipPos = CGPoint(x: worldW / 2 - size.width / 2,
                                          y: worldH / 2 - size.height / 2)
                        shipVel = .zero
                        invulnerable = true
                        invulnerableEndMach = now + secondsToMach(Double(invulnerableDuration))
                        scoreLabel?.attributedStringValue = Self.styledScore(livesString())
                        print("Asteroids lost life, \(lives) remaining")
                    }
                    break
                }
            }
        }

        // --- Wave clear ---
        if !gameOver && asteroidList.isEmpty {
            waveCleared = true
            waveClearMach = now
            scoreLabel?.attributedStringValue = Self.styledScore("WAVE \(wave)! \(score)")
            print("Asteroids wave \(wave) cleared: score=\(score)")
        }

        // --- Camera & visuals ---
        updateCamera(screen: screen, size: size)
        updateVisuals(screen: screen, size: size, axWindow: axWindow, now: now)
    }

    // MARK: - Camera

    /// Shortest signed delta on a wrapping axis (result in -max/2...max/2)
    private func wrapDelta(_ a: CGFloat, _ b: CGFloat, _ wMax: CGFloat) -> CGFloat {
        var d = a - b
        if d > wMax / 2 { d -= wMax }
        if d < -wMax / 2 { d += wMax }
        return d
    }

    private func updateCamera(screen: CGRect, size: CGSize) {
        let targetX = shipPos.x + size.width / 2 - screen.width / 2
        let targetY = shipPos.y + size.height / 2 - screen.height / 2
        cameraX += wrapDelta(targetX, cameraX, worldW) * cameraLerp
        cameraY += wrapDelta(targetY, cameraY, worldH) * cameraLerp
    }

    // MARK: - Helpers

    private func isVisible(_ wx: CGFloat, _ wy: CGFloat, _ w: CGFloat, _ h: CGFloat) -> Bool {
        let screen = savedScreen
        let sp = worldToScreen(wx, wy)
        return sp.x + w > screen.minX - 50 && sp.x < screen.maxX + 50
            && sp.y + h > screen.minY - 50 && sp.y < screen.maxY + 50
    }

    private func updateVisuals(screen: CGRect, size: CGSize, axWindow: AXUIElement, now: UInt64) {
        let shipScreen = worldToScreen(shipPos.x, shipPos.y)
        if !movePip(to: shipScreen) { return }

        let bounds = CGRect(origin: shipScreen, size: size)

        withTransaction {
            // Thrust emitter
            if let te = thrustEmitter {
                let shipCX = shipPos.x + size.width / 2
                let shipCY = shipPos.y + size.height / 2
                if let mp = mousePosition() {
                    let mouseWorld = screenToWorld(mp.x, mp.y)
                    let dx = mouseWorld.x - shipCX
                    let dy = mouseWorld.y - shipCY
                    let dist = sqrt(dx * dx + dy * dy)
                    if dist > 5 {
                        let nx = dx / dist
                        let ny = dy / dist
                        let twx = shipCX - nx * (size.width / 2 + 10)
                        let twy = shipCY - ny * (size.height / 2 + 10)
                        let ts = worldToScreen(twx, twy)
                        te.emitterPosition = CGPoint(x: ts.x - screen.minX, y: screenH - ts.y)
                        let emitAngle = atan2(-(screenH - ts.y - (screenH - shipScreen.y - size.height / 2)),
                                              -(ts.x - screen.minX - (shipScreen.x - screen.minX + size.width / 2)))
                        for cell in te.emitterCells ?? [] {
                            cell.emissionLongitude = emitAngle
                        }
                        te.birthRate = 1
                    } else {
                        te.birthRate = 0
                    }
                }
            }

            // Asteroids
            for a in asteroidList {
                let ds = Sprites.displaySize(for: a.size)
                if isVisible(a.x, a.y, ds.width, ds.height) {
                    let sp = worldToScreen(a.x, a.y)
                    a.layer.frame = CGRect(x: sp.x - screen.minX, y: screenH - sp.y - ds.height, width: ds.width, height: ds.height)
                    a.layer.transform = CATransform3DMakeRotation(a.rotation, 0, 0, 1)
                    a.layer.isHidden = false
                } else {
                    a.layer.isHidden = true
                }
            }

            // Bullets
            for b in bullets {
                if isVisible(b.x, b.y, 4, 10) {
                    let sp = worldToScreen(b.x, b.y)
                    b.layer.position = CGPoint(x: sp.x - screen.minX + 2, y: screenH - sp.y - 5)
                    b.layer.isHidden = false
                } else {
                    b.layer.isHidden = true
                }
            }

            // Border
            if settings.glow, let border = borderRef {
                if invulnerable {
                    let ticks = secondsToMach(Double(invulnerableDuration))
                    let elapsed = machToSeconds(now - (invulnerableEndMach - ticks))
                    let blinkOn = Int(elapsed * blinkFrequency) % 2 == 0
                    if blinkOn {
                        border.show(around: bounds)
                    } else {
                        border.hide()
                    }
                } else {
                    border.show(around: bounds)
                }
            }
            lastBounds = bounds
        }
    }

    private func spawnBullet(x: CGFloat, y: CGFloat, vx: CGFloat, vy: CGFloat, spawnTime: UInt64) {
        guard let rootLayer = overlayLayer else { return }

        let layer = layerPool.dequeue()
        layer.bounds = CGRect(x: 0, y: 0, width: 6, height: 18)
        layer.contents = Sprites.bullet
        layer.magnificationFilter = .nearest
        layer.minificationFilter = .nearest

        // Rotate bolt to face direction of travel
        let angle = atan2(vy, vx) - .pi / 2
        layer.transform = CATransform3DMakeRotation(angle, 0, 0, 1)

        rootLayer.addSublayer(layer)
        bullets.append(Bullet(layer: layer, x: x, y: y, vx: vx, vy: vy, spawnMach: spawnTime))
    }

    private func splitAsteroid(_ a: Asteroid) -> [Asteroid] {
        guard let rootLayer = overlayLayer else { return [] }

        let nextSize: AsteroidSize?
        switch a.size {
        case .large:  nextSize = .medium
        case .medium: nextSize = .small
        case .small:  nextSize = nil
        }

        guard let ns = nextSize else { return [] }

        let displaySize = Sprites.displaySize(for: ns)
        let variants = Sprites.variants(for: ns)

        var result: [Asteroid] = []
        for _ in 0..<2 {
            let speedMult: CGFloat = 1.4
            let baseVx = a.vx * speedMult
            let baseVy = a.vy * speedMult
            let jitterAngle = CGFloat.random(in: -0.8...0.8)
            let cos_a = cos(jitterAngle)
            let sin_a = sin(jitterAngle)
            let nvx = baseVx * cos_a - baseVy * sin_a
            let nvy = baseVx * sin_a + baseVy * cos_a

            let layer = layerPool.dequeue()
            layer.bounds = CGRect(origin: .zero, size: displaySize)
            if !variants.isEmpty {
                layer.contents = variants.randomElement()!
            }
            layer.magnificationFilter = .nearest
            layer.minificationFilter = .nearest

            let rotSpeed = CGFloat.random(in: -2...2)
            rootLayer.addSublayer(layer)
            result.append(Asteroid(layer: layer, x: a.x, y: a.y, vx: nvx, vy: nvy,
                                   size: ns, rotation: 0, rotationSpeed: rotSpeed))
        }
        return result
    }
}
