import Cocoa
import ApplicationServices

let pong = PongGame()

class PongGame: MiniGame {
    var active = false
    var lastBounds = CGRect.zero

    private var velocity = CGPoint.zero
    private let baseSpeed: CGFloat = 420.0
    private let maxSpeed: CGFloat = 900.0

    private var playerPaddle: NSWindow?
    private var aiPaddle: NSWindow?
    private var scoreOverlay: NSWindow?
    private var scoreLabel: NSTextField?

    private let paddleWidth: CGFloat = 8
    private let paddleMargin: CGFloat = 20
    private var paddleHeight: CGFloat = 150

    private var playerScore = 0
    private var aiScore = 0
    private var aiY: CGFloat = 0
    private let aiSpeed: CGFloat = 300.0

    private var pauseUntil: UInt64 = 0
    private var lastMach: UInt64 = 0
    private var ballPos = CGPoint.zero
    private var scoreChanged = false

    // Cached PiP reference -- avoids findPipWindow() every frame
    private var cachedAXWindow: AXUIElement?
    private var cachedPipSize = CGSize.zero

    private var borderRef: RGBBorder?

    // High-frequency timer on main queue -- keeps PiP + border perfectly synchronized
    private var gameTimer: DispatchSourceTimer?

    private static var timebaseInfo: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    private func machToSeconds(_ ticks: UInt64) -> CGFloat {
        let info = Self.timebaseInfo
        return CGFloat(Double(ticks) * Double(info.numer) / Double(info.denom) / 1_000_000_000)
    }

    private func secondsToMach(_ sec: Double) -> UInt64 {
        let info = Self.timebaseInfo
        return UInt64(sec * 1_000_000_000) * UInt64(info.denom) / UInt64(info.numer)
    }

    func start(screen: CGRect, pip: PipWindowInfo, border: RGBBorder) {
        playerScore = 0
        aiScore = 0
        scoreChanged = false
        paddleHeight = screen.height * 0.15
        aiY = screen.midY - paddleHeight / 2
        lastMach = mach_absolute_time()
        pauseUntil = 0

        cachedAXWindow = pip.axWindow
        cachedPipSize = pip.bounds.size
        ballPos = pip.bounds.origin
        borderRef = border

        launchBall(direction: Bool.random() ? 1 : -1)

        if Thread.isMainThread {
            createOverlays(screen: screen)
        } else {
            DispatchQueue.main.sync { self.createOverlays(screen: screen) }
        }

        active = true
        print("Pong started")

        // 500fps on main queue -- PiP move + border move happen in the SAME call,
        // microseconds apart, so they never desync
        let t = DispatchSource.makeTimerSource(flags: .strict, queue: .main)
        t.schedule(deadline: .now(), repeating: .milliseconds(2), leeway: .microseconds(100))
        t.setEventHandler { [weak self] in self?.gameTick() }
        gameTimer = t
        t.resume()
    }

