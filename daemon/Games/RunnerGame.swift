import Cocoa
import ApplicationServices

let runner = RunnerGame()

class RunnerGame: GameBase {

    // MARK: - Pixel Art Sprites

    private enum Sprites {
        // 10x4 obstacle tiles per zone, rendered at scale 3 → 30x12, tiled vertically
        static let greyTile: CGImage? = GameBase.renderPixelArt([
            [0x6B6B6B, 0x7A7A7A, 0x888888, 0x6B6B6B, 0x7A7A7A, 0x6B6B6B, 0x888888, 0x7A7A7A, 0x6B6B6B, 0x7A7A7A],
            [0x7A7A7A, 0x555555, 0x6B6B6B, 0x888888, 0x555555, 0x7A7A7A, 0x6B6B6B, 0x555555, 0x888888, 0x6B6B6B],
            [0x888888, 0x6B6B6B, 0x4A4A4A, 0x7A7A7A, 0x6B6B6B, 0x888888, 0x4A4A4A, 0x7A7A7A, 0x6B6B6B, 0x888888],
            [0x6B6B6B, 0x7A7A7A, 0x6B6B6B, 0x555555, 0x888888, 0x6B6B6B, 0x7A7A7A, 0x6B6B6B, 0x555555, 0x7A7A7A],
        ], scale: 3)

        static let blueTile: CGImage? = GameBase.renderPixelArt([
            [0x3366AA, 0x4488CC, 0x55AAEE, 0x3366AA, 0xCCEEFF, 0x4488CC, 0x3366AA, 0x55AAEE, 0x4488CC, 0x3366AA],
            [0x4488CC, 0x224488, 0x3366AA, 0x55AAEE, 0x3366AA, 0x224488, 0x4488CC, 0xCCEEFF, 0x3366AA, 0x4488CC],
            [0x55AAEE, 0x3366AA, 0x4488CC, 0x224488, 0x4488CC, 0x55AAEE, 0x3366AA, 0x4488CC, 0x224488, 0x55AAEE],
            [0x3366AA, 0x4488CC, 0x224488, 0x3366AA, 0x55AAEE, 0x3366AA, 0x224488, 0x3366AA, 0x4488CC, 0x3366AA],
        ], scale: 3)

        static let purpleTile: CGImage? = GameBase.renderPixelArt([
            [0x7733AA, 0x8844BB, 0xCC66FF, 0x7733AA, 0x8844BB, 0x7733AA, 0xCC66FF, 0x8844BB, 0x7733AA, 0x8844BB],
            [0x8844BB, 0x552288, 0x7733AA, 0xCC66FF, 0x552288, 0x8844BB, 0x7733AA, 0x552288, 0xCC66FF, 0x7733AA],
            [0x7733AA, 0x8844BB, 0x552288, 0x8844BB, 0x7733AA, 0xCC66FF, 0x552288, 0x8844BB, 0x7733AA, 0xCC66FF],
            [0x552288, 0x7733AA, 0x8844BB, 0x7733AA, 0xCC66FF, 0x552288, 0x7733AA, 0x8844BB, 0x552288, 0x7733AA],
        ], scale: 3)

        static let brownTile: CGImage? = GameBase.renderPixelArt([
            [0x8B6534, 0x9E7744, 0xBB9955, 0x8B6534, 0x9E7744, 0x8B6534, 0xBB9955, 0x9E7744, 0x8B6534, 0x9E7744],
            [0x9E7744, 0x5C3D1A, 0x8B6534, 0xBB9955, 0x5C3D1A, 0x9E7744, 0x8B6534, 0x5C3D1A, 0xBB9955, 0x8B6534],
            [0x8B6534, 0x9E7744, 0x5C3D1A, 0x9E7744, 0x8B6534, 0xBB9955, 0x5C3D1A, 0x9E7744, 0x8B6534, 0xBB9955],
            [0x5C3D1A, 0x8B6534, 0x9E7744, 0x8B6534, 0xBB9955, 0x5C3D1A, 0x8B6534, 0x9E7744, 0x5C3D1A, 0x9E7744],
        ], scale: 3)

        static let forestTile: CGImage? = GameBase.renderPixelArt([
            [0x556B55, 0x667766, 0x778877, 0x556B55, 0x2D5C2D, 0x667766, 0x556B55, 0x778877, 0x667766, 0x556B55],
            [0x667766, 0x445544, 0x556B55, 0x2D5C2D, 0x667766, 0x445544, 0x667766, 0x2D5C2D, 0x556B55, 0x667766],
            [0x778877, 0x556B55, 0x445544, 0x667766, 0x556B55, 0x778877, 0x445544, 0x667766, 0x2D5C2D, 0x778877],
            [0x556B55, 0x2D5C2D, 0x667766, 0x556B55, 0x778877, 0x556B55, 0x2D5C2D, 0x556B55, 0x667766, 0x556B55],
        ], scale: 3)

