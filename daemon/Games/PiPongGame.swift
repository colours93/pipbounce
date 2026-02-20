import Cocoa
import ApplicationServices



/// PiPong — classic mode where the PiP window IS the ball.
/// Both paddles are overlay windows. Player controls left paddle with mouse Y.
class PiPongGame: GameBase {

    // Glow cycle colors: purple → cyan → green → purple
    private static let glowCycleColors: [CGColor] = [
        NSColor(red: 0.7, green: 0.2, blue: 1.0, alpha: 1).cgColor,
        NSColor(red: 0.3, green: 0.8, blue: 1.0, alpha: 1).cgColor,
        NSColor(red: 0.2, green: 1.0, blue: 0.6, alpha: 1).cgColor,
        NSColor(red: 0.7, green: 0.2, blue: 1.0, alpha: 1).cgColor,
    ]

    private var velocity = CGPoint.zero
    private let baseSpeed: CGFloat = 420.0
    private let maxSpeed: CGFloat = 900.0

    private var playerPaddle: NSWindow?
    private var aiPaddle: NSWindow?

    private let paddleWidth: CGFloat = 10
    private let paddleMargin: CGFloat = 20
    private var paddleHeight: CGFloat = 150

    private var playerScore = 0
    private var aiScore = 0
    private var playerY: CGFloat = 0
    private var aiY: CGFloat = 0
    private let aiSpeed: CGFloat = 300.0

    private var pauseUntil: UInt64 = 0
    private var scoreChanged = false

    // Ball position (= PiP position, in screen coords)
    private var ballPos = CGPoint.zero

    // AI reaction delay
    private var aiTargetY: CGFloat = 0
    private var aiTargetNoise: CGFloat = 0
    private var aiLastUpdateMach: UInt64 = 0
    private let aiReactionDelay: Double = 0.15

    // Match format: first to 7, win by 2
    private let winScore = 7
    private var matchOverUntil: UInt64 = 0
    private var matchOverMessage: String?

    // Rally timer for speed ramp
    private var rallyStartMach: UInt64 = 0
    private let speedRampDuration: CGFloat = 15.0

    // Galactic shooting star trail
    private var trailWindow: NSWindow?
    private struct Particle {
        var layer: CALayer
        var x: CGFloat
        var y: CGFloat
        var vx: CGFloat
        var vy: CGFloat
        var life: CGFloat      // 1.0 → 0.0
        var maxLife: CGFloat
        var size: CGFloat
        var hue: CGFloat       // for RGB cycling
        var twinkleRate: CGFloat
    }
    private var particles: [Particle] = []
    private let maxParticles = 80
    private var trailHue: CGFloat = 0

    // Screen shake
    private var shakeFramesRemaining = 0

    override func onStart(screen: CGRect, pip: PipWindowInfo) {
        timerIntervalMs = 8

        playerScore = 0
        aiScore = 0
        scoreChanged = false
        paddleHeight = screen.height * 0.15
        playerY = screen.midY - paddleHeight / 2
        aiY = screen.midY - paddleHeight / 2
        aiTargetY = aiY
        aiTargetNoise = 0
        aiLastUpdateMach = 0
        pauseUntil = 0
        matchOverUntil = 0
        matchOverMessage = nil
        rallyStartMach = mach_absolute_time()
        particles = []
        shakeFramesRemaining = 0

        // PiP IS the ball — start at center
        ballPos = CGPoint(x: screen.midX - cachedPipSize.width / 2,
                          y: screen.midY - cachedPipSize.height / 2)
        movePip(to: ballPos)

        launchBall(direction: Bool.random() ? 1 : -1)

        if Thread.isMainThread {
            createOverlays(screen: screen)
        } else {
            DispatchQueue.main.sync { self.createOverlays(screen: screen) }
        }

        print("PiPong started")
    }

    override func onStop() {
        let pp = playerPaddle, ap = aiPaddle, tw = trailWindow
        let cleanup = {
            pp?.orderOut(nil)
            ap?.orderOut(nil)
            tw?.orderOut(nil)
        }
        if Thread.isMainThread { cleanup() }
        else { DispatchQueue.main.async { cleanup() } }
        playerPaddle = nil
        aiPaddle = nil
        trailWindow = nil
        particles = []
        print("PiPong stopped")
    }

