import Cocoa
import ApplicationServices



class PiPong2Game: GameBase {

    // Glow cycle colors: purple → cyan → green → purple
    private static let glowCycleColors: [CGColor] = [
        NSColor(red: 0.7, green: 0.2, blue: 1.0, alpha: 1).cgColor,    // purple
        NSColor(red: 0.3, green: 0.8, blue: 1.0, alpha: 1).cgColor,    // cyan
        NSColor(red: 0.2, green: 1.0, blue: 0.6, alpha: 1).cgColor,    // green
        NSColor(red: 0.7, green: 0.2, blue: 1.0, alpha: 1).cgColor,    // back to purple
    ]

    private var velocity = CGPoint.zero
    private let baseSpeed: CGFloat = 420.0
    private let maxSpeed: CGFloat = 900.0

    // Ball is now a separate window (PiP = player paddle)
    private var ballWindow: NSWindow?
    private let ballSize: CGFloat = 16
    private var ballPos = CGPoint.zero

    private var aiPaddle: NSWindow?

    private let paddleWidth: CGFloat = 10
    private let paddleMargin: CGFloat = 20
    private var paddleHeight: CGFloat = 150

    private var playerScore = 0
    private var aiScore = 0
    private var aiY: CGFloat = 0
    private let aiSpeed: CGFloat = 300.0

    private var pauseUntil: UInt64 = 0
    private var scoreChanged = false

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

    // Ball trail (manual position history)
    private var trailWindow: NSWindow?
    private var trailLayers: [CALayer] = []
    private var trailPositions: [CGPoint] = []
    private var trailFrameCounter = 0
    private let trailCount = 5

    // Screen shake
    private var shakeFramesRemaining = 0

    // Center line
    private var centerLine: NSWindow?

    // PiP paddle position
    private var pipPaddleY: CGFloat = 0


    override func onStart(screen: CGRect, pip: PipWindowInfo) {
        timerIntervalMs = 8

        playerScore = 0
        aiScore = 0
        scoreChanged = false
        paddleHeight = screen.height * 0.15
        aiY = screen.midY - paddleHeight / 2
        aiTargetY = aiY
        aiTargetNoise = 0
        aiLastUpdateMach = 0
        pauseUntil = 0
        matchOverUntil = 0
        matchOverMessage = nil
        rallyStartMach = mach_absolute_time()
        trailLayers = []
        trailPositions = []
        trailFrameCounter = 0
        shakeFramesRemaining = 0
        pipPaddleY = screen.midY - cachedPipSize.height / 2

        ballPos = CGPoint(x: screen.midX - ballSize / 2, y: screen.midY - ballSize / 2)

        launchBall(direction: Bool.random() ? 1 : -1)

        if Thread.isMainThread {
            createOverlays(screen: screen)
        } else {
            DispatchQueue.main.sync { self.createOverlays(screen: screen) }
        }

        // Position PiP as left paddle immediately
        let pipX = screen.minX + paddleMargin
        movePip(to: CGPoint(x: pipX, y: pipPaddleY))

        print("Pong started")
    }

    override func onStop() {
        ballPos = .zero

        let bw = ballWindow, aw = aiPaddle, tw = trailWindow, cl = centerLine
        let cleanup = {
            bw?.orderOut(nil)
            aw?.orderOut(nil)
            tw?.orderOut(nil)
            cl?.orderOut(nil)
        }
        if Thread.isMainThread { cleanup() }
        else { DispatchQueue.main.async { cleanup() } }
        ballWindow = nil
        aiPaddle = nil
        trailWindow = nil
        centerLine = nil
        trailLayers = []
        trailPositions = []
        print("Pong stopped")
    }