        static let crimsonTile: CGImage? = GameBase.renderPixelArt([
            [0x8B2222, 0xAA3333, 0xFF4444, 0x8B2222, 0xAA3333, 0x8B2222, 0xFF4444, 0xAA3333, 0x8B2222, 0xAA3333],
            [0xAA3333, 0x551111, 0x8B2222, 0xFF4444, 0x551111, 0xAA3333, 0x8B2222, 0x551111, 0xFF4444, 0x8B2222],
            [0x8B2222, 0xAA3333, 0x551111, 0xAA3333, 0x8B2222, 0xFF4444, 0x551111, 0xAA3333, 0x8B2222, 0xFF4444],
            [0x551111, 0x8B2222, 0xAA3333, 0x8B2222, 0xFF4444, 0x551111, 0x8B2222, 0xAA3333, 0x551111, 0x8B2222],
        ], scale: 3)

        static func tileForZone(_ zone: Int) -> CGImage? {
            switch (zone - 1) % 6 {
            case 0: return greyTile
            case 1: return blueTile
            case 2: return purpleTile
            case 3: return brownTile
            case 4: return forestTile
            case 5: return crimsonTile
            default: return greyTile
            }
        }
    }

    private struct Obstacle {
        let topLayer: CALayer
        let bottomLayer: CALayer
        let gapTopIndicator: CALayer
        let gapBottomIndicator: CALayer
        let gapTopGlow: CALayer
        let gapBottomGlow: CALayer
        var x: CGFloat
        var gapY: CGFloat
        var gapHeight: CGFloat
        var scored: Bool
        // Moving gap
        let gapBaseY: CGFloat
        let gapAmplitude: CGFloat
        let gapFrequency: CGFloat
        var gapPhase: CGFloat
    }

    private var obstacles: [Obstacle] = []
    private let obstacleWidth: CGFloat = 30

    // Speed
    private var scrollSpeed: CGFloat = 200
    private let startSpeed: CGFloat = 200
    private let maxSpeed: CGFloat = 600

    // PiP position
    private var pipX: CGFloat = 0
    private var pipY: CGFloat = 0

    // Zone system
    private var zone = 1
    private var obstaclesPassed = 0
    private var zonePauseTimer: CGFloat = 0
    private var zoneFlashTimer: CGFloat = 0

    // Game over flash
    private var gameOverFlashTimer: CGFloat = 0

    // Overlay
    private var overlayWindow: NSWindow?
    private var overlayLayer: CALayer?

    // Particles
    private struct Particle {
        let layer: CALayer
        var x: CGFloat
        var y: CGFloat
        var vx: CGFloat
        var vy: CGFloat
        var life: CGFloat
    }
    private var particles: [Particle] = []

    private var gameTime: CGFloat = 0

    // MARK: - GameBase Hooks

    override func onStart(screen: CGRect, pip: PipWindowInfo) {
        timerIntervalMs = 8
        obstacles = []
        particles = []
        scrollSpeed = startSpeed
        zone = 1
        obstaclesPassed = 0
        zonePauseTimer = 0
        zoneFlashTimer = 0
        gameOverFlashTimer = 0
        gameTime = 0

        pipX = screen.minX + screen.width * 0.18
        pipY = screen.midY - cachedPipSize.height / 2

        if Thread.isMainThread {
            createOverlays(screen: screen)
        } else {
            DispatchQueue.main.sync { self.createOverlays(screen: screen) }
        }

        print("Runner started")
    }

    override func onStop() {
        overlayWindow?.orderOut(nil)
        overlayWindow = nil
        overlayLayer = nil
        obstacles = []
        particles = []
        print("Runner stopped")
    }

    // MARK: - Overlay Creation

    private func createOverlays(screen: CGRect) {
        let (ow, rootLayer) = createFullscreenOverlay(screen: screen)
        overlayLayer = rootLayer
        overlayWindow = ow

        createScoreOverlay(screen: screen)
    }

    // MARK: - Game Loop

