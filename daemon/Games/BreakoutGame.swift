import Cocoa
import ApplicationServices



class BreakoutGame: GameBase {

    // Ball physics
    private var ballPos = CGPoint.zero
    private var velocity = CGPoint.zero
    private let baseSpeed: CGFloat = 350.0
    private let maxSpeed: CGFloat = 700.0
    private var launched = false

    // Paddle
    private var paddleWindow: NSWindow?
    private let basePaddleW: CGFloat = 120
    private var paddleW: CGFloat = 120
    private let paddleH: CGFloat = 12
    private let paddleBottomMargin: CGFloat = 60
    private var paddleX: CGFloat = 0

    // Bricks
    private let brickCols = 10
    private let brickRows = 5
    private let brickW: CGFloat = 60
    private let brickH: CGFloat = 21
    private let brickSpacingX: CGFloat = 4
    private let brickSpacingY: CGFloat = 4
    private let brickTopMargin: CGFloat = 40

    private struct Brick {
        let layer: CALayer
        var alive: Bool
        let row: Int
        var hitsRemaining: Int
    }
    private var bricks: [Brick] = []
    private var aliveBrickCount = 0

    // Overlay for bricks
    private var overlayWindow: NSWindow?
    private var overlayLayer: CALayer?

    // Particle emitter for brick destruction
    private var emitterLayer: CAEmitterLayer?

    // Lives, level
    private var lives = 3
    private var level = 0
    private var extraLifeGiven500 = false
    private var extraLifeGiven1500 = false

    // Input
    private var wasMouseDown = false

    // Row scores (top to bottom)
    private let rowScores = [50, 40, 30, 20, 10]

    // Row colors (bottom to top): dark muted terminal aesthetic
    private let rowColors: [(bg: NSColor, border: NSColor)] = [
        (NSColor(red: 0.0, green: 0.35, blue: 0.15, alpha: 1),
         NSColor(red: 0.0, green: 0.50, blue: 0.25, alpha: 0.6)),
        (NSColor(red: 0.0, green: 0.30, blue: 0.30, alpha: 1),
         NSColor(red: 0.0, green: 0.45, blue: 0.45, alpha: 0.6)),
        (NSColor(red: 0.20, green: 0.22, blue: 0.30, alpha: 1),
         NSColor(red: 0.30, green: 0.33, blue: 0.45, alpha: 0.6)),
        (NSColor(red: 0.30, green: 0.10, blue: 0.30, alpha: 1),
         NSColor(red: 0.45, green: 0.18, blue: 0.45, alpha: 0.6)),
        (NSColor(red: 0.40, green: 0.05, blue: 0.10, alpha: 1),
         NSColor(red: 0.55, green: 0.12, blue: 0.18, alpha: 0.6)),
    ]

    // MARK: - Pixel Art Sprites (see BreakoutSprites.swift)

    // MARK: - GameBase Hooks

    override func onStart(screen: CGRect, pip: PipWindowInfo) {
        timerIntervalMs = 8
        lives = 3
        level = 0
        launched = false
        wasMouseDown = false
        bricks = []
        aliveBrickCount = 0
        extraLifeGiven500 = false
        extraLifeGiven1500 = false
        paddleW = basePaddleW

        // Place ball on paddle initially
        paddleX = screen.midX - paddleW / 2
        let paddleY = screen.maxY - paddleBottomMargin
        ballPos = CGPoint(x: paddleX + paddleW / 2 - cachedPipSize.width / 2,
                          y: paddleY - cachedPipSize.height)
        velocity = .zero

        if Thread.isMainThread {
            createOverlays(screen: screen)
        } else {
            DispatchQueue.main.sync { self.createOverlays(screen: screen) }
        }

        print("Breakout started")
    }

    override func onStop() {
        let pw = paddleWindow, ow = overlayWindow
        let cleanup = {
            pw?.orderOut(nil)
            ow?.orderOut(nil)
        }
        if Thread.isMainThread { cleanup() }
        else { DispatchQueue.main.async { cleanup() } }

        paddleWindow = nil
        overlayWindow = nil
        overlayLayer = nil
        bricks = []
        print("Breakout stopped")
    }