    override func gameTick() {
        guard active, let _ = cachedAXWindow else { return }

        refreshPipSize()

        guard let mousePos = mousePosition() else { return }
        let screen = getScreenFrame()

        let dt = deltaTime()
        let now = mach_absolute_time()

        // Player paddle tracks mouse Y
        playerY = max(screen.minY, min(screen.maxY - paddleHeight, mousePos.y - paddleHeight / 2))

        // Match over pause
        if matchOverUntil > 0 {
            if now < matchOverUntil {
                withTransaction {
                    updateOverlayPositions(screen: screen)
                    let pipBounds = CGRect(origin: ballPos, size: cachedPipSize)
                    syncBorder(around: pipBounds)
                }
                return
            }
            matchOverUntil = 0
            matchOverMessage = nil
            playerScore = 0
            aiScore = 0
            scoreChanged = true
        }

        // Pause after score
        if pauseUntil > 0 {
            withTransaction {
                updateOverlayPositions(screen: screen)
                let pipBounds = CGRect(origin: ballPos, size: cachedPipSize)
                syncBorder(around: pipBounds)
                if scoreChanged { updateScore(); scoreChanged = false }
            }
            if now < pauseUntil { return }
            pauseUntil = 0
            rallyStartMach = now
        }

        // Speed ramp
        let rallyTime = machToSeconds(now - rallyStartMach)
        let speedT = min(rallyTime / speedRampDuration, 1.0)
        let currentSpeed = baseSpeed + (maxSpeed - baseSpeed) * speedT

        // Normalize velocity to current speed
        let spd = sqrt(velocity.x * velocity.x + velocity.y * velocity.y)
        if spd > 0 {
            let s = currentSpeed / spd
            velocity.x *= s
            velocity.y *= s
        }

        // Ball physics (PiP moves)
        ballPos.x += velocity.x * dt
        ballPos.y += velocity.y * dt

        // Top/bottom bounce
        if ballPos.y <= screen.minY {
            ballPos.y = screen.minY
            velocity.y = abs(velocity.y)
        }
        if ballPos.y + cachedPipSize.height >= screen.maxY {
            ballPos.y = screen.maxY - cachedPipSize.height
            velocity.y = -abs(velocity.y)
        }

        // Clamp speed
        let spdAfter = sqrt(velocity.x * velocity.x + velocity.y * velocity.y)
        if spdAfter > maxSpeed {
            let s = maxSpeed / spdAfter
            velocity.x *= s
            velocity.y *= s
        }

        // AI with reaction delay and noise
        let ballCY = ballPos.y + cachedPipSize.height / 2
        let midX = screen.midX

        if velocity.x > 0 && ballPos.x + cachedPipSize.width > midX {
            if now - aiLastUpdateMach > secondsToMach(aiReactionDelay) {
                aiLastUpdateMach = now
                let noiseMag = aiNoiseAmount()
                aiTargetNoise = CGFloat.random(in: -noiseMag...noiseMag)
                aiTargetY = ballCY - paddleHeight / 2 + aiTargetNoise
            }
        } else if velocity.x < 0 {
            if now - aiLastUpdateMach > secondsToMach(aiReactionDelay) {
                aiLastUpdateMach = now
                aiTargetY = screen.midY - paddleHeight / 2
            }
        }

        let aiDiff = aiTargetY - aiY
        aiY += max(-aiSpeed * dt, min(aiSpeed * dt, aiDiff))
        aiY = max(screen.minY, min(screen.maxY - paddleHeight, aiY))

        let playerX = screen.minX + paddleMargin
        let aiX = screen.maxX - paddleMargin - paddleWidth

        // Player paddle collision
        let deflectScale = 150 + (currentSpeed / maxSpeed) * 100
        let playerRight = playerX + paddleWidth
        if ballPos.x <= playerRight && ballPos.x + cachedPipSize.width >= playerX && velocity.x < 0 {
            if ballCY >= playerY && ballCY <= playerY + paddleHeight {
                velocity.x = abs(velocity.x)
                let hit = (ballCY - playerY) / paddleHeight - 0.5
                velocity.y += hit * deflectScale
                let s2 = sqrt(velocity.x * velocity.x + velocity.y * velocity.y)
                if s2 > maxSpeed { let c = maxSpeed / s2; velocity.x *= c; velocity.y *= c }
                ballPos.x = playerRight
                flashPaddle(playerPaddle)
            }
        }

        // AI paddle collision
        if ballPos.x + cachedPipSize.width >= aiX && ballPos.x + cachedPipSize.width <= aiX + paddleWidth + cachedPipSize.width / 2 && velocity.x > 0 {
            if ballCY >= aiY && ballCY <= aiY + paddleHeight {
                velocity.x = -(abs(velocity.x))
                let hit = (ballCY - aiY) / paddleHeight - 0.5
                velocity.y += hit * deflectScale
                let s2 = sqrt(velocity.x * velocity.x + velocity.y * velocity.y)
                if s2 > maxSpeed { let c = maxSpeed / s2; velocity.x *= c; velocity.y *= c }
                ballPos.x = aiX - cachedPipSize.width
                flashPaddle(aiPaddle)
            }
        }

        // Scoring
        if ballPos.x + cachedPipSize.width < screen.minX - 30 {
            aiScore += 1
            scoreChanged = true
            ballPos = CGPoint(x: screen.midX - cachedPipSize.width / 2, y: screen.midY - cachedPipSize.height / 2)
            launchBall(direction: 1)
            triggerShake()
            if checkMatchOver() { return }
            pauseUntil = mach_absolute_time() + secondsToMach(0.8)
            rallyStartMach = 0
        }

        if ballPos.x > screen.maxX + 30 {
            playerScore += 1
            scoreChanged = true
            ballPos = CGPoint(x: screen.midX - cachedPipSize.width / 2, y: screen.midY - cachedPipSize.height / 2)
            launchBall(direction: -1)
            triggerShake()
            if checkMatchOver() { return }
            pauseUntil = mach_absolute_time() + secondsToMach(0.8)
            rallyStartMach = 0
        }

        // Move PiP (the ball)
        let shakeOff = applyShake()
        let movedPos = CGPoint(x: ballPos.x + shakeOff.x, y: ballPos.y + shakeOff.y)
        if !movePip(to: movedPos) { return }

        let pipBounds = CGRect(origin: movedPos, size: cachedPipSize)

        withTransaction {
            updateOverlayPositions(screen: screen, shakeOffset: shakeOff)
            syncBorder(around: pipBounds)
            updateTrail(shakeOffset: shakeOff, screen: screen, dt: dt)
            if scoreChanged { updateScore(); scoreChanged = false }
        }
    }