    override func gameTick() {
        guard active, let _ = cachedAXWindow else { return }

        let screen = getScreenFrame()
        let now = mach_absolute_time()
        let dt = deltaTime()
        gameTime += dt

        // Refresh pip size periodically
        refreshPipSize()
        let size = cachedPipSize

        // Game over state
        if gameOver {
            gameOverFlashTimer -= dt
            if gameOverFlashTimer > 0 {
                overlayWindow?.backgroundColor = NSColor.red.withAlphaComponent(0.3)
            } else {
                overlayWindow?.backgroundColor = .clear
            }
            if checkGameOverTimeout() { return }
            return
        }

        // Zone pause
        if zonePauseTimer > 0 {
            zonePauseTimer -= dt
            zoneFlashTimer -= dt
            if zoneFlashTimer > 0 {
                scoreLabel?.stringValue = "ZONE \(zone)"
                scoreLabel?.textColor = NSColor.yellow
            } else {
                scoreLabel?.stringValue = "\(score)"
                scoreLabel?.textColor = .white
            }
            // Still move PiP during pause
            guard let mousePos = mousePosition() else { return }
            pipY = max(screen.minY, min(screen.maxY - size.height, mousePos.y - size.height / 2))
            movePip(to: CGPoint(x: pipX, y: pipY))
            let bounds = CGRect(origin: CGPoint(x: pipX, y: pipY), size: size)
            lastBounds = bounds
            syncBorder(around: bounds)
            updateParticles(dt: dt)
            return
        }

        // Input: mouse Y controls PiP Y
        guard let mousePos = mousePosition() else { return }
        pipY = max(screen.minY, min(screen.maxY - size.height, mousePos.y - size.height / 2))

        // Speed: step up per zone instead of linear
        let zoneSpeed = startSpeed + CGFloat(zone - 1) * 60
        scrollSpeed = min(zoneSpeed, maxSpeed)

        // Gap tightening based on score
        let minGapExtra: CGFloat = 30
        let maxGapExtra: CGFloat = 80
        let tightenProgress = min(CGFloat(score) / 30.0, 1.0)
        let currentGapExtra = maxGapExtra - (maxGapExtra - minGapExtra) * tightenProgress

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        // Move obstacles left and animate moving gaps
        for i in 0..<obstacles.count {
            obstacles[i].x -= scrollSpeed * dt
            // Moving gaps
            if obstacles[i].gapAmplitude > 0 {
                obstacles[i].gapPhase += obstacles[i].gapFrequency * dt
                let newGapY = obstacles[i].gapBaseY + obstacles[i].gapAmplitude * sin(obstacles[i].gapPhase)
                // Clamp to screen
                let clampedGapY = max(screen.minY + 30, min(screen.maxY - obstacles[i].gapHeight - 30, newGapY))
                obstacles[i].gapY = clampedGapY
            }
        }

        // Spawn new obstacles
        let spawnX = screen.maxX + 20
        let shouldSpawn: Bool
        if obstacles.isEmpty {
            shouldSpawn = true
        } else {
            let lastObs = obstacles.last!
            shouldSpawn = lastObs.x < screen.maxX - 300
        }

        if shouldSpawn {
            spawnObstacle(at: spawnX, screen: screen, pipSize: size, gapExtra: currentGapExtra)
        }

        // Remove off-screen obstacles
        obstacles.removeAll { obs in
            let offscreen = obs.x + obstacleWidth < screen.minX - 40
            if offscreen {
                obs.topLayer.removeFromSuperlayer()
                obs.bottomLayer.removeFromSuperlayer()
                obs.gapTopIndicator.removeFromSuperlayer()
                obs.gapBottomIndicator.removeFromSuperlayer()
                obs.gapTopGlow.removeFromSuperlayer()
                obs.gapBottomGlow.removeFromSuperlayer()
            }
            return offscreen
        }

        // Collision detection
        let pipRect = CGRect(x: pipX + 4, y: pipY + 4,
                             width: size.width - 8, height: size.height - 8)

        for obs in obstacles {
            let topRect = CGRect(x: obs.x, y: screen.minY,
                                 width: obstacleWidth, height: obs.gapY - screen.minY)
            let gapBottom = obs.gapY + obs.gapHeight
            let bottomRect = CGRect(x: obs.x, y: gapBottom,
                                    width: obstacleWidth, height: screen.maxY - gapBottom)

            if pipRect.intersects(topRect) || pipRect.intersects(bottomRect) {
                doTriggerGameOver(now: now)
                CATransaction.commit()
                return
            }
        }

        // Scoring: when PiP passes an obstacle
        for i in 0..<obstacles.count {
            if !obstacles[i].scored && obstacles[i].x + obstacleWidth < pipX {
                obstacles[i].scored = true
                score += 1
                obstaclesPassed += 1
                scoreLabel?.stringValue = "\(score)"

                // Near-miss particle burst
                let obs = obstacles[i]
                let gapBottom = obs.gapY + obs.gapHeight
                let topClearance = pipY - obs.gapY
                let bottomClearance = gapBottom - (pipY + size.height)
                if topClearance < 15 || bottomClearance < 15 {
                    emitNearMissParticles(obsX: obs.x, gapY: obs.gapY, gapBottom: gapBottom,
                                          topClose: topClearance < 15, bottomClose: bottomClearance < 15)
                }

                // Zone transition
                if obstaclesPassed % 10 == 0 {
                    zone += 1
                    zonePauseTimer = 0.5
                    zoneFlashTimer = 0.8
                    // Update existing obstacle tiles
                    let newTile = Sprites.tileForZone(zone)
                    for o in obstacles {
                        o.topLayer.contents = newTile
                        o.bottomLayer.contents = newTile
                    }
                }
            }
        }

        // Move PiP
        if !movePip(to: CGPoint(x: pipX, y: pipY)) {
            CATransaction.commit()
            return
        }

        // Update visuals
        let bounds = CGRect(origin: CGPoint(x: pipX, y: pipY), size: size)
        lastBounds = bounds

        for obs in obstacles {
            let gapBottom = obs.gapY + obs.gapHeight

            let topH = obs.gapY - screen.minY
            obs.topLayer.frame = CGRect(x: obs.x,
                                        y: screenH - screen.minY - topH,
                                        width: obstacleWidth, height: max(0, topH))

            let bottomH = screen.maxY - gapBottom
            obs.bottomLayer.frame = CGRect(x: obs.x,
                                           y: 0,
                                           width: obstacleWidth, height: max(0, bottomH))

            // Gap glow color based on gap tightness
            let gapRatio = obs.gapHeight / size.height
            let glowColor: CGColor
            if gapRatio > 1.3 {
                glowColor = NSColor(red: 0.0, green: 0.7, blue: 0.3, alpha: 0.25).cgColor
            } else if gapRatio > 1.1 {
                glowColor = NSColor(red: 0.9, green: 0.7, blue: 0.0, alpha: 0.25).cgColor
            } else {
                glowColor = NSColor(red: 0.9, green: 0.2, blue: 0.1, alpha: 0.25).cgColor
            }

            // Gap indicators (thin lines)
            let indicatorColor: CGColor
            if gapRatio > 1.3 {
                indicatorColor = NSColor(red: 0.0, green: 0.55, blue: 0.3, alpha: 0.5).cgColor
            } else if gapRatio > 1.1 {
                indicatorColor = NSColor(red: 0.9, green: 0.7, blue: 0.0, alpha: 0.5).cgColor
            } else {
                indicatorColor = NSColor(red: 0.9, green: 0.2, blue: 0.1, alpha: 0.5).cgColor
            }

            obs.gapTopIndicator.backgroundColor = indicatorColor
            obs.gapTopIndicator.frame = CGRect(x: obs.x - 2,
                                               y: screenH - obs.gapY - 2,
                                               width: obstacleWidth + 4, height: 2)
            obs.gapBottomIndicator.backgroundColor = indicatorColor
            obs.gapBottomIndicator.frame = CGRect(x: obs.x - 2,
                                                  y: screenH - gapBottom,
                                                  width: obstacleWidth + 4, height: 2)

            // Glow layers (wider, softer)
            obs.gapTopGlow.backgroundColor = glowColor
            obs.gapTopGlow.frame = CGRect(x: obs.x - 6,
                                          y: screenH - obs.gapY - 6,
                                          width: obstacleWidth + 12, height: 6)
            obs.gapBottomGlow.backgroundColor = glowColor
            obs.gapBottomGlow.frame = CGRect(x: obs.x - 6,
                                             y: screenH - gapBottom - 1,
                                             width: obstacleWidth + 12, height: 6)
        }

        // Update particles
        updateParticles(dt: dt)

        // Border sync
        syncBorder(around: bounds)

        CATransaction.commit()
    }

