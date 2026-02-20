import Cocoa
import ApplicationServices



class RunnerGame: GameBase {

    // MARK: - Hell/Inferno Theme

    static func zoneName(_ zone: Int) -> String {
        switch zone {
        case 1: return "THE DESCENT"
        case 2: return "EMBER FIELDS"
        case 3: return "ASHEN DEPTHS"
        case 4: return "THE FURNACE"
        case 5: return "RIVER STYX"
        case 6: return "THE ABYSS"
        default: return "ZONE \(zone)"
        }
    }

    static func zoneColor(_ zone: Int) -> NSColor {
        switch zone {
        case 1: return NSColor(calibratedRed: 1.0, green: 0.45, blue: 0.1,  alpha: 1.0)
        case 2: return NSColor(calibratedRed: 1.0, green: 0.25, blue: 0.05, alpha: 1.0)
        case 3: return NSColor(calibratedRed: 0.9, green: 0.15, blue: 0.0,  alpha: 1.0)
        case 4: return NSColor(calibratedRed: 1.0, green: 0.6,  blue: 0.0,  alpha: 1.0)
        case 5: return NSColor(calibratedRed: 0.4, green: 0.0,  blue: 0.8,  alpha: 1.0)
        case 6: return NSColor(calibratedRed: 0.85, green: 0.0, blue: 0.15, alpha: 1.0)
        default: return NSColor(calibratedRed: 1.0, green: 0.45, blue: 0.1, alpha: 1.0)
        }
    }

    static func zoneOverlayColor(_ zone: Int) -> NSColor {
        switch zone {
        case 1: return NSColor(calibratedRed: 0.8, green: 0.2, blue: 0.0,  alpha: 0.018)
        case 2: return NSColor(calibratedRed: 0.9, green: 0.15, blue: 0.0, alpha: 0.025)
        case 3: return NSColor(calibratedRed: 1.0, green: 0.05, blue: 0.0, alpha: 0.030)
        case 4: return NSColor(calibratedRed: 1.0, green: 0.4,  blue: 0.0, alpha: 0.035)
        case 5: return NSColor(calibratedRed: 0.3, green: 0.0,  blue: 0.6, alpha: 0.030)
        case 6: return NSColor(calibratedRed: 0.7, green: 0.0,  blue: 0.1, alpha: 0.045)
        default: return .clear
        }
    }

    // Pre-built ember palette for near-miss particles (avoids rebuilding every call)
    private static let nearMissEmberPalette: [CGColor] = {
        let palette: [(CGColor, Int)] = [
            (NSColor(red: 1.00, green: 0.13, blue: 0.00, alpha: 1).cgColor, 4),
            (NSColor(red: 1.00, green: 0.40, blue: 0.00, alpha: 1).cgColor, 5),
            (NSColor(red: 1.00, green: 0.67, blue: 0.00, alpha: 1).cgColor, 4),
            (NSColor(red: 1.00, green: 0.87, blue: 0.30, alpha: 1).cgColor, 3),
            (NSColor(red: 1.00, green: 0.95, blue: 0.80, alpha: 1).cgColor, 2),
            (NSColor(red: 1.00, green: 1.00, blue: 1.00, alpha: 1).cgColor, 1),
        ]
        var flat: [CGColor] = []
        for (color, weight) in palette {
            for _ in 0..<weight { flat.append(color) }
        }
        return flat
    }()

    // MARK: - Pixel Art Sprites (see RunnerSprites.swift)

    private struct Obstacle {
        let topLayer: CALayer
        let bottomLayer: CALayer
        let topCapLayer: CALayer
        let bottomCapLayer: CALayer
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
    private let obstacleBodyWidth: CGFloat = 48   // 16px * scale 3
    private let obstacleCapWidth: CGFloat = 54    // 18px * scale 3
    private let obstacleCapHeight: CGFloat = 18   // 6px * scale 3

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
        var maxLife: CGFloat
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
        // Set initial zone atmosphere
        ow.backgroundColor = RunnerGame.zoneOverlayColor(zone)

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