    // MARK: - AI Difficulty

    private func aiNoiseAmount() -> CGFloat {
        let diff = playerScore - aiScore
        if diff >= 3 { return 5 }
        else if diff <= -3 { return 40 }
        return 20
    }

    // MARK: - Match Logic

    private func checkMatchOver() -> Bool {
        let maxS = max(playerScore, aiScore)
        let minS = min(playerScore, aiScore)
        if maxS >= winScore && maxS - minS >= 2 {
            let msg = playerScore > aiScore ? "YOU WIN" : "AI WINS"
            matchOverMessage = msg
            scoreChanged = true
            updateScore()
            matchOverUntil = mach_absolute_time() + secondsToMach(1.5)
            pauseUntil = 0
            return true
        }
        return false
    }

    // MARK: - Hit Flash

    private func flashPaddle(_ paddle: NSWindow?) {
        guard let layer = paddle?.contentView?.layer else { return }
        let flash = CABasicAnimation(keyPath: "backgroundColor")
        flash.fromValue = layer.backgroundColor
        flash.toValue = NSColor.white.cgColor
        flash.duration = 0.15
        flash.autoreverses = true
        layer.add(flash, forKey: "hitFlash")
    }

    private func glowCGColor() -> CGColor {
        switch settings.glowColor {
        case "blue": return NSColor(red: 0.2, green: 0.5, blue: 1.0, alpha: 1).cgColor
        case "red": return NSColor(red: 1.0, green: 0.2, blue: 0.2, alpha: 1).cgColor
        case "green": return NSColor(red: 0.1, green: 0.9, blue: 0.4, alpha: 1).cgColor
        case "rainbow": return NSColor.cyan.cgColor
        default: return NSColor(red: 0.7, green: 0.3, blue: 1.0, alpha: 1).cgColor
        }
    }

    // MARK: - Screen Shake

    private func triggerShake() {
        shakeFramesRemaining = 5
    }

    private func applyShake() -> CGPoint {
        if shakeFramesRemaining > 0 {
            shakeFramesRemaining -= 1
            return CGPoint(x: CGFloat.random(in: -3...3), y: CGFloat.random(in: -3...3))
        }
        return .zero
    }

    // MARK: - Ball Trail