    // MARK: - Overlay Creation

    private func createOverlays(screen: CGRect) {
        // Full-screen overlay for bricks
        let (ow, rootLayer) = createFullscreenOverlay(screen: screen)
        overlayLayer = rootLayer
        buildBricks(rootLayer: rootLayer, screen: screen)

        // Shared emitter layer for brick destruction particles
        let emitter = CAEmitterLayer()
        emitter.frame = CGRect(origin: .zero, size: screen.size)
        emitter.emitterShape = .point
        emitter.renderMode = .additive
        emitter.birthRate = 0  // starts inactive
        rootLayer.addSublayer(emitter)
        emitterLayer = emitter

        overlayWindow = ow

        // Paddle window
        let paddleY = screen.maxY - paddleBottomMargin
        let pw = NSWindow(contentRect: NSRect(x: paddleX,
                                               y: screenH - paddleY - paddleH,
                                               width: paddleW, height: paddleH),
                          styleMask: .borderless, backing: .buffered, defer: false)
        pw.isOpaque = false
        pw.backgroundColor = .clear
        pw.level = .floating
        pw.ignoresMouseEvents = true
        pw.hasShadow = false
        pw.collectionBehavior = [.canJoinAllSpaces, .stationary, .transient, .ignoresCycle]
        pw.contentView!.wantsLayer = true
        let paddleLayer = pw.contentView!.layer!
        paddleLayer.contents = BreakoutSprites.paddle
        paddleLayer.magnificationFilter = .nearest
        paddleLayer.minificationFilter = .nearest

        pw.orderFrontRegardless()
        paddleWindow = pw

        // Score overlay
        createScoreOverlay(screen: screen, width: 180)
        scoreLabel?.attributedStringValue = Self.styledScore(formatScore())
    }

    private func buildBricks(rootLayer: CALayer, screen: CGRect) {
        for brick in bricks {
            brick.layer.removeFromSuperlayer()
        }
        bricks = []
        aliveBrickCount = 0

        let totalGridW = CGFloat(brickCols) * brickW + CGFloat(brickCols - 1) * brickSpacingX
        let gridOriginX = (screen.width - totalGridW) / 2

        for row in 0..<brickRows {
            for col in 0..<brickCols {
                let layer = CALayer()
                let bx = gridOriginX + CGFloat(col) * (brickW + brickSpacingX)
                let by = brickTopMargin + CGFloat(row) * (brickH + brickSpacingY)
                layer.frame = CGRect(x: bx, y: screenH - by - brickH, width: brickW, height: brickH)
                layer.contents = BreakoutSprites.brickImages[row].normal
                layer.magnificationFilter = .nearest
                layer.minificationFilter = .nearest
                rootLayer.addSublayer(layer)
                let hits = row < 2 ? 2 : 1
                bricks.append(Brick(layer: layer, alive: true, row: row, hitsRemaining: hits))
                aliveBrickCount += 1
            }
        }
    }

    // MARK: - Game Loop