        // Game over state — multi-phase hellfire flash
        if gameOver {
            gameOverFlashTimer -= dt
            if gameOverFlashTimer > 0 {
                // Phase 1 (0.68–0.76s remaining): white-hot impact flash
                if gameOverFlashTimer > 0.68 {
                    let t = (gameOverFlashTimer - 0.68) / 0.08
                    let alpha = 0.55 * t
                    overlayWindow?.backgroundColor = NSColor.white.withAlphaComponent(alpha)
                }
                // Phase 2 (0.50–0.68s remaining): blood red flash
                else if gameOverFlashTimer > 0.50 {
                    let t = (gameOverFlashTimer - 0.50) / 0.18
                    let alpha = 0.35 * t + 0.05
                    overlayWindow?.backgroundColor = NSColor(red: 0.9, green: 0.05, blue: 0.0, alpha: alpha)
                }
                // Phase 3 (0.0–0.50s remaining): deep crimson smolder
                else {
                    let t = gameOverFlashTimer / 0.50
                    let alpha = 0.22 * t
                    overlayWindow?.backgroundColor = NSColor(red: 0.6, green: 0.02, blue: 0.0, alpha: alpha)
                }
            } else {
                overlayWindow?.backgroundColor = .clear
            }
            updateParticles(dt: dt)
            if checkGameOverTimeout() { return }
            return
        }