    private func updateTrail(shakeOffset: CGPoint, screen: CGRect, dt: CGFloat = 0.008) {
        guard let tw = trailWindow else { return }

        tw.setFrame(NSRect(x: screen.minX, y: screenH - screen.maxY,
                           width: screen.width, height: screen.height), display: false)

        trailHue += 0.75 * dt
        if trailHue > 1.0 { trailHue -= 1.0 }

        let pw = cachedPipSize.width
        let ph = cachedPipSize.height

        // Spawn from the TRAILING EDGE of the PiP — opposite to velocity
        // If moving right → spawn along left edge, if moving up → spawn along bottom edge
        let spawnCount = min(4, maxParticles - particles.count)
        for j in 0..<spawnCount {
            let isSparkle = j >= 2
            let sz: CGFloat = isSparkle ? CGFloat.random(in: 0.8...1.5) : CGFloat.random(in: 2.0...3.5)
            let lifeSpan: CGFloat = isSparkle ? CGFloat.random(in: 0.5...0.8) : CGFloat.random(in: 0.8...1.0)
            let particleHue = (trailHue + CGFloat.random(in: -0.05...0.05)).truncatingRemainder(dividingBy: 1.0)

            // Determine spawn position along trailing edge
            var sx: CGFloat
            var sy: CGFloat
            if abs(velocity.x) > abs(velocity.y) {
                // Primarily horizontal — spawn along trailing vertical edge
                sx = velocity.x > 0 ? ballPos.x : ballPos.x + pw
                sy = ballPos.y + CGFloat.random(in: 0...ph)
            } else {
                // Primarily vertical — spawn along trailing horizontal edge
                sx = ballPos.x + CGFloat.random(in: 0...pw)
                sy = velocity.y > 0 ? ballPos.y : ballPos.y + ph
            }
            // Small jitter off the edge
            let jitter: CGFloat = isSparkle ? CGFloat.random(in: -4...4) : CGFloat.random(in: -1.5...1.5)
            sx += jitter
            sy += jitter

            let dot = layerPool.dequeue()
            dot.backgroundColor = NSColor(hue: particleHue, saturation: 0.85,
                                           brightness: 1.0, alpha: 1.0).cgColor
            dot.cornerRadius = sz / 2
            tw.contentView!.layer!.addSublayer(dot)

            particles.append(Particle(
                layer: dot,
                x: sx,
                y: sy,
                vx: 0, vy: 0,
                life: lifeSpan,
                maxLife: lifeSpan,
                size: sz,
                hue: particleHue,
                twinkleRate: isSparkle ? CGFloat.random(in: 10...25) : 0
            ))
        }

        // Render — particles are stationary, they just fade and shrink in place
        var i = 0
        while i < particles.count {
            particles[i].life -= dt * 2.5
            if particles[i].life <= 0 {
                layerPool.enqueue(particles[i].layer)
                particles[i].layer.removeFromSuperlayer()
                particles.remove(at: i)
                continue
            }
            let p = particles[i]
            let t = p.life / p.maxLife

            let sx = p.x - screen.minX + shakeOffset.x
            let sy = screen.height - (p.y - screen.minY + shakeOffset.y)
            let renderSize = p.size * (0.2 + 0.8 * t)
            particles[i].layer.frame = CGRect(x: sx - renderSize / 2, y: sy - renderSize / 2,
                                               width: renderSize, height: renderSize)
            particles[i].layer.cornerRadius = renderSize / 2

            var alpha = t * 0.9
            if p.twinkleRate > 0 {
                alpha *= sin(p.life * p.twinkleRate * .pi) * 0.3 + 0.7
            }
            particles[i].layer.opacity = Float(alpha)

            let agingSat = max(0.15, 0.85 * t)
            particles[i].layer.backgroundColor = NSColor(
                hue: (p.hue + (1.0 - t) * 0.1).truncatingRemainder(dividingBy: 1.0),
                saturation: agingSat, brightness: 0.6 + 0.4 * t, alpha: 1.0).cgColor

            i += 1
        }
    }

    private func launchBall(direction: CGFloat) {
        let angle = CGFloat.random(in: -0.4...0.4)
        velocity = CGPoint(x: baseSpeed * direction, y: baseSpeed * sin(angle))
    }