    // MARK: - Helpers

    private func spawnObstacle(at x: CGFloat, screen: CGRect, pipSize: CGSize, gapExtra: CGFloat) {
        guard let rootLayer = overlayLayer else { return }

        let gapHeight = pipSize.height + gapExtra
        let minGapY = screen.minY + 60
        let maxGapY = screen.maxY - gapHeight - 60
        let gapY = CGFloat.random(in: minGapY...max(minGapY, maxGapY))

        // ~30% of obstacles get moving gaps
        let isMoving = CGFloat.random(in: 0...1) < 0.3
        let amplitude: CGFloat = isMoving ? CGFloat.random(in: 30...70) : 0
        let frequency: CGFloat = isMoving ? CGFloat.random(in: 1.5...3.0) : 0

        let topLayer = CALayer()
        topLayer.contents = Sprites.tileForZone(zone)
        topLayer.magnificationFilter = .nearest
        topLayer.minificationFilter = .nearest
        topLayer.contentsGravity = .resize
        topLayer.cornerRadius = 3
        topLayer.masksToBounds = true
        rootLayer.addSublayer(topLayer)

        let bottomLayer = CALayer()
        bottomLayer.contents = Sprites.tileForZone(zone)
        bottomLayer.magnificationFilter = .nearest
        bottomLayer.minificationFilter = .nearest
        bottomLayer.contentsGravity = .resize
        bottomLayer.cornerRadius = 3
        bottomLayer.masksToBounds = true
        rootLayer.addSublayer(bottomLayer)

        let gapTopInd = CALayer()
        rootLayer.addSublayer(gapTopInd)

        let gapBottomInd = CALayer()
        rootLayer.addSublayer(gapBottomInd)

        let gapTopGlow = CALayer()
        gapTopGlow.cornerRadius = 3
        rootLayer.addSublayer(gapTopGlow)

        let gapBottomGlow = CALayer()
        gapBottomGlow.cornerRadius = 3
        rootLayer.addSublayer(gapBottomGlow)

        obstacles.append(Obstacle(
            topLayer: topLayer,
            bottomLayer: bottomLayer,
            gapTopIndicator: gapTopInd,
            gapBottomIndicator: gapBottomInd,
            gapTopGlow: gapTopGlow,
            gapBottomGlow: gapBottomGlow,
            x: x,
            gapY: gapY,
            gapHeight: gapHeight,
            scored: false,
            gapBaseY: gapY,
            gapAmplitude: amplitude,
            gapFrequency: frequency,
            gapPhase: 0
        ))
    }