        // Zone pause
        if zonePauseTimer > 0 {
            zonePauseTimer -= dt
            zoneFlashTimer -= dt
            if zoneFlashTimer > 0 {
                let name = RunnerGame.zoneName(zone)
                let color = RunnerGame.zoneColor(zone)
                let pStyle = NSMutableParagraphStyle()
                pStyle.alignment = .center
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.monospacedSystemFont(ofSize: 16, weight: .heavy),
                    .foregroundColor: color,
                    .kern: NSNumber(value: 3.0),
                    .paragraphStyle: pStyle,
                    .shadow: {
                        let s = NSShadow()
                        s.shadowColor = color.withAlphaComponent(0.9)
                        s.shadowBlurRadius = 12
                        s.shadowOffset = .zero
                        return s
                    }()
                ]
                scoreLabel?.attributedStringValue = NSAttributedString(string: name, attributes: attrs)
            } else {
                scoreLabel?.attributedStringValue = Self.styledScore("\(score)")
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

        // Move obstacles left and animate moving gaps
        for i in 0..<obstacles.count {
            obstacles[i].x -= scrollSpeed * dt
            if obstacles[i].gapAmplitude > 0 {
                obstacles[i].gapPhase += obstacles[i].gapFrequency * dt
                let newGapY = obstacles[i].gapBaseY + obstacles[i].gapAmplitude * sin(obstacles[i].gapPhase)
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
            let offscreen = obs.x + obstacleCapWidth < screen.minX - 40
            if offscreen {
                obs.topLayer.removeFromSuperlayer()
                obs.bottomLayer.removeFromSuperlayer()
                obs.topCapLayer.removeFromSuperlayer()
                obs.bottomCapLayer.removeFromSuperlayer()
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
        let capExtra = (obstacleCapWidth - obstacleBodyWidth) / 2

        for obs in obstacles {
            let topRect = CGRect(x: obs.x, y: screen.minY,
                                 width: obstacleBodyWidth, height: obs.gapY - screen.minY)
            let gapBottom = obs.gapY + obs.gapHeight
            let bottomRect = CGRect(x: obs.x, y: gapBottom,
                                    width: obstacleBodyWidth, height: screen.maxY - gapBottom)
            let topCapRect = CGRect(x: obs.x - capExtra, y: obs.gapY - obstacleCapHeight,
                                    width: obstacleCapWidth, height: obstacleCapHeight)
            let bottomCapRect = CGRect(x: obs.x - capExtra, y: gapBottom,
                                       width: obstacleCapWidth, height: obstacleCapHeight)

            if Self.rectsCollide(pipRect, topRect) || Self.rectsCollide(pipRect, bottomRect) ||
               Self.rectsCollide(pipRect, topCapRect) || Self.rectsCollide(pipRect, bottomCapRect) {
                doTriggerGameOver(now: now)
                return
            }
        }

        // Scoring
        for i in 0..<obstacles.count {
            if !obstacles[i].scored && obstacles[i].x + obstacleBodyWidth < pipX {
                obstacles[i].scored = true
                score += 1
                obstaclesPassed += 1
                scoreLabel?.attributedStringValue = Self.styledScore("\(score)")

                // Near-miss ember burst
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
                    // Update existing obstacle tiles and caps
                    let newTile = RunnerSprites.tileForZone(zone)
                    let newCap = RunnerSprites.capForZone(zone)
                    for o in obstacles {
                        o.topLayer.contents = newTile
                        o.bottomLayer.contents = newTile
                        o.topCapLayer.contents = newCap
                        o.bottomCapLayer.contents = newCap
                    }
                    // Update atmosphere
                    overlayWindow?.backgroundColor = RunnerGame.zoneOverlayColor(zone)
                }
            }
        }

        // Move PiP
        if !movePip(to: CGPoint(x: pipX, y: pipY)) { return }

        // Update visuals
        let bounds = CGRect(origin: CGPoint(x: pipX, y: pipY), size: size)
        lastBounds = bounds

        withTransaction {
            for obs in obstacles {
                let gapBottom = obs.gapY + obs.gapHeight
                let capExtra = (obstacleCapWidth - obstacleBodyWidth) / 2

                // Top body
                let topBodyH = max(0, obs.gapY - obstacleCapHeight - screen.minY)
                obs.topLayer.frame = CGRect(x: obs.x,
                                            y: screenH - screen.minY - topBodyH,
                                            width: obstacleBodyWidth, height: topBodyH)

                // Top cap
                obs.topCapLayer.frame = CGRect(x: obs.x - capExtra,
                                               y: screenH - obs.gapY,
                                               width: obstacleCapWidth, height: obstacleCapHeight)

                // Bottom body
                let bottomBodyH = max(0, screen.maxY - gapBottom - obstacleCapHeight)
                obs.bottomLayer.frame = CGRect(x: obs.x,
                                               y: 0,
                                               width: obstacleBodyWidth, height: bottomBodyH)

                // Bottom cap
                obs.bottomCapLayer.frame = CGRect(x: obs.x - capExtra,
                                                  y: screenH - gapBottom - obstacleCapHeight,
                                                  width: obstacleCapWidth, height: obstacleCapHeight)

                // Hellish gap glow colors
                let gapRatio = obs.gapHeight / size.height
                let glowColor: CGColor
                if gapRatio > 1.3 {
                    glowColor = NSColor(red: 0.80, green: 0.28, blue: 0.00, alpha: 0.18).cgColor
                } else if gapRatio > 1.1 {
                    glowColor = NSColor(red: 1.00, green: 0.50, blue: 0.00, alpha: 0.30).cgColor
                } else {
                    glowColor = NSColor(red: 1.00, green: 0.15, blue: 0.00, alpha: 0.40).cgColor
                }

                let indicatorColor: CGColor
                if gapRatio > 1.3 {
                    indicatorColor = NSColor(red: 0.85, green: 0.35, blue: 0.00, alpha: 0.45).cgColor
                } else if gapRatio > 1.1 {
                    indicatorColor = NSColor(red: 1.00, green: 0.65, blue: 0.05, alpha: 0.70).cgColor
                } else {
                    indicatorColor = NSColor(red: 1.00, green: 0.92, blue: 0.70, alpha: 0.90).cgColor
                }

                obs.gapTopIndicator.backgroundColor = indicatorColor
                obs.gapTopIndicator.frame = CGRect(x: obs.x - capExtra - 2,
                                                   y: screenH - obs.gapY,
                                                   width: obstacleCapWidth + 4, height: 2)
                obs.gapBottomIndicator.backgroundColor = indicatorColor
                obs.gapBottomIndicator.frame = CGRect(x: obs.x - capExtra - 2,
                                                      y: screenH - gapBottom - 2,
                                                      width: obstacleCapWidth + 4, height: 2)

                obs.gapTopGlow.backgroundColor = glowColor
                obs.gapTopGlow.frame = CGRect(x: obs.x - capExtra - 6,
                                              y: screenH - obs.gapY - 6,
                                              width: obstacleCapWidth + 12, height: 6)
                obs.gapBottomGlow.backgroundColor = glowColor
                obs.gapBottomGlow.frame = CGRect(x: obs.x - capExtra - 6,
                                                 y: screenH - gapBottom,
                                                 width: obstacleCapWidth + 12, height: 6)

                // Ambient flame particles from obstacle edges
                emitAmbientFlames(obsX: obs.x, gapY: obs.gapY, gapBottom: gapBottom)
            }

            // Update particles
            updateParticles(dt: dt)

            // Border sync
            syncBorder(around: bounds)
        }
    }

    // MARK: - Helpers

    private func spawnObstacle(at x: CGFloat, screen: CGRect, pipSize: CGSize, gapExtra: CGFloat) {
        guard let rootLayer = overlayLayer else { return }

        let gapHeight = pipSize.height + gapExtra
        let minGapY = screen.minY + 60
        let maxGapY = screen.maxY - gapHeight - 60
        let gapY = CGFloat.random(in: minGapY...max(minGapY, maxGapY))

        let isMoving = CGFloat.random(in: 0...1) < 0.3
        let amplitude: CGFloat = isMoving ? CGFloat.random(in: 30...70) : 0
        let frequency: CGFloat = isMoving ? CGFloat.random(in: 1.5...3.0) : 0

        let topLayer = CALayer()
        topLayer.contents = RunnerSprites.tileForZone(zone)
        topLayer.magnificationFilter = .nearest
        topLayer.minificationFilter = .nearest
        topLayer.contentsGravity = .resizeAspect
        topLayer.cornerRadius = 3
        topLayer.masksToBounds = true
        rootLayer.addSublayer(topLayer)

        let bottomLayer = CALayer()
        bottomLayer.contents = RunnerSprites.tileForZone(zone)
        bottomLayer.magnificationFilter = .nearest
        bottomLayer.minificationFilter = .nearest
        bottomLayer.contentsGravity = .resizeAspect
        bottomLayer.cornerRadius = 3
        bottomLayer.masksToBounds = true
        rootLayer.addSublayer(bottomLayer)

        let topCapLayer = CALayer()
        topCapLayer.contents = RunnerSprites.capForZone(zone)
        topCapLayer.magnificationFilter = .nearest
        topCapLayer.minificationFilter = .nearest
        topCapLayer.contentsGravity = .resize
        rootLayer.addSublayer(topCapLayer)

        let bottomCapLayer = CALayer()
        bottomCapLayer.contents = RunnerSprites.capForZone(zone)
        bottomCapLayer.magnificationFilter = .nearest
        bottomCapLayer.minificationFilter = .nearest
        bottomCapLayer.contentsGravity = .resize
        bottomCapLayer.transform = CATransform3DMakeScale(1, -1, 1)
        rootLayer.addSublayer(bottomCapLayer)

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
            topCapLayer: topCapLayer,
            bottomCapLayer: bottomCapLayer,
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

    // MARK: - Ember Burst (near-miss)

    private func emitNearMissParticles(obsX: CGFloat, gapY: CGFloat, gapBottom: CGFloat,
                                        topClose: Bool, bottomClose: Bool) {
        guard let rootLayer = overlayLayer else { return }

        // Hell ember palette — weighted toward orange/red, rare white-hot sparks
        let flatPalette = Self.nearMissEmberPalette

        let count = Int.random(in: 18...26)
        for _ in 0..<count {
            let fromTop = topClose && (!bottomClose || Bool.random())
            let px = obsX + CGFloat.random(in: -4...obstacleCapWidth)
            let py = fromTop ? gapY : gapBottom

            let isBigEmber = CGFloat.random(in: 0...1) < 0.25
            let sz: CGFloat = isBigEmber ? CGFloat.random(in: 5...9) : CGFloat.random(in: 1.5...4)

            let layer = layerPool.dequeue()
            layer.frame = CGRect(x: 0, y: 0, width: sz, height: sz)
            layer.cornerRadius = isBigEmber ? sz * 0.35 : sz / 2
            layer.backgroundColor = flatPalette.randomElement()!
            if isBigEmber {
                layer.shadowColor = NSColor(red: 1, green: 0.4, blue: 0, alpha: 1).cgColor
                layer.shadowOpacity = 0.9
                layer.shadowRadius = 4
                layer.shadowOffset = .zero
            }
            rootLayer.addSublayer(layer)

            let baseVX = CGFloat.random(in: -180...60)
            let baseVY: CGFloat = fromTop
                ? CGFloat.random(in: -80...140)
                : CGFloat.random(in: 60...200)
            let speedMult: CGFloat = isBigEmber ? 0.65 : 1.0
            let life: CGFloat = isBigEmber
                ? CGFloat.random(in: 0.35...0.60)
                : CGFloat.random(in: 0.18...0.38)
            let layerY = screenH - py + CGFloat.random(in: -3...3)

            particles.append(Particle(
                layer: layer, x: px, y: layerY,
                vx: baseVX * speedMult, vy: baseVY * speedMult,
                life: life, maxLife: life
            ))
            layer.position = CGPoint(x: px, y: layerY)
        }
    }

    // MARK: - Ambient Flames (smoldering columns)

    private func emitAmbientFlames(obsX: CGFloat, gapY: CGFloat, gapBottom: CGFloat) {
        guard let rootLayer = overlayLayer else { return }
        guard CGFloat.random(in: 0...1) < 0.30 else { return }

        let count = Int.random(in: 1...2)
        let emitFromTop = Bool.random()

        for _ in 0..<count {
            let capExtra = (obstacleCapWidth - obstacleBodyWidth) / 2
            let px = (obsX - capExtra) + CGFloat.random(in: 0...obstacleCapWidth)
            let originY: CGFloat = emitFromTop ? gapY : gapBottom

            let sz: CGFloat = CGFloat.random(in: 1.0...3.0)

            let isBright = CGFloat.random(in: 0...1) < 0.15
            let emberColor: CGColor
            if isBright {
                emberColor = NSColor(red: 1.00, green: 0.65, blue: 0.10, alpha: 0.85).cgColor
            } else {
                let rVar = CGFloat.random(in: 0.75...0.95)
                let gVar = CGFloat.random(in: 0.15...0.35)
                emberColor = NSColor(red: rVar, green: gVar, blue: 0.00, alpha: 0.65).cgColor
            }

            let layer = layerPool.dequeue()
            layer.frame = CGRect(x: 0, y: 0, width: sz, height: sz)
            layer.cornerRadius = sz / 2
            layer.backgroundColor = emberColor
            rootLayer.addSublayer(layer)

            let vx = CGFloat.random(in: -18...18)
            let vy = CGFloat.random(in: 25...70)
            let life: CGFloat = CGFloat.random(in: 0.20...0.45)
            let layerY = screenH - originY

            particles.append(Particle(
                layer: layer, x: px, y: layerY,
                vx: vx, vy: vy,
                life: life, maxLife: life
            ))
            layer.position = CGPoint(x: px, y: layerY)
        }
    }

    // MARK: - Particle System

    private func updateParticles(dt: CGFloat) {
        guard !particles.isEmpty else { return }
        particles.removeAll { p in
            let dead = p.life <= 0
            if dead {
                layerPool.enqueue(p.layer)
                p.layer.removeFromSuperlayer()
            }
            return dead
        }
        for i in 0..<particles.count {
            particles[i].life -= dt
            particles[i].x += particles[i].vx * dt
            particles[i].y += particles[i].vy * dt
            particles[i].x += CGFloat.random(in: -0.4...0.4) // heat shimmer
            let alpha = max(0, particles[i].life / particles[i].maxLife)
            particles[i].layer.opacity = Float(alpha)
            particles[i].layer.position = CGPoint(x: particles[i].x, y: particles[i].y)
        }
    }

    // MARK: - Game Over

    private func doTriggerGameOver(now: UInt64) {
        gameOverFlashTimer = 0.76

        // Hell-themed game over messages
        let gameOverMessages = [
            "YOUR SOUL: \(score)",
            "CLAIMED: \(score)",
            "CONDEMNED: \(score)",
            "DEVOURED: \(score)",
        ]
        let message = gameOverMessages[score % gameOverMessages.count]
        triggerGameOver(message: message)

        // Style the score label with hellfire
        let goStyle = NSMutableParagraphStyle()
        goStyle.alignment = .center
        let gameOverAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 16, weight: .heavy),
            .foregroundColor: NSColor(calibratedRed: 0.85, green: 0.0, blue: 0.15, alpha: 1.0),
            .kern: NSNumber(value: 2.0),
            .paragraphStyle: goStyle,
            .shadow: {
                let s = NSShadow()
                s.shadowColor = NSColor(calibratedRed: 1.0, green: 0.1, blue: 0.0, alpha: 0.85)
                s.shadowBlurRadius = 14
                s.shadowOffset = .zero
                return s
            }()
        ]
        scoreLabel?.attributedStringValue = NSAttributedString(string: message, attributes: gameOverAttrs)

        // Death explosion
        emitDeathExplosion()

        // Violent shake
        if let sw = scoreOverlay {
            let origFrame = sw.frame
            let shakes: [(Double, CGFloat, CGFloat)] = [
                (0.02, -9, 4), (0.05, 8, -5), (0.08, -7, 3),
                (0.11, 6, -2), (0.14, -4, 2), (0.17, 3, -1),
                (0.20, -2, 0), (0.23, 0, 0),
            ]
            for (delay, dx, dy) in shakes {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    sw.setFrame(origFrame.offsetBy(dx: dx, dy: dy), display: true)
                }
            }
        }

        print("Runner game over: score=\(score)")
    }