    override func gameTick() {
        guard active, let _ = cachedAXWindow else { return }

        let screen = getScreenFrame()
        let dt = deltaTime()

        // Update PiP size each frame
        refreshPipSize()
        let size = cachedPipSize

        // End screen timeout
        if checkGameOverTimeout() { return }

        // --- Input ---
        guard let mousePos = mousePosition() else { return }
        let mouseDown = isMouseDown

        // Paddle follows mouse X
        paddleX = max(screen.minX, min(screen.maxX - paddleW, mousePos.x - paddleW / 2))
        let paddleY = screen.maxY - paddleBottomMargin

        let currentSpeed = baseSpeed * (1.0 + 0.1 * CGFloat(level))

        if !launched {
            ballPos = CGPoint(x: paddleX + paddleW / 2 - size.width / 2,
                              y: paddleY - size.height)

            if mouseDown && !wasMouseDown {
                launched = true
                let angle = CGFloat.random(in: -0.3...0.3)
                velocity = CGPoint(x: currentSpeed * sin(angle), y: -currentSpeed * cos(angle))
            }
            wasMouseDown = mouseDown
        } else {
            wasMouseDown = mouseDown

            // --- Ball physics ---
            ballPos.x += velocity.x * dt
            ballPos.y += velocity.y * dt

            // Top wall bounce
            if ballPos.y <= screen.minY {
                ballPos.y = screen.minY
                velocity.y = abs(velocity.y)
                perturbAngle()
            }

            // Left wall bounce
            if ballPos.x <= screen.minX {
                ballPos.x = screen.minX
                velocity.x = abs(velocity.x)
                perturbAngle()
            }

            // Right wall bounce
            if ballPos.x + size.width >= screen.maxX {
                ballPos.x = screen.maxX - size.width
                velocity.x = -abs(velocity.x)
                perturbAngle()
            }

            // Paddle collision
            let ballBottom = ballPos.y + size.height
            let ballCenterX = ballPos.x + size.width / 2
            if ballBottom >= paddleY && ballBottom <= paddleY + paddleH + 8 && velocity.y > 0 {
                if ballCenterX >= paddleX && ballCenterX <= paddleX + paddleW {
                    ballPos.y = paddleY - size.height
                    let hitNorm = (ballCenterX - paddleX) / paddleW
                    let deflect = (hitNorm - 0.5) * 2.0
                    let spd = sqrt(velocity.x * velocity.x + velocity.y * velocity.y)
                    let newSpeed = min(spd * 1.02, maxSpeed)
                    let maxAngle: CGFloat = 1.2
                    let angle = deflect * maxAngle
                    velocity.x = newSpeed * sin(angle)
                    velocity.y = -newSpeed * cos(angle)
                    enforceMinVerticalSpeed()
                    flashPaddle()
                }
            }

            // Brick collisions
            let ballRect = CGRect(origin: ballPos, size: size)
            let totalGridW = CGFloat(brickCols) * brickW + CGFloat(brickCols - 1) * brickSpacingX
            let gridOriginX = (screen.width - totalGridW) / 2
            var firstHitBounced = false

            for i in 0..<bricks.count where bricks[i].alive {
                let row = i / brickCols
                let col = i % brickCols
                let bx = gridOriginX + CGFloat(col) * (brickW + brickSpacingX)
                let by = brickTopMargin + CGFloat(row) * (brickH + brickSpacingY)
                let brickRect = CGRect(x: bx, y: by, width: brickW, height: brickH)

                if Self.rectsCollide(ballRect, brickRect) {
                    bricks[i].hitsRemaining -= 1
                    score += rowScores[row]
                    checkExtraLife()

                    if bricks[i].hitsRemaining <= 0 {
                        bricks[i].alive = false
                        aliveBrickCount -= 1
                        animateBrickDeath(bricks[i].layer)
                    } else {
                        bricks[i].layer.contents = BreakoutSprites.brickImages[bricks[i].row].damaged
                    }

                    if !firstHitBounced {
                        firstHitBounced = true
                        let overlapLeft = ballRect.maxX - brickRect.minX
                        let overlapRight = brickRect.maxX - ballRect.minX
                        let overlapTop = ballRect.maxY - brickRect.minY
                        let overlapBottom = brickRect.maxY - ballRect.minY
                        let minOverlapX = min(overlapLeft, overlapRight)
                        let minOverlapY = min(overlapTop, overlapBottom)

                        if minOverlapX < minOverlapY {
                            velocity.x = -velocity.x
                        } else {
                            velocity.y = -velocity.y
                        }
                    }

                    if aliveBrickCount <= 0 {
                        advanceLevel()
                    }

                    scoreLabel?.attributedStringValue = Self.styledScore(formatScore())
                    popScoreLabel()
                }
            }

            // Ball falls below screen
            if ballPos.y > screen.maxY + 20 {
                lives -= 1
                if lives <= 0 {
                    triggerGameOver(message: "GAME OVER \(score)")
                    print("Breakout game over: score=\(score)")
                } else {
                    launched = false
                    ballPos = CGPoint(x: paddleX + paddleW / 2 - size.width / 2,
                                      y: paddleY - size.height)
                    velocity = .zero
                    scoreLabel?.attributedStringValue = Self.styledScore(formatScore())
                }
            }

            // Speed cap
            let spd = sqrt(velocity.x * velocity.x + velocity.y * velocity.y)
            if spd > maxSpeed {
                let s = maxSpeed / spd
                velocity.x *= s
                velocity.y *= s
            }
            enforceMinVerticalSpeed()
        }

        // --- Move PiP ---
        if !movePip(to: ballPos) { return }

        let bounds = CGRect(origin: ballPos, size: size)

        // --- Update visuals ---
        withTransaction {
            paddleWindow?.setFrame(
                NSRect(x: paddleX, y: screenH - paddleY - paddleH,
                       width: paddleW, height: paddleH), display: true)

            syncBorder(around: bounds)
        }
    }

