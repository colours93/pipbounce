import Cocoa
import ApplicationServices

let flappy = FlappyGame()

class FlappyGame: MiniGame {
    var active = false
    var lastBounds = CGRect.zero

    // Physics
    private var velocity: CGFloat = 0
    private let gravity: CGFloat = 900
    private let flapImpulse: CGFloat = -360
    private let maxFallSpeed: CGFloat = 700

    // Bird position (AX coords)
    private var birdX: CGFloat = 0
    private var birdY: CGFloat = 0

    // Pipes
    private struct PipePair {
        let topWindow: NSWindow
        let bottomWindow: NSWindow
        var x: CGFloat
        let gapCenterY: CGFloat
        var scored: Bool
    }
    private var pipes: [PipePair] = []
    private let pipeBodyWidth: CGFloat = 56
    private let pipeCapWidth: CGFloat = 70
    private let pipeCapHeight: CGFloat = 28
    private var pipeGap: CGFloat = 200
    private var pipeInterval: CGFloat = 260
    private let scrollSpeed: CGFloat = 200

    // Pipe colors
    private let pipeBodyGreen = NSColor(red: 0.45, green: 0.78, blue: 0.18, alpha: 1)
    private let pipeCapGreen = NSColor(red: 0.32, green: 0.58, blue: 0.12, alpha: 1)
    private let pipeCapBorder = NSColor(red: 0.20, green: 0.40, blue: 0.08, alpha: 1)
    private let pipeHighlight = NSColor(red: 0.58, green: 0.88, blue: 0.30, alpha: 1)
    private let pipeShadow = NSColor(red: 0.28, green: 0.48, blue: 0.10, alpha: 1)

    // Scoring
    private var score = 0
    private var bestScore = 0
    private var scoreOverlay: NSWindow?
    private var scoreLabel: NSTextField?

    // Input
    private var wasMouseDown = false

    // Wobble (border glow only — can't rotate Chrome's window)
    private var tiltAngle: CGFloat = 0

    // Timer & cached refs
    private var gameTimer: DispatchSourceTimer?
    private var cachedAXWindow: AXUIElement?
    private var cachedPipSize = CGSize.zero
    private var borderRef: RGBBorder?
    private var lastMach: UInt64 = 0

    // Game state
    private var gameOver = false
    private var gameOverMach: UInt64 = 0
    private var started = false

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

    // MARK: - MiniGame Protocol

    func start(screen: CGRect, pip: PipWindowInfo, border: RGBBorder) {
        score = 0
        velocity = 0
        gameOver = false
        started = false
        tiltAngle = 0
        wasMouseDown = false
        pipes = []

        cachedAXWindow = pip.axWindow
        borderRef = border
        lastMach = mach_absolute_time()

        // Shrink PiP to a small bird size
        var smallSize = CGSize(width: 200, height: 112)
        if let val = AXValueCreate(.cgSize, &smallSize) {
            AXUIElementSetAttributeValue(pip.axWindow, kAXSizeAttribute as CFString, val)
        }
        var sizeRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(pip.axWindow, kAXSizeAttribute as CFString, &sizeRef) == .success {
            var actualSize = CGSize.zero
            AXValueGetValue(sizeRef as! AXValue, .cgSize, &actualSize)
            cachedPipSize = actualSize
        } else {
            cachedPipSize = pip.bounds.size
        }

        border.rotationPadding = max(cachedPipSize.width, cachedPipSize.height) * 0.5
        pipeGap = cachedPipSize.height + 160
        pipeInterval = cachedPipSize.width + 250

        birdX = screen.width * 0.22
        birdY = screen.midY - cachedPipSize.height / 2

        // Move PiP to initial position
        var initPos = CGPoint(x: birdX, y: birdY)
        if let val = AXValueCreate(.cgPoint, &initPos) {
            AXUIElementSetAttributeValue(pip.axWindow, kAXPositionAttribute as CFString, val)
        }

        if Thread.isMainThread {
            createScoreOverlay(screen: screen)
        } else {
            DispatchQueue.main.sync { self.createScoreOverlay(screen: screen) }
        }

        active = true
        print("Flappy started")

        let t = DispatchSource.makeTimerSource(flags: .strict, queue: .main)
        t.schedule(deadline: .now(), repeating: .milliseconds(4), leeway: .microseconds(200))
        t.setEventHandler { [weak self] in self?.gameTick() }
        gameTimer = t
        t.resume()
    }