    private func emitDeathExplosion() {
        guard let rootLayer = overlayLayer else { return }

        let palette: [CGColor] = [
            NSColor(red: 1.00, green: 1.00, blue: 1.00, alpha: 1).cgColor,
            NSColor(red: 1.00, green: 0.95, blue: 0.70, alpha: 1).cgColor,
            NSColor(red: 1.00, green: 0.65, blue: 0.05, alpha: 1).cgColor,
            NSColor(red: 1.00, green: 0.35, blue: 0.00, alpha: 1).cgColor,
            NSColor(red: 0.95, green: 0.10, blue: 0.00, alpha: 1).cgColor,
            NSColor(red: 0.60, green: 0.05, blue: 0.00, alpha: 1).cgColor,
        ]

        let originX = lastBounds.midX
        let originY = screenH - lastBounds.midY

        let count = Int.random(in: 40...55)
        for i in 0..<count {
            let isCoreSpark = i < 8

            let sz: CGFloat = isCoreSpark
                ? CGFloat.random(in: 2...4)
                : CGFloat.random(in: 1.5...8)

            let color = isCoreSpark ? palette[0] : palette.randomElement()!

            let layer = layerPool.dequeue()
            layer.frame = CGRect(x: 0, y: 0, width: sz, height: sz)
            layer.cornerRadius = sz * 0.4
            layer.backgroundColor = color
            if sz > 4 {
                layer.shadowColor = NSColor(red: 1, green: 0.3, blue: 0, alpha: 1).cgColor
                layer.shadowOpacity = 1.0
                layer.shadowRadius = 5
                layer.shadowOffset = .zero
            }
            rootLayer.addSublayer(layer)

            let angle = CGFloat.random(in: 0...(2 * .pi))
            let speed = isCoreSpark
                ? CGFloat.random(in: 40...120)
                : CGFloat.random(in: 80...320)
            let vx = cos(angle) * speed
            var vy = sin(angle) * speed
            vy += CGFloat.random(in: 30...90) // heat rises

            let life: CGFloat = CGFloat.random(in: 0.4...1.1)

            particles.append(Particle(
                layer: layer, x: originX, y: originY,
                vx: vx, vy: vy,
                life: life, maxLife: life
            ))
            layer.position = CGPoint(x: originX, y: originY)
        }
    }
}