    private func gameTick() {
        guard active, let axWindow = cachedAXWindow else { return }

        guard let event = CGEvent(source: nil) else { return }
        let mousePos = event.location
        let screen = getScreenFrame()
        let size = cachedPipSize

        let now = mach_absolute_time()
        let dt = min(machToSeconds(now - lastMach), 0.05)
        lastMach = now

        // Pause after score -- paddles still track mouse
        if pauseUntil > 0 {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            updatePaddlePositions(playerY: mousePos.y - paddleHeight / 2, screen: screen)
            let bounds = CGRect(origin: ballPos, size: size)
            lastBounds = bounds
            updateBorder(bounds)
            if scoreChanged { updateScore(); scoreChanged = false }
            CATransaction.commit()
            if now < pauseUntil { return }
            pauseUntil = 0
        }

        // Physics
        ballPos.x += velocity.x * dt
        ballPos.y += velocity.y * dt

        if ballPos.y <= screen.minY {
            ballPos.y = screen.minY
            velocity.y = abs(velocity.y)
        }
        if ballPos.y + size.height >= screen.maxY {
            ballPos.y = screen.maxY - size.height
            velocity.y = -abs(velocity.y)
        }

        let spd = sqrt(velocity.x * velocity.x + velocity.y * velocity.y)
        if spd > maxSpeed {
            let s = maxSpeed / spd
            velocity.x *= s
            velocity.y *= s
        }

        let pX = screen.minX + paddleMargin
        let pY = max(screen.minY, min(screen.maxY - paddleHeight, mousePos.y - paddleHeight / 2))

        let aiX = screen.maxX - paddleMargin - paddleWidth
        let ballCY = ballPos.y + size.height / 2
        let aiTarget = ballCY - paddleHeight / 2
        let aiDiff = aiTarget - aiY
        aiY += max(-aiSpeed * dt, min(aiSpeed * dt, aiDiff))
        aiY = max(screen.minY, min(screen.maxY - paddleHeight, aiY))

        if ballPos.x <= pX + paddleWidth && ballPos.x >= pX - size.width / 2 && velocity.x < 0 {
            if ballCY >= pY && ballCY <= pY + paddleHeight {
                velocity.x = abs(velocity.x) * 1.05
                let hit = (ballCY - pY) / paddleHeight - 0.5
                velocity.y += hit * 200
                ballPos.x = pX + paddleWidth
            }
        }

        if ballPos.x + size.width >= aiX && ballPos.x + size.width <= aiX + paddleWidth + size.width / 2 && velocity.x > 0 {
            if ballCY >= aiY && ballCY <= aiY + paddleHeight {
                velocity.x = -(abs(velocity.x) * 1.05)
                let hit = (ballCY - aiY) / paddleHeight - 0.5
                velocity.y += hit * 200
                ballPos.x = aiX - size.width
            }
        }

        if ballPos.x + size.width < screen.minX - 30 {
            aiScore += 1
            scoreChanged = true
            ballPos = CGPoint(x: screen.midX - size.width / 2, y: screen.midY - size.height / 2)
            launchBall(direction: 1)
            pauseUntil = mach_absolute_time() + secondsToMach(0.8)
        }

        if ballPos.x > screen.maxX + 30 {
            playerScore += 1
            scoreChanged = true
            ballPos = CGPoint(x: screen.midX - size.width / 2, y: screen.midY - size.height / 2)
            launchBall(direction: -1)
            pauseUntil = mach_absolute_time() + secondsToMach(0.8)
        }

        // Move PiP THEN border -- same thread, microseconds apart, perfectly synced
        var newPos = ballPos
        if let val = AXValueCreate(.cgPoint, &newPos) {
            let err = AXUIElementSetAttributeValue(axWindow, kAXPositionAttribute as CFString, val)
            if err != .success {
                stop()
                return
            }
        }

        let bounds = CGRect(origin: ballPos, size: size)
        lastBounds = bounds

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        updatePaddlePositions(playerY: pY, screen: screen)
        updateBorder(bounds)
        if scoreChanged { updateScore(); scoreChanged = false }
        CATransaction.commit()
    }

    private func updateBorder(_ bounds: CGRect) {
        if settings.glow, let border = borderRef {
            border.show(around: bounds)
        } else {
            borderRef?.hide()
        }
    }

    func stop() {
        gameTimer?.cancel()
        gameTimer = nil
        active = false
        ballPos = .zero
        lastMach = 0
        cachedAXWindow = nil
        borderRef?.hide()
        borderRef = nil

        let pw = playerPaddle, aw = aiPaddle, sw = scoreOverlay
        let cleanup = {
            pw?.orderOut(nil)
            aw?.orderOut(nil)
            sw?.orderOut(nil)
        }
        if Thread.isMainThread { cleanup() }
        else { DispatchQueue.main.async { cleanup() } }
        playerPaddle = nil
        aiPaddle = nil
        scoreOverlay = nil
        scoreLabel = nil
        print("Pong stopped")
    }

    private func launchBall(direction: CGFloat) {
        let angle = CGFloat.random(in: -0.4...0.4)
        velocity = CGPoint(x: baseSpeed * direction, y: baseSpeed * sin(angle))
    }

    private func createOverlays(screen: CGRect) {
        let h = (NSScreen.main ?? NSScreen.screens[0]).frame.height

        playerPaddle = makePaddleWindow(
            nsFrame: NSRect(x: screen.minX + paddleMargin,
                            y: h - screen.midY - paddleHeight / 2,
                            width: paddleWidth, height: paddleHeight))

        aiPaddle = makePaddleWindow(
            nsFrame: NSRect(x: screen.maxX - paddleMargin - paddleWidth,
                            y: h - screen.midY - paddleHeight / 2,
                            width: paddleWidth, height: paddleHeight))

        let sw = NSWindow(contentRect: NSRect(x: screen.midX - 80, y: h - 55, width: 160, height: 44),
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
        label.stringValue = "0 : 0"
        sw.contentView!.addSubview(label)
        sw.orderFrontRegardless()

        scoreOverlay = sw
        scoreLabel = label
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

    private func updatePaddlePositions(playerY: CGFloat, screen: CGRect) {
        let h = (NSScreen.main ?? NSScreen.screens[0]).frame.height

        playerPaddle?.setFrame(
            NSRect(x: screen.minX + paddleMargin, y: h - playerY - paddleHeight,
                   width: paddleWidth, height: paddleHeight), display: true)

        let aY = max(screen.minY, min(screen.maxY - paddleHeight, aiY))
        aiPaddle?.setFrame(
            NSRect(x: screen.maxX - paddleMargin - paddleWidth, y: h - aY - paddleHeight,
                   width: paddleWidth, height: paddleHeight), display: true)
    }

    private func updateScore() {
        scoreLabel?.stringValue = "\(playerScore) : \(aiScore)"
    }
}