    func stop() {
        gameTimer?.cancel()
        gameTimer = nil
        active = false
        started = false

        // Move PiP back to bottom-right
        if let axWindow = cachedAXWindow {
            let screen = getScreenFrame()
            var restorePos = CGPoint(x: screen.maxX - cachedPipSize.width - 20,
                                     y: screen.maxY - cachedPipSize.height - 20)
            if let val = AXValueCreate(.cgPoint, &restorePos) {
                AXUIElementSetAttributeValue(axWindow, kAXPositionAttribute as CFString, val)
            }
        }
        cachedAXWindow = nil

        borderRef?.tilt(0)
        borderRef?.rotationPadding = 0
        borderRef?.hide()
        borderRef = nil

        let sw = scoreOverlay
        let pipeList = pipes
        let doCleanup = {
            sw?.orderOut(nil)
            for p in pipeList {
                p.topWindow.orderOut(nil)
                p.bottomWindow.orderOut(nil)
            }
        }
        if Thread.isMainThread { doCleanup() }
        else { DispatchQueue.main.async { doCleanup() } }

        pipes = []
        scoreOverlay = nil
        scoreLabel = nil
        print("Flappy stopped")
    }

    // MARK: - Game Loop

    private func gameTick() {
        guard active else { return }

        let screen = getScreenFrame()
        let size = cachedPipSize
        let now = mach_absolute_time()
        let dt = min(machToSeconds(now - lastMach), 0.05)
        lastMach = now

        if gameOver {
            if machToSeconds(now - gameOverMach) > 2.0 { stop() }
            return
        }

        // Input
        let mouseDown = NSEvent.pressedMouseButtons & 1 != 0
        if mouseDown && !wasMouseDown { flap() }
        wasMouseDown = mouseDown

        // Physics
        if started {
            velocity += gravity * dt
            velocity = min(velocity, maxFallSpeed)
            birdY += velocity * dt
        } else {
            let bob = sin(Double(now) / 200_000_000.0) * 4
            birdY = screen.midY - size.height / 2 + CGFloat(bob)
        }

        // Wobble tilt (border glow only)
        if started {
            let targetTilt = velocity / 800.0
            let clampedTilt = max(-0.3, min(0.6, targetTilt))
            tiltAngle += (clampedTilt - tiltAngle) * 0.06
        } else {
            tiltAngle = 0
        }

        // Scroll pipes
        if started {
            for i in 0..<pipes.count { pipes[i].x -= scrollSpeed * dt }
        }

        // Spawn pipes
        let lastPipeX = pipes.last?.x ?? -1000
        if started && (pipes.isEmpty || lastPipeX < screen.maxX - pipeInterval) {
            spawnPipe(screen: screen)
        }

        // Remove off-screen pipes
        let removeList = pipes.filter { $0.x + pipeCapWidth < -20 }
        pipes.removeAll { pair in pair.x + pipeCapWidth < -20 }
        for p in removeList {
            p.topWindow.orderOut(nil)
            p.bottomWindow.orderOut(nil)
        }

        // Scoring
        for i in 0..<pipes.count {
            if !pipes[i].scored && pipes[i].x + pipeBodyWidth / 2 < birdX {
                pipes[i].scored = true
                score += 1
                updateScore()
            }
        }

        // Collision: floor / ceiling
        if started && (birdY < screen.minY || birdY + size.height > screen.maxY) {
            birdY = max(screen.minY, min(screen.maxY - size.height, birdY))
            triggerGameOver()
            return
        }

        // Collision: pipes
        if started {
            let birdRect = CGRect(x: birdX + 4, y: birdY + 4,
                                  width: size.width - 8, height: size.height - 8)
            for pair in pipes {
                let capExtra = (pipeCapWidth - pipeBodyWidth) / 2
                let topH = pair.gapCenterY - pipeGap / 2
                let bottomY = pair.gapCenterY + pipeGap / 2
                let bottomH = screen.maxY - bottomY

                let topBody = CGRect(x: pair.x, y: 0, width: pipeBodyWidth, height: topH - pipeCapHeight)
                let topCap = CGRect(x: pair.x - capExtra, y: topH - pipeCapHeight,
                                    width: pipeCapWidth, height: pipeCapHeight)
                let bottomCap = CGRect(x: pair.x - capExtra, y: bottomY,
                                       width: pipeCapWidth, height: pipeCapHeight)
                let bottomBody = CGRect(x: pair.x, y: bottomY + pipeCapHeight,
                                        width: pipeBodyWidth, height: bottomH - pipeCapHeight)

                if birdRect.intersects(topBody) || birdRect.intersects(topCap) ||
                   birdRect.intersects(bottomCap) || birdRect.intersects(bottomBody) {
                    triggerGameOver()
                    return
                }
            }
        }

        let bounds = CGRect(x: birdX, y: birdY, width: size.width, height: size.height)
        lastBounds = bounds

        // Update visuals
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        // Move real PiP directly — video keeps playing
        if let axWindow = cachedAXWindow {
            var pos = CGPoint(x: birdX, y: birdY)
            if let val = AXValueCreate(.cgPoint, &pos) {
                AXUIElementSetAttributeValue(axWindow, kAXPositionAttribute as CFString, val)
            }
        }

        updatePipeWindows(screen: screen)

        if settings.glow, let border = borderRef {
            border.show(around: bounds)
            border.tilt(tiltAngle)
        }

        CATransaction.commit()
    }

