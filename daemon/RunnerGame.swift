import Cocoa
import ApplicationServices

let runner = RunnerGame()

class RunnerGame: MiniGame {
    var active = false
    var lastBounds = CGRect.zero

    // Obstacle definition: a wall with a gap
    private struct Obstacle {
        let topLayer: CALayer
        let bottomLayer: CALayer
        let gapTopIndicator: CALayer
        let gapBottomIndicator: CALayer
        var x: CGFloat           // AX coords (left edge of wall)
        let gapY: CGFloat        // AX y of gap top edge
        let gapHeight: CGFloat
        var scored: Bool         // whether PiP has passed this obstacle
    }

    private var obstacles: [Obstacle] = []
    private let obstacleWidth: CGFloat = 30

    // Speed
    private var scrollSpeed: CGFloat = 200
    private let startSpeed: CGFloat = 200
    private let maxSpeed: CGFloat = 600
    private let speedIncrement: CGFloat = 8  // per second

    // PiP position
    private var pipX: CGFloat = 0
    private var pipY: CGFloat = 0

    // Scoring
    private var score = 0
    private var scoreTimer: CGFloat = 0
    private var scoreOverlay: NSWindow?
    private var scoreLabel: NSTextField?

    // Game state
    private var gameOver = false
    private var gameEndMach: UInt64 = 0

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

    // Colors
    private let obstacleColor = NSColor(red: 0.25, green: 0.28, blue: 0.32, alpha: 1.0).cgColor
    private let obstacleBorderColor = NSColor(red: 0.35, green: 0.38, blue: 0.42, alpha: 0.6).cgColor
    private let gapIndicatorColor = NSColor(red: 0.0, green: 0.55, blue: 0.3, alpha: 0.4).cgColor

    // MARK: - MiniGame Protocol

    func start(screen: CGRect, pip: PipWindowInfo, border: RGBBorder) {
        score = 0
        scoreTimer = 0
        gameOver = false
        obstacles = []
        scrollSpeed = startSpeed

        cachedAXWindow = pip.axWindow
        cachedPipSize = pip.bounds.size
        borderRef = border
        screenH = (NSScreen.main ?? NSScreen.screens[0]).frame.height
        lastMach = mach_absolute_time()

        // PiP on left side, vertically centered
        pipX = screen.minX + screen.width * 0.18
        pipY = screen.midY - cachedPipSize.height / 2

        if Thread.isMainThread {
            createOverlays(screen: screen)
        } else {
            DispatchQueue.main.sync { self.createOverlays(screen: screen) }
        }

        active = true
        print("Runner started")

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
        obstacles = []
        print("Runner stopped")
    }

    // MARK: - Overlay Creation