    private func createOverlays(screen: CGRect) {
        let h = screenH

        // Player paddle (left side)
        playerPaddle = makePaddleWindow(
            nsFrame: NSRect(x: screen.minX + paddleMargin,
                            y: h - screen.midY - paddleHeight / 2,
                            width: paddleWidth, height: paddleHeight))

        // AI paddle (right side)
        aiPaddle = makePaddleWindow(
            nsFrame: NSRect(x: screen.maxX - paddleMargin - paddleWidth,
                            y: h - screen.midY - paddleHeight / 2,
                            width: paddleWidth, height: paddleHeight))

        // Score overlay — shared liquid glass pill
        createScoreOverlay(screen: screen, width: 160)
        scoreLabel?.attributedStringValue = Self.styledVersusScore("0", "0")

        // Trail window
        let tw = NSWindow(contentRect: NSRect(x: screen.minX, y: h - screen.maxY,
                                              width: screen.width, height: screen.height),
                          styleMask: .borderless, backing: .buffered, defer: false)
        tw.isOpaque = false
        tw.backgroundColor = .clear
        tw.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 2)
        tw.ignoresMouseEvents = true
        tw.hasShadow = false
        tw.collectionBehavior = [.canJoinAllSpaces, .stationary, .transient, .ignoresCycle]
        tw.contentView!.wantsLayer = true

        particles = []
        tw.orderFrontRegardless()
        trailWindow = tw
    }

    private func makePaddleWindow(nsFrame: NSRect) -> NSWindow {
        let w = NSWindow(contentRect: nsFrame, styleMask: .borderless, backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.level = .floating
        w.ignoresMouseEvents = true
        w.hasShadow = false
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .transient, .ignoresCycle]
        w.contentView!.wantsLayer = true
        let layer = w.contentView!.layer!
        layer.cornerRadius = paddleWidth / 2

        // Pulse-cycle background: purple → cyan → green → purple
        layer.backgroundColor = Self.glowCycleColors[0]
        let bgAnim = CAKeyframeAnimation(keyPath: "backgroundColor")
        bgAnim.values = Self.glowCycleColors
        bgAnim.keyTimes = [0, 0.33, 0.66, 1.0]
        bgAnim.duration = 3.0
        bgAnim.repeatCount = .infinity
        bgAnim.calculationMode = .linear
        layer.add(bgAnim, forKey: "glowCycle")

        // Pulse-cycle shadow
        layer.shadowOffset = .zero
        layer.shadowRadius = 12
        layer.shadowOpacity = 0.9
        layer.shadowColor = Self.glowCycleColors[0]
        let shadowAnim = CAKeyframeAnimation(keyPath: "shadowColor")
        shadowAnim.values = Self.glowCycleColors
        shadowAnim.keyTimes = [0, 0.33, 0.66, 1.0]
        shadowAnim.duration = 3.0
        shadowAnim.repeatCount = .infinity
        shadowAnim.calculationMode = .linear
        layer.add(shadowAnim, forKey: "shadowCycle")

        w.orderFrontRegardless()
        return w
    }

    private func updateOverlayPositions(screen: CGRect, shakeOffset: CGPoint = .zero) {
        let h = screenH

        // Player paddle (left)
        let pY = max(screen.minY, min(screen.maxY - paddleHeight, playerY))
        playerPaddle?.setFrame(
            NSRect(x: screen.minX + paddleMargin + shakeOffset.x,
                   y: h - pY - paddleHeight + shakeOffset.y,
                   width: paddleWidth, height: paddleHeight), display: true)

        // AI paddle (right)
        let aY = max(screen.minY, min(screen.maxY - paddleHeight, aiY))
        aiPaddle?.setFrame(
            NSRect(x: screen.maxX - paddleMargin - paddleWidth + shakeOffset.x,
                   y: h - aY - paddleHeight + shakeOffset.y,
                   width: paddleWidth, height: paddleHeight), display: true)

        // Score overlay
        if let sw = scoreOverlay {
            let scoreY = h - screen.minY - 75
            sw.setFrame(NSRect(x: screen.midX - 210 + shakeOffset.x,
                               y: scoreY + shakeOffset.y,
                               width: 420, height: 60), display: true)
        }
    }

    // MARK: - Score Display

    private func updateScore() {
        if let msg = matchOverMessage {
            scoreLabel?.attributedStringValue = Self.styledMessage(msg)
        } else {
            scoreLabel?.attributedStringValue = Self.styledVersusScore("\(playerScore)", "\(aiScore)")
        }
        pulseScoreOverlay()
    }
}