    // MARK: - Actions

    private func flap() {
        if !started { started = true }
        velocity = flapImpulse
    }

    private func triggerGameOver() {
        gameOver = true
        gameOverMach = mach_absolute_time()
        if score > bestScore { bestScore = score }
        scoreLabel?.stringValue = "Game Over  \(score)"
        print("Flappy game over: score=\(score) best=\(bestScore)")
    }

    // MARK: - Pipe Creation

    private func spawnPipe(screen: CGRect) {
        let minGapY = screen.minY + pipeGap / 2 + 60
        let maxGapY = screen.maxY - pipeGap / 2 - 60
        let gapY = CGFloat.random(in: minGapY...maxGapY)
        let x = screen.maxX + 20

        let topW = makePipeWindow(screen: screen, isTop: true, x: x, gapCenterY: gapY)
        let botW = makePipeWindow(screen: screen, isTop: false, x: x, gapCenterY: gapY)

        pipes.append(PipePair(topWindow: topW, bottomWindow: botW,
                              x: x, gapCenterY: gapY, scored: false))
    }

    private func makePipeWindow(screen: CGRect, isTop: Bool, x: CGFloat, gapCenterY: CGFloat) -> NSWindow {
        let screenH = (NSScreen.main ?? NSScreen.screens[0]).frame.height
        let capExtra = (pipeCapWidth - pipeBodyWidth) / 2

        let pipeH: CGFloat
        let nsY: CGFloat
        if isTop {
            pipeH = gapCenterY - pipeGap / 2
            nsY = screenH - pipeH
        } else {
            let gapBottom = gapCenterY + pipeGap / 2
            pipeH = screen.maxY - gapBottom
            nsY = 0
        }

        let w = NSWindow(contentRect: NSRect(x: x - capExtra, y: nsY,
                                              width: pipeCapWidth, height: max(pipeH, 1)),
                         styleMask: .borderless, backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.level = .floating
        w.ignoresMouseEvents = true
        w.hasShadow = false
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .transient, .ignoresCycle]
        w.contentView!.wantsLayer = true

        buildPipeLayers(in: w, height: pipeH, isTop: isTop)
        w.orderFrontRegardless()
        return w
    }

