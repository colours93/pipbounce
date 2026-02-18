import Cocoa
import ApplicationServices

let breakout = BreakoutGame()

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
    private var gameWon = false
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

    // MARK: - Pixel Art Sprites

    private enum Sprites {
        // Paddle: 40x4 metallic with green bumper dots, scale 3 → 120x12
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

    // MARK: - GameBase Hooks

    override func onStart(screen: CGRect, pip: PipWindowInfo) {
        timerIntervalMs = 8
        lives = 3
        level = 0
        gameWon = false
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
        paddleLayer.contents = Sprites.paddle
        paddleLayer.magnificationFilter = .nearest
        paddleLayer.minificationFilter = .nearest

        pw.orderFrontRegardless()
        paddleWindow = pw

        // Score overlay
        createScoreOverlay(screen: screen, width: 200)
        scoreLabel?.font = NSFont.monospacedSystemFont(ofSize: 20, weight: .bold)
        scoreLabel?.stringValue = formatScore()
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
                layer.contents = Sprites.brickImages[row].normal
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
        guard active, let axWindow = cachedAXWindow else { return }

        let screen = getScreenFrame()
        let dt = deltaTime()

        // Update PiP size each frame
        refreshPipSize()
        let size = cachedPipSize

        // End screen timeout
        if gameOver || gameWon {
            if checkGameOverTimeout() { return }
            // gameWon uses same timeout logic
            let now = mach_absolute_time()
            if machToSeconds(now - gameEndMach) > gameOverDelay { stop() }
            return
        }

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

                if ballRect.intersects(brickRect) {
                    bricks[i].hitsRemaining -= 1
                    score += rowScores[row]
                    checkExtraLife()

                    if bricks[i].hitsRemaining <= 0 {
                        bricks[i].alive = false
                        aliveBrickCount -= 1
                        animateBrickDeath(bricks[i].layer)
                    } else {
                        bricks[i].layer.contents = Sprites.brickImages[bricks[i].row].damaged
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

                    scoreLabel?.stringValue = formatScore()
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
                    scoreLabel?.stringValue = formatScore()
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
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        paddleWindow?.setFrame(
            NSRect(x: paddleX, y: screenH - paddleY - paddleH,
                   width: paddleW, height: paddleH), display: true)

        syncBorder(around: bounds)

        CATransaction.commit()
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
        }
        if !extraLifeGiven1500 && score >= 1500 && lives < 5 {
            extraLifeGiven1500 = true
            lives += 1
        }
    }

    private func advanceLevel() {
        level += 1
        launched = false
        velocity = .zero

        paddleW = max(80, basePaddleW - CGFloat(level) * 20)

        if let rootLayer = overlayLayer {
            buildBricks(rootLayer: rootLayer, screen: getScreenFrame())
        }

        let screen = getScreenFrame()
        let paddleY = screen.maxY - paddleBottomMargin
        ballPos = CGPoint(x: paddleX + paddleW / 2 - cachedPipSize.width / 2,
                          y: paddleY - cachedPipSize.height)

        scoreLabel?.stringValue = formatScore()
        print("Breakout level \(level + 1)")
    }
}