    // MARK: - Helpers

    private func formatScore() -> String {
        let hearts = String(repeating: "\u{2665}", count: lives)
        if level > 0 {
            return "L\(level + 1) \(score) \(hearts)"
        }
        return "\(score)  \(hearts)"
    }

    private func enforceMinVerticalSpeed() {
        let spd = sqrt(velocity.x * velocity.x + velocity.y * velocity.y)
        guard spd > 0 else { return }
        let minVY = spd * 0.3
        if abs(velocity.y) < minVY {
            let sign: CGFloat = velocity.y >= 0 ? 1 : -1
            velocity.y = sign * minVY
            let newVX = sqrt(spd * spd - velocity.y * velocity.y)
            velocity.x = velocity.x >= 0 ? newVX : -newVX
        }
    }

    private func perturbAngle() {
        let perturbation = CGFloat.random(in: -0.05...0.05)
        let spd = sqrt(velocity.x * velocity.x + velocity.y * velocity.y)
        guard spd > 0 else { return }
        let angle = atan2(velocity.x, velocity.y) + perturbation
        velocity.x = spd * sin(angle)
        velocity.y = spd * cos(angle)
    }

    private func animateBrickDeath(_ layer: CALayer) {
        // Emit particles at brick center
        let brickColor: CGColor = rowColors[bricks.first(where: { $0.layer === layer })?.row ?? 0].bg.cgColor
        emitBrickParticles(at: layer.position, color: brickColor)

        let scaleAnim = CABasicAnimation(keyPath: "transform.scale")
        scaleAnim.fromValue = 1.0
        scaleAnim.toValue = 1.3
        scaleAnim.duration = 0.15

        let fadeAnim = CABasicAnimation(keyPath: "opacity")
        fadeAnim.fromValue = layer.opacity
        fadeAnim.toValue = 0.0
        fadeAnim.duration = 0.15

        let group = CAAnimationGroup()
        group.animations = [scaleAnim, fadeAnim]
        group.duration = 0.15
        group.isRemovedOnCompletion = false
        group.fillMode = .forwards

        CATransaction.begin()
        CATransaction.setCompletionBlock {
            layer.removeFromSuperlayer()
        }
        layer.add(group, forKey: "death")
        CATransaction.commit()
    }