    private func buildPipeLayers(in window: NSWindow, height: CGFloat, isTop: Bool) {
        guard let layer = window.contentView?.layer else { return }
        let capExtra = (pipeCapWidth - pipeBodyWidth) / 2

        let bodyH = max(height - pipeCapHeight, 0)
        let bodyY: CGFloat = isTop ? pipeCapHeight : 0
        let bodyLayer = CALayer()
        bodyLayer.frame = NSRect(x: capExtra, y: bodyY, width: pipeBodyWidth, height: bodyH)
        bodyLayer.backgroundColor = pipeBodyGreen.cgColor
        bodyLayer.borderWidth = 2
        bodyLayer.borderColor = pipeCapBorder.cgColor

        let hl = CALayer()
        hl.frame = NSRect(x: 4, y: 0, width: 6, height: bodyH)
        hl.backgroundColor = pipeHighlight.cgColor
        hl.cornerRadius = 2
        bodyLayer.addSublayer(hl)

        let sl = CALayer()
        sl.frame = NSRect(x: pipeBodyWidth - 10, y: 0, width: 6, height: bodyH)
        sl.backgroundColor = pipeShadow.cgColor
        sl.cornerRadius = 2
        bodyLayer.addSublayer(sl)

        let capY: CGFloat = isTop ? 0 : height - pipeCapHeight
        let capLayer = CALayer()
        capLayer.frame = NSRect(x: 0, y: capY, width: pipeCapWidth, height: pipeCapHeight)
        capLayer.backgroundColor = pipeCapGreen.cgColor
        capLayer.borderWidth = 2.5
        capLayer.borderColor = pipeCapBorder.cgColor
        capLayer.cornerRadius = 4

        let chl = CALayer()
        chl.frame = NSRect(x: 5, y: 4, width: 7, height: pipeCapHeight - 8)
        chl.backgroundColor = pipeHighlight.cgColor
        chl.cornerRadius = 3
        capLayer.addSublayer(chl)

        let csl = CALayer()
        csl.frame = NSRect(x: pipeCapWidth - 12, y: 4, width: 7, height: pipeCapHeight - 8)
        csl.backgroundColor = pipeShadow.cgColor
        csl.cornerRadius = 3
        capLayer.addSublayer(csl)

        layer.addSublayer(bodyLayer)
        layer.addSublayer(capLayer)
    }

    private func updatePipeWindows(screen: CGRect) {
        let screenH = (NSScreen.main ?? NSScreen.screens[0]).frame.height
        let capExtra = (pipeCapWidth - pipeBodyWidth) / 2

        for pair in pipes {
            let nsX = pair.x - capExtra
            let topH = pair.gapCenterY - pipeGap / 2
            pair.topWindow.setFrameOrigin(NSPoint(x: nsX, y: screenH - topH))
            pair.bottomWindow.setFrameOrigin(NSPoint(x: nsX, y: 0))
        }
    }

    // MARK: - Score

    private func createScoreOverlay(screen: CGRect) {
        let screenH = (NSScreen.main ?? NSScreen.screens[0]).frame.height
        let sw = NSWindow(contentRect: NSRect(x: screen.midX - 60, y: screenH - 55, width: 120, height: 44),
                          styleMask: .borderless, backing: .buffered, defer: false)
        sw.isOpaque = false
        sw.backgroundColor = NSColor.black.withAlphaComponent(0.6)
        sw.level = .floating
        sw.ignoresMouseEvents = true
        sw.hasShadow = false
        sw.collectionBehavior = [.canJoinAllSpaces, .stationary, .transient, .ignoresCycle]

        let label = NSTextField(frame: NSRect(x: 0, y: 0, width: 120, height: 44))
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

    private func updateScore() {
        scoreLabel?.stringValue = "\(score)"
    }
}