    override func gameTick() {
        guard active, let _ = cachedAXWindow else { return }

        refreshPipSize()

        guard let mousePos = mousePosition() else { return }
        let screen = getScreenFrame()

        let dt = deltaTime()
        let now = mach_absolute_time()

        let pipX = screen.minX + paddleMargin

        // Move PiP (player paddle) to track mouse Y
        pipPaddleY = max(screen.minY, min(screen.maxY - cachedPipSize.height, mousePos.y - cachedPipSize.height / 2))
        if !movePip(to: CGPoint(x: pipX, y: pipPaddleY)) { return }

        // Match over pause
        if matchOverUntil > 0 {
            if now < matchOverUntil {
                withTransaction {
                    updateOverlayPositions(screen: screen)
                    let pipBounds = CGRect(x: pipX, y: pipPaddleY, width: cachedPipSize.width, height: cachedPipSize.height)
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
                let pipBounds = CGRect(x: pipX, y: pipPaddleY, width: cachedPipSize.width, height: cachedPipSize.height)
                syncBorder(around: pipBounds)
                if scoreChanged { updateScore(); scoreChanged = false }
            }
            if now < pauseUntil { return }
            pauseUntil = 0
            rallyStartMach = now
        }

        // Speed ramp: linearly from baseSpeed to maxSpeed over speedRampDuration
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

        // Ball physics
        ballPos.x += velocity.x * dt
        ballPos.y += velocity.y * dt

        // Top/bottom bounce
        if ballPos.y <= screen.minY {
            ballPos.y = screen.minY
            velocity.y = abs(velocity.y)
        }
        if ballPos.y + ballSize >= screen.maxY {
            ballPos.y = screen.maxY - ballSize
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
        let ballCY = ballPos.y + ballSize / 2
        let midX = screen.midX

        if velocity.x > 0 && ballPos.x + ballSize > midX {
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

        let aiX = screen.maxX - paddleMargin - paddleWidth

        // Player paddle collision (PiP = paddle)
        let deflectScale = 150 + (currentSpeed / maxSpeed) * 100
        let playerRight = pipX + cachedPipSize.width
        if ballPos.x <= playerRight && ballPos.x + ballSize >= pipX && velocity.x < 0 {
            if ballCY >= pipPaddleY && ballCY <= pipPaddleY + cachedPipSize.height {
                velocity.x = abs(velocity.x)
                let hit = (ballCY - pipPaddleY) / cachedPipSize.height - 0.5
                velocity.y += hit * deflectScale
                let s2 = sqrt(velocity.x * velocity.x + velocity.y * velocity.y)
                if s2 > maxSpeed { let c = maxSpeed / s2; velocity.x *= c; velocity.y *= c }
                ballPos.x = playerRight
                flashPipBorder()
            }
        }

        // AI paddle collision
        if ballPos.x + ballSize >= aiX && ballPos.x + ballSize <= aiX + paddleWidth + ballSize / 2 && velocity.x > 0 {
            if ballCY >= aiY && ballCY <= aiY + paddleHeight {
                velocity.x = -(abs(velocity.x))
                let hit = (ballCY - aiY) / paddleHeight - 0.5
                velocity.y += hit * deflectScale
                let s2 = sqrt(velocity.x * velocity.x + velocity.y * velocity.y)
                if s2 > maxSpeed { let c = maxSpeed / s2; velocity.x *= c; velocity.y *= c }
                ballPos.x = aiX - ballSize
                flashPaddle(aiPaddle)
            }
        }

        // Scoring
        if ballPos.x + ballSize < screen.minX - 30 {
            aiScore += 1
            scoreChanged = true
            ballPos = CGPoint(x: screen.midX - ballSize / 2, y: screen.midY - ballSize / 2)
            launchBall(direction: 1)
            triggerShake()
            if checkMatchOver() { return }
            pauseUntil = mach_absolute_time() + secondsToMach(0.8)
            rallyStartMach = 0
        }

        if ballPos.x > screen.maxX + 30 {
            playerScore += 1
            scoreChanged = true
            ballPos = CGPoint(x: screen.midX - ballSize / 2, y: screen.midY - ballSize / 2)
            launchBall(direction: -1)
            triggerShake()
            if checkMatchOver() { return }
            pauseUntil = mach_absolute_time() + secondsToMach(0.8)
            rallyStartMach = 0
        }

        // Border around PiP (player paddle)
        let pipBounds = CGRect(x: pipX, y: pipPaddleY, width: cachedPipSize.width, height: cachedPipSize.height)

        withTransaction {
            let shakeOff = applyShake()

            updateOverlayPositions(screen: screen, shakeOffset: shakeOff)
            syncBorder(around: pipBounds)
            updateTrail(shakeOffset: shakeOff, screen: screen)
            if scoreChanged { updateScore(); scoreChanged = false }
        }
    }

    // MARK: - AI Difficulty

    private func aiNoiseAmount() -> CGFloat {
        let diff = playerScore - aiScore
        if diff >= 3 {
            return 5
        } else if diff <= -3 {
            return 40
        }
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

    private func flashPipBorder() {
        guard let border = borderRef else { return }
        let pipBounds = CGRect(x: lastBounds.origin.x, y: lastBounds.origin.y,
                               width: cachedPipSize.width, height: cachedPipSize.height)
        border.show(around: pipBounds)
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
        shakeFramesRemaining = 6
    }

    private func applyShake() -> CGPoint {
        if shakeFramesRemaining > 0 {
            shakeFramesRemaining -= 1
            return CGPoint(x: CGFloat.random(in: -4...4), y: CGFloat.random(in: -4...4))
        }
        return .zero
    }

    // MARK: - Ball Trail

    private func updateTrail(shakeOffset: CGPoint, screen: CGRect) {
        guard let tw = trailWindow else { return }

        tw.setFrame(NSRect(x: screen.minX, y: screenH - screen.maxY,
                           width: screen.width, height: screen.height), display: false)

        trailFrameCounter += 1
        if trailFrameCounter >= 2 {
            trailFrameCounter = 0
            trailPositions.insert(CGPoint(x: ballPos.x + ballSize / 2,
                                           y: ballPos.y + ballSize / 2), at: 0)
            if trailPositions.count > trailCount + 2 {
                trailPositions.removeLast()
            }
        }

        let dotSize: CGFloat = ballSize * 0.8
        let color = glowCGColor()

        let opacities: [Float] = [0.4, 0.3, 0.2, 0.1, 0.05]
        let scales: [CGFloat] = [0.8, 0.67, 0.55, 0.42, 0.3]

        for i in 0..<trailLayers.count {
            let posIdx = i + 1
            if posIdx < trailPositions.count {
                let p = trailPositions[posIdx]
                let cx = p.x - screen.minX + shakeOffset.x - dotSize / 2
                let cy = p.y - screen.minY + shakeOffset.y - dotSize / 2
                let scale = i < scales.count ? scales[i] : 0.3
                let sz = dotSize * scale
                trailLayers[i].frame = CGRect(x: cx + (dotSize - sz) / 2,
                                               y: screen.height - cy - dotSize + (dotSize - sz) / 2,
                                               width: sz, height: sz)
                trailLayers[i].cornerRadius = sz / 2
                trailLayers[i].backgroundColor = color
                trailLayers[i].opacity = i < opacities.count ? opacities[i] : 0.05
            }
        }
    }

    private func launchBall(direction: CGFloat) {
        let angle = CGFloat.random(in: -0.4...0.4)
        velocity = CGPoint(x: baseSpeed * direction, y: baseSpeed * sin(angle))
    }

    private func createOverlays(screen: CGRect) {
        let h = screenH

        // AI paddle (right side) — glowing color-cycling paddle
        aiPaddle = makePaddleWindow(
            nsFrame: NSRect(x: screen.maxX - paddleMargin - paddleWidth,
                            y: h - screen.midY - paddleHeight / 2,
                            width: paddleWidth, height: paddleHeight))

        // Ball window — small glowing circle
        let bw = NSWindow(contentRect: NSRect(x: screen.midX - ballSize / 2,
                                              y: h - screen.midY - ballSize / 2,
                                              width: ballSize, height: ballSize),
                          styleMask: .borderless, backing: .buffered, defer: false)
        bw.isOpaque = false
        bw.backgroundColor = .clear
        bw.level = .floating
        bw.ignoresMouseEvents = true
        bw.hasShadow = false
        bw.collectionBehavior = [.canJoinAllSpaces, .stationary, .transient, .ignoresCycle]
        bw.contentView!.wantsLayer = true
        bw.contentView!.layer!.backgroundColor = glowCGColor()
        bw.contentView!.layer!.cornerRadius = ballSize / 2
        bw.contentView!.layer!.shadowColor = glowCGColor()
        bw.contentView!.layer!.shadowRadius = 10
        bw.contentView!.layer!.shadowOpacity = 1.0
        bw.contentView!.layer!.shadowOffset = .zero
        bw.orderFrontRegardless()
        ballWindow = bw

        // Score overlay — shared liquid glass pill
        createScoreOverlay(screen: screen, width: 160)
        scoreLabel?.attributedStringValue = Self.styledVersusScore("0", "0")

        // Dashed center line (decorative)
        let centerLineWindow = NSWindow(
            contentRect: NSRect(x: screen.midX - 1, y: h - screen.maxY,
                                width: 2, height: screen.height),
            styleMask: .borderless, backing: .buffered, defer: false)
        centerLineWindow.isOpaque = false
        centerLineWindow.backgroundColor = .clear
        centerLineWindow.level = .floating
        centerLineWindow.ignoresMouseEvents = true
        centerLineWindow.hasShadow = false
        centerLineWindow.collectionBehavior = [.canJoinAllSpaces, .stationary, .transient, .ignoresCycle]
        centerLineWindow.contentView!.wantsLayer = true

        let dashHeight: CGFloat = 12
        let dashSpacing: CGFloat = 24
        var yOff: CGFloat = 0
        while yOff + dashHeight <= screen.height {
            let dash = CALayer()
            dash.frame = CGRect(x: 0, y: yOff, width: 2, height: dashHeight)
            dash.backgroundColor = NSColor(white: 1.0, alpha: 0.15).cgColor
            centerLineWindow.contentView!.layer!.addSublayer(dash)
            yOff += dashSpacing
        }
        centerLineWindow.orderFrontRegardless()
        centerLine = centerLineWindow

        // Trail window
        let tw = NSWindow(contentRect: NSRect(x: screen.minX, y: h - screen.maxY,
                                              width: screen.width, height: screen.height),
                          styleMask: .borderless, backing: .buffered, defer: false)
        tw.isOpaque = false
        tw.backgroundColor = .clear
        tw.level = .floating
        tw.ignoresMouseEvents = true
        tw.hasShadow = false
        tw.collectionBehavior = [.canJoinAllSpaces, .stationary, .transient, .ignoresCycle]
        tw.contentView!.wantsLayer = true

        trailLayers = []
        trailPositions = []
        trailFrameCounter = 0
        for _ in 0..<trailCount {
            let dot = CALayer()
            dot.opacity = 0
            tw.contentView!.layer!.addSublayer(dot)
            trailLayers.append(dot)
        }

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

        // Start with first glow color
        layer.backgroundColor = Self.glowCycleColors[0]

        // Pulse-cycle background: purple → cyan → green → purple
        let bgAnim = CAKeyframeAnimation(keyPath: "backgroundColor")
        bgAnim.values = Self.glowCycleColors
        bgAnim.keyTimes = [0, 0.33, 0.66, 1.0]
        bgAnim.duration = 3.0
        bgAnim.repeatCount = .infinity
        bgAnim.calculationMode = .linear
        layer.add(bgAnim, forKey: "glowCycle")

        // Pulse-cycle the shadow color in sync
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

        // Ball window position
        if let bw = ballWindow {
            bw.setFrame(NSRect(x: ballPos.x + shakeOffset.x,
                               y: h - ballPos.y - ballSize + shakeOffset.y,
                               width: ballSize, height: ballSize), display: true)
        }

        // AI paddle
        let aY = max(screen.minY, min(screen.maxY - paddleHeight, aiY))
        aiPaddle?.setFrame(
            NSRect(x: screen.maxX - paddleMargin - paddleWidth + shakeOffset.x,
                   y: h - aY - paddleHeight + shakeOffset.y,
                   width: paddleWidth, height: paddleHeight), display: true)

        // Center line
        if let cl = centerLine {
            cl.setFrame(NSRect(x: screen.midX - 1 + shakeOffset.x,
                               y: h - screen.maxY + shakeOffset.y,
                               width: 2, height: screen.height), display: false)
        }

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