    private func emitBrickParticles(at position: CGPoint, color: CGColor) {
        guard let emitter = emitterLayer else { return }

        let cell = CAEmitterCell()
        cell.birthRate = 80
        cell.lifetime = 0.5
        cell.velocity = 120
        cell.velocityRange = 60
        cell.emissionRange = .pi * 2
        cell.scale = 0.04
        cell.scaleRange = 0.02
        cell.color = color
        cell.alphaSpeed = -2.0
        cell.contents = {
            let size = CGSize(width: 8, height: 8)
            let image = NSImage(size: size)
            image.lockFocus()
            NSColor.white.setFill()
            NSBezierPath(ovalIn: CGRect(origin: .zero, size: size)).fill()
            image.unlockFocus()
            return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        }()

        emitter.emitterPosition = position
        emitter.emitterCells = [cell]
        emitter.birthRate = 1

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            emitter.birthRate = 0
        }
    }

    private func flashPaddle() {
        guard let layer = paddleWindow?.contentView?.layer else { return }
        let glowNS: NSColor
        switch settings.glowColor {
        case "blue": glowNS = NSColor(red: 0.2, green: 0.5, blue: 1.0, alpha: 1)
        case "red": glowNS = NSColor(red: 1.0, green: 0.2, blue: 0.2, alpha: 1)
        case "green": glowNS = NSColor(red: 0.1, green: 0.9, blue: 0.4, alpha: 1)
        case "purple": glowNS = NSColor(red: 0.7, green: 0.3, blue: 1.0, alpha: 1)
        default: glowNS = NSColor(red: 0.7, green: 0.3, blue: 1.0, alpha: 1)
        }
        let origContents = layer.contents
        layer.backgroundColor = glowNS.cgColor
        layer.contents = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            layer.backgroundColor = nil
            layer.contents = origContents
        }

        // Spring bounce on paddle hit
        let spring = CASpringAnimation(keyPath: "transform.scale")
        spring.fromValue = 1.05
        spring.toValue = 1.0
        spring.mass = 1.0
        spring.stiffness = 300
        spring.damping = 10
        spring.initialVelocity = 5
        spring.duration = spring.settlingDuration
        spring.isRemovedOnCompletion = true
        layer.add(spring, forKey: "paddleBounce")
    }

    private func popScoreLabel() {
        guard let layer = scoreLabel?.layer else { return }
        let anim = CABasicAnimation(keyPath: "transform.scale")
        anim.fromValue = 1.0
        anim.toValue = 1.1
        anim.duration = 0.075
        anim.autoreverses = true
        anim.isRemovedOnCompletion = true
        layer.add(anim, forKey: "pop")
    }

    private func checkExtraLife() {
        if !extraLifeGiven500 && score >= 500 && lives < 5 {
            extraLifeGiven500 = true
            lives += 1
            flashExtraLife()
        }
        if !extraLifeGiven1500 && score >= 1500 && lives < 5 {
            extraLifeGiven1500 = true
            lives += 1
            flashExtraLife()
        }
    }

    private func flashExtraLife() {
        scoreLabel?.attributedStringValue = Self.styledScore(formatScore())

        guard let layer = scoreLabel?.layer else { return }

        // Flash green background
        layer.backgroundColor = NSColor(red: 0.1, green: 0.9, blue: 0.3, alpha: 0.8).cgColor
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            layer.backgroundColor = nil
        }

        // Scale pop animation
        let anim = CABasicAnimation(keyPath: "transform.scale")
        anim.fromValue = 1.3
        anim.toValue = 1.0
        anim.duration = 0.3
        anim.timingFunction = CAMediaTimingFunction(name: .easeOut)
        anim.isRemovedOnCompletion = true
        layer.add(anim, forKey: "extraLifePop")
    }

    private func advanceLevel() {
        level += 1
        launched = false
        velocity = .zero

        paddleW = max(60, basePaddleW - CGFloat(level) * 15)

        if let rootLayer = overlayLayer {
            buildBricks(rootLayer: rootLayer, screen: getScreenFrame())
        }

        let screen = getScreenFrame()
        let paddleY = screen.maxY - paddleBottomMargin
        ballPos = CGPoint(x: paddleX + paddleW / 2 - cachedPipSize.width / 2,
                          y: paddleY - cachedPipSize.height)

        scoreLabel?.attributedStringValue = Self.styledScore(formatScore())
        print("Breakout level \(level + 1)")
    }
}