    private func emitNearMissParticles(obsX: CGFloat, gapY: CGFloat, gapBottom: CGFloat,
                                        topClose: Bool, bottomClose: Bool) {
        guard let rootLayer = overlayLayer else { return }
        let colors: [CGColor] = [
            NSColor.yellow.cgColor, NSColor.cyan.cgColor,
            NSColor.green.cgColor, NSColor.white.cgColor,
            NSColor.orange.cgColor,
        ]

        let count = Int.random(in: 10...14)
        for _ in 0..<count {
            let fromTop = topClose && (!bottomClose || Bool.random())
            let py = fromTop ? gapY : gapBottom
            let layer = CALayer()
            let sz: CGFloat = CGFloat.random(in: 3...6)
            layer.frame = CGRect(x: obsX, y: screenH - py, width: sz, height: sz)
            layer.backgroundColor = colors.randomElement()!
            layer.cornerRadius = sz / 2
            rootLayer.addSublayer(layer)

            particles.append(Particle(
                layer: layer,
                x: obsX,
                y: screenH - py,
                vx: CGFloat.random(in: -120...120),
                vy: CGFloat.random(in: -120...120),
                life: 0.2
            ))
        }
    }

    private func updateParticles(dt: CGFloat) {
        guard !particles.isEmpty else { return }
        particles.removeAll { p in
            let dead = p.life <= 0
            if dead { p.layer.removeFromSuperlayer() }
            return dead
        }
        for i in 0..<particles.count {
            particles[i].life -= dt
            particles[i].x += particles[i].vx * dt
            particles[i].y += particles[i].vy * dt
            let alpha = max(0, particles[i].life / 0.35)
            particles[i].layer.opacity = Float(alpha)
            particles[i].layer.position = CGPoint(x: particles[i].x, y: particles[i].y)
        }
    }

    private func doTriggerGameOver(now: UInt64) {
        gameOverFlashTimer = 0.25
        triggerGameOver(message: "GAME OVER \(score)")
        scoreLabel?.font = NSFont.monospacedSystemFont(ofSize: 20, weight: .bold)

        // Shake score overlay
        if let sw = scoreOverlay {
            let origFrame = sw.frame
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
                sw.setFrame(origFrame.offsetBy(dx: 5, dy: 0), display: true)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                sw.setFrame(origFrame.offsetBy(dx: -5, dy: 0), display: true)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) {
                sw.setFrame(origFrame.offsetBy(dx: 3, dy: 0), display: true)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                sw.setFrame(origFrame, display: true)
            }
        }

        print("Runner game over: score=\(score)")
    }
}
