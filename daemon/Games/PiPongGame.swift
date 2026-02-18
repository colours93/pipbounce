import Cocoa
import ApplicationServices

let pipong = PiPongGame()

/// PiPong — classic mode where the PiP window IS the ball.
/// Both paddles are overlay windows. Player controls left paddle with mouse Y.
class PiPongGame: GameBase {

    private var velocity = CGPoint.zero
    private let baseSpeed: CGFloat = 420.0
    private let maxSpeed: CGFloat = 900.0

    private var playerPaddle: NSWindow?
    private var aiPaddle: NSWindow?

    private let paddleWidth: CGFloat = 8
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

    // Ball trail
    private var trailWindow: NSWindow?
    private var trailLayers: [CALayer] = []
    private var trailPositions: [CGPoint] = []
    private var trailFrameCounter = 0
    private let trailCount = 3

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
        trailLayers = []
        trailPositions = []
        trailFrameCounter = 0
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
        trailLayers = []
        trailPositions = []
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
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                updateOverlayPositions(screen: screen)
                let pipBounds = CGRect(origin: ballPos, size: cachedPipSize)
                syncBorder(around: pipBounds)
                CATransaction.commit()
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
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            updateOverlayPositions(screen: screen)
            let pipBounds = CGRect(origin: ballPos, size: cachedPipSize)
            syncBorder(around: pipBounds)
            if scoreChanged { updateScore(); scoreChanged = false }
            CATransaction.commit()
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

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        updateOverlayPositions(screen: screen, shakeOffset: shakeOff)
        syncBorder(around: pipBounds)
        updateTrail(shakeOffset: shakeOff, screen: screen)
        if scoreChanged { updateScore(); scoreChanged = false }
        CATransaction.commit()
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
        flash.fromValue = glowCGColor()
        flash.toValue = NSColor.white.cgColor
        flash.duration = 0.1
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

    private func updateTrail(shakeOffset: CGPoint, screen: CGRect) {
        guard let tw = trailWindow else { return }

        tw.setFrame(NSRect(x: screen.minX, y: screenH - screen.maxY,
                           width: screen.width, height: screen.height), display: false)

        trailFrameCounter += 1
        if trailFrameCounter >= 2 {
            trailFrameCounter = 0
            trailPositions.insert(CGPoint(x: ballPos.x + cachedPipSize.width / 2,
                                           y: ballPos.y + cachedPipSize.height / 2), at: 0)
            if trailPositions.count > trailCount + 2 {
                trailPositions.removeLast()
            }
        }

        let dotSize: CGFloat = min(cachedPipSize.width, cachedPipSize.height) * 0.4
        let color = glowCGColor()

        for i in 0..<trailLayers.count {
            let posIdx = i + 1
            if posIdx < trailPositions.count {
                let p = trailPositions[posIdx]
                let cx = p.x - screen.minX + shakeOffset.x - dotSize / 2
                let cy = p.y - screen.minY + shakeOffset.y - dotSize / 2
                let sz = dotSize * (1.0 - CGFloat(i + 1) * 0.15)
                trailLayers[i].frame = CGRect(x: cx + (dotSize - sz) / 2,
                                               y: screen.height - cy - dotSize + (dotSize - sz) / 2,
                                               width: sz, height: sz)
                trailLayers[i].cornerRadius = sz / 2
                trailLayers[i].backgroundColor = color
                trailLayers[i].opacity = Float(1.0 - CGFloat(i + 1) * 0.25)
            }
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

        // Score overlay
        let scoreY = h - screen.minY - 55
        let sw = NSWindow(contentRect: NSRect(x: screen.midX - 80, y: scoreY, width: 160, height: 44),
                          styleMask: .borderless, backing: .buffered, defer: false)
        sw.isOpaque = false
        sw.backgroundColor = .clear
        sw.level = .floating
        sw.ignoresMouseEvents = true
        sw.hasShadow = false
        sw.collectionBehavior = [.canJoinAllSpaces, .stationary, .transient, .ignoresCycle]

        let vibrancy = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 160, height: 44))
        vibrancy.material = .hudWindow
        vibrancy.blendingMode = .behindWindow
        vibrancy.state = .active
        vibrancy.wantsLayer = true
        vibrancy.layer?.cornerRadius = 8
        sw.contentView = vibrancy

        let label = NSTextField(frame: NSRect(x: 0, y: 0, width: 160, height: 44))
        label.isEditable = false
        label.isBordered = false
        label.backgroundColor = .clear
        label.textColor = .white
        label.font = NSFont.monospacedSystemFont(ofSize: 24, weight: .bold)
        label.alignment = .center
        label.stringValue = "0 : 0"
        vibrancy.addSubview(label)
        sw.orderFrontRegardless()

        scoreOverlay = sw
        scoreLabel = label

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
        w.contentView!.layer!.backgroundColor = NSColor.white.cgColor
        w.contentView!.layer!.cornerRadius = paddleWidth / 2
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
            let scoreY = h - screen.minY - 55
            sw.setFrame(NSRect(x: screen.midX - 80 + shakeOffset.x,
                               y: scoreY + shakeOffset.y,
                               width: 160, height: 44), display: true)
        }
    }

    private func updateScore() {
        if let msg = matchOverMessage {
            scoreLabel?.stringValue = msg
        } else {
            scoreLabel?.stringValue = "\(playerScore) : \(aiScore)"
        }
    }
}