    private func createOverlays(screen: CGRect) {
        // Full-screen game overlay for obstacles
        let ow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: screen.width, height: screenH),
                          styleMask: .borderless, backing: .buffered, defer: false)
        ow.isOpaque = false
        ow.backgroundColor = .clear
        ow.level = .floating
        ow.ignoresMouseEvents = true
        ow.hasShadow = false
        ow.collectionBehavior = [.canJoinAllSpaces, .stationary, .transient, .ignoresCycle]
        ow.contentView!.wantsLayer = true

        overlayLayer = ow.contentView!.layer!
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

    // MARK: - Game Loop

    private func gameTick() {
        guard active, let axWindow = cachedAXWindow else { return }

        let screen = getScreenFrame()
        let size = cachedPipSize
        let now = mach_absolute_time()
        let dt = min(machToSeconds(now - lastMach), 0.05)
        lastMach = now

        // Game over state -- wait then stop
        if gameOver {
            if machToSeconds(now - gameEndMach) > 2.5 { stop() }
            return
        }

        // --- Input: mouse Y controls PiP Y ---
        guard let event = CGEvent(source: nil) else { return }
        let mousePos = event.location
        pipY = max(screen.minY, min(screen.maxY - size.height, mousePos.y - size.height / 2))

        // --- Increase speed over time ---
        scrollSpeed = min(scrollSpeed + speedIncrement * dt, maxSpeed)

        // --- Move obstacles left ---
        for i in 0..<obstacles.count {
            obstacles[i].x -= scrollSpeed * dt
        }

        // --- Spawn new obstacles ---
        let spawnX = screen.maxX + 20
        let shouldSpawn: Bool
        if obstacles.isEmpty {
            shouldSpawn = true
        } else {
            let lastObs = obstacles.last!
            shouldSpawn = lastObs.x < screen.maxX - 300
        }

        if shouldSpawn {
            spawnObstacle(at: spawnX, screen: screen, pipSize: size)
        }

        // --- Remove off-screen obstacles ---
        obstacles.removeAll { obs in
            let offscreen = obs.x + obstacleWidth < screen.minX - 40
            if offscreen {
                obs.topLayer.removeFromSuperlayer()
                obs.bottomLayer.removeFromSuperlayer()
                obs.gapTopIndicator.removeFromSuperlayer()
                obs.gapBottomIndicator.removeFromSuperlayer()
            }
            return offscreen
        }

        // --- Collision detection ---
        let pipRect = CGRect(x: pipX + 4, y: pipY + 4,
                             width: size.width - 8, height: size.height - 8)

        for obs in obstacles {
            // Top wall: from screen top to gap top
            let topRect = CGRect(x: obs.x, y: screen.minY,
                                 width: obstacleWidth, height: obs.gapY - screen.minY)
            // Bottom wall: from gap bottom to screen bottom
            let gapBottom = obs.gapY + obs.gapHeight
            let bottomRect = CGRect(x: obs.x, y: gapBottom,
                                    width: obstacleWidth, height: screen.maxY - gapBottom)

            if pipRect.intersects(topRect) || pipRect.intersects(bottomRect) {
                triggerGameOver(now: now)
                break
            }
        }

        // --- Scoring: when PiP passes an obstacle ---
        for i in 0..<obstacles.count {
            if !obstacles[i].scored && obstacles[i].x + obstacleWidth < pipX {
                obstacles[i].scored = true
                score += 1
                scoreLabel?.stringValue = "\(score)"
            }
        }

        // --- Distance-based score increment ---
        scoreTimer += dt
        if scoreTimer >= 0.5 {
            scoreTimer -= 0.5
            score += 1
            scoreLabel?.stringValue = "\(score)"
        }

        // --- Move PiP ---
        var newPos = CGPoint(x: pipX, y: pipY)
        if let val = AXValueCreate(.cgPoint, &newPos) {
            let err = AXUIElementSetAttributeValue(axWindow, kAXPositionAttribute as CFString, val)
            if err != .success {
                stop()
                return
            }
        }

        // --- Update visuals ---
        let bounds = CGRect(origin: CGPoint(x: pipX, y: pipY), size: size)
        lastBounds = bounds

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        for obs in obstacles {
            let gapBottom = obs.gapY + obs.gapHeight

            // Top wall: from screen.minY to gapY (AX coords, y-down)
            let topH = obs.gapY - screen.minY
            obs.topLayer.frame = CGRect(x: obs.x,
                                        y: screenH - screen.minY - topH,
                                        width: obstacleWidth, height: max(0, topH))

            // Bottom wall: from gapBottom to screen.maxY
            let bottomH = screen.maxY - gapBottom
            obs.bottomLayer.frame = CGRect(x: obs.x,
                                           y: 0,
                                           width: obstacleWidth, height: max(0, bottomH))

            // Gap indicators (thin lines at gap edges)
            obs.gapTopIndicator.frame = CGRect(x: obs.x - 2,
                                               y: screenH - obs.gapY - 2,
                                               width: obstacleWidth + 4, height: 2)
            obs.gapBottomIndicator.frame = CGRect(x: obs.x - 2,
                                                  y: screenH - gapBottom,
                                                  width: obstacleWidth + 4, height: 2)
        }

        // Border sync
        if settings.glow, let border = borderRef {
            border.show(around: bounds)
        } else {
            borderRef?.hide()
        }

        CATransaction.commit()
    }

    // MARK: - Helpers

    private func spawnObstacle(at x: CGFloat, screen: CGRect, pipSize: CGSize) {
        guard let rootLayer = overlayLayer else { return }

        let gapHeight = pipSize.height + 80
        let minGapY = screen.minY + 60
        let maxGapY = screen.maxY - gapHeight - 60
        let gapY = CGFloat.random(in: minGapY...max(minGapY, maxGapY))

        // Top wall layer
        let topLayer = CALayer()
        topLayer.backgroundColor = obstacleColor
        topLayer.borderColor = obstacleBorderColor
        topLayer.borderWidth = 1
        topLayer.cornerRadius = 3
        rootLayer.addSublayer(topLayer)

        // Bottom wall layer
        let bottomLayer = CALayer()
        bottomLayer.backgroundColor = obstacleColor
        bottomLayer.borderColor = obstacleBorderColor
        bottomLayer.borderWidth = 1
        bottomLayer.cornerRadius = 3
        rootLayer.addSublayer(bottomLayer)

        // Gap edge indicators
        let gapTopInd = CALayer()
        gapTopInd.backgroundColor = gapIndicatorColor
        rootLayer.addSublayer(gapTopInd)

        let gapBottomInd = CALayer()
        gapBottomInd.backgroundColor = gapIndicatorColor
        rootLayer.addSublayer(gapBottomInd)

        obstacles.append(Obstacle(
            topLayer: topLayer,
            bottomLayer: bottomLayer,
            gapTopIndicator: gapTopInd,
            gapBottomIndicator: gapBottomInd,
            x: x,
            gapY: gapY,
            gapHeight: gapHeight,
            scored: false
        ))
    }

    private func triggerGameOver(now: UInt64) {
        gameOver = true
        gameEndMach = now
        scoreLabel?.stringValue = "GAME OVER \(score)"
        print("Runner game over: score=\(score)")
    }
}
