import Cocoa
import ApplicationServices

let snake = SnakeGame()

class SnakeGame: MiniGame {
    var active = false
    var lastBounds = CGRect.zero

    // Movement
    private let snakeSpeed: CGFloat = 150.0
    private var headPos = CGPoint.zero

    // Tail
    private var tailSegments: [NSWindow] = []
    private var positionHistory: [CGPoint] = []
    private let segmentSize: CGFloat = 20
    private let segmentSpacing = 15  // samples between each segment

    // Food
    private var foodWindow: NSWindow?
    private let foodSize: CGFloat = 10
    private var foodPos = CGPoint.zero

    // Score
    private var score = 0
    private var scoreOverlay: NSWindow?
    private var scoreLabel: NSTextField?

    // Game state
    private var gameOver = false
    private var gameOverMach: UInt64 = 0

    // Timer & cached refs
    private var gameTimer: DispatchSourceTimer?
    private var cachedAXWindow: AXUIElement?
    private var cachedPipSize = CGSize.zero
    private var borderRef: RGBBorder?
    private var lastMach: UInt64 = 0

    // Colors
    private let tailColor = NSColor(red: 0.0, green: 0.3, blue: 0.15, alpha: 0.9)
    private let tailBorderColor = NSColor(red: 0.0, green: 0.4, blue: 0.2, alpha: 1.0)
    private let foodColor = NSColor(red: 0.0, green: 0.8, blue: 0.3, alpha: 1.0)

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
        gameOver = false
        positionHistory = []
        tailSegments = []
        headPos = CGPoint(x: screen.midX - pip.bounds.size.width / 2,
                          y: screen.midY - pip.bounds.size.height / 2)

        cachedAXWindow = pip.axWindow
        cachedPipSize = pip.bounds.size
        borderRef = border
        lastMach = mach_absolute_time()

        // Move PiP to center
        var initPos = headPos
        if let val = AXValueCreate(.cgPoint, &initPos) {
            AXUIElementSetAttributeValue(pip.axWindow, kAXPositionAttribute as CFString, val)
        }

        if Thread.isMainThread {
            createOverlays(screen: screen)
        } else {
            DispatchQueue.main.sync { self.createOverlays(screen: screen) }
        }

        // Spawn initial food
        spawnFood(screen: screen)

        active = true
        print("Snake started")

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

        let sw = scoreOverlay
        let fw = foodWindow
        let segs = tailSegments
        let cleanup = {
            sw?.orderOut(nil)
            fw?.orderOut(nil)
            for s in segs { s.orderOut(nil) }
        }
        if Thread.isMainThread { cleanup() }
        else { DispatchQueue.main.async { cleanup() } }

        scoreOverlay = nil
        scoreLabel = nil
        foodWindow = nil
        tailSegments = []
        positionHistory = []
        print("Snake stopped")
    }

    // MARK: - Game Loop

    private func gameTick() {
        guard active, let axWindow = cachedAXWindow else { return }

        let screen = getScreenFrame()
        let size = cachedPipSize
        let now = mach_absolute_time()
        let dt = min(machToSeconds(now - lastMach), 0.05)
        lastMach = now

        // Game over wait
        if gameOver {
            if machToSeconds(now - gameOverMach) > 2.0 { stop() }
            return
        }

        // Get mouse position
        guard let event = CGEvent(source: nil) else { return }
        let mousePos = event.location

        // Calculate direction toward mouse
        let headCenterX = headPos.x + size.width / 2
        let headCenterY = headPos.y + size.height / 2
        let dx = mousePos.x - headCenterX
        let dy = mousePos.y - headCenterY
        let dist = sqrt(dx * dx + dy * dy)

        // Move head toward mouse (only if mouse is far enough away to have meaningful direction)
        if dist > 2.0 {
            let nx = dx / dist
            let ny = dy / dist
            headPos.x += nx * snakeSpeed * dt
            headPos.y += ny * snakeSpeed * dt
        }

        // Record position history
        positionHistory.append(headPos)

        // Trim history to prevent unbounded growth (keep enough for all segments + buffer)
        let maxNeeded = (tailSegments.count + 2) * segmentSpacing + 10
        if positionHistory.count > maxNeeded * 2 {
            positionHistory.removeFirst(positionHistory.count - maxNeeded)
        }

        // Wall collision
        if headPos.x < screen.minX || headPos.y < screen.minY ||
           headPos.x + size.width > screen.maxX || headPos.y + size.height > screen.maxY {
            triggerGameOver()
            return
        }

        // Food collision (check overlap between PiP and food)
        let headRect = CGRect(origin: headPos, size: size)
        let foodRect = CGRect(x: foodPos.x, y: foodPos.y, width: foodSize, height: foodSize)
        if headRect.intersects(foodRect) {
            score += 1
            addTailSegment()
            spawnFood(screen: screen)
        }

        // Self collision (head vs tail segment positions with forgiveness inset)
        for i in 0..<tailSegments.count {
            let historyIndex = (i + 1) * segmentSpacing
            if historyIndex >= positionHistory.count { break }
            let segIdx = positionHistory.count - 1 - historyIndex
            if segIdx < 0 { break }
            let segPos = positionHistory[segIdx]
            // Segment is centered on PiP center of the recorded position
            let segCX = segPos.x + cachedPipSize.width / 2
            let segCY = segPos.y + cachedPipSize.height / 2
            let inset: CGFloat = 4
            let segRect = CGRect(x: segCX - segmentSize / 2 + inset,
                                 y: segCY - segmentSize / 2 + inset,
                                 width: segmentSize - inset * 2,
                                 height: segmentSize - inset * 2)
            if headRect.insetBy(dx: 4, dy: 4).intersects(segRect) {
                triggerGameOver()
                return
            }
        }

        // Move PiP via AX
        var newPos = headPos
        if let val = AXValueCreate(.cgPoint, &newPos) {
            let err = AXUIElementSetAttributeValue(axWindow, kAXPositionAttribute as CFString, val)
            if err != .success {
                stop()
                return
            }
        }

        let bounds = CGRect(origin: headPos, size: size)
        lastBounds = bounds

        // Update visuals
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        updateTailPositions()
        updateFoodWindow()
        updateScore()

        if settings.glow, let border = borderRef {
            border.show(around: bounds)
        } else {
            borderRef?.hide()
        }

        CATransaction.commit()
    }

    // MARK: - Game Over

    private func triggerGameOver() {
        gameOver = true
        gameOverMach = mach_absolute_time()
        scoreLabel?.stringValue = "Game Over  \(score)"
        print("Snake game over: score=\(score)")
    }

    // MARK: - Tail

    private func addTailSegment() {
        let screenH = (NSScreen.main ?? NSScreen.screens[0]).frame.height
        let w = NSWindow(contentRect: NSRect(x: -100, y: screenH + 100,
                                              width: segmentSize, height: segmentSize),
                         styleMask: .borderless, backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.level = .floating
        w.ignoresMouseEvents = true
        w.hasShadow = false
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .transient, .ignoresCycle]
        w.contentView!.wantsLayer = true
        w.contentView!.layer!.backgroundColor = tailColor.cgColor
        w.contentView!.layer!.borderColor = tailBorderColor.cgColor
        w.contentView!.layer!.borderWidth = 1
        w.contentView!.layer!.cornerRadius = 3
        w.orderFrontRegardless()
        tailSegments.append(w)
    }

    private func updateTailPositions() {
        let screenH = (NSScreen.main ?? NSScreen.screens[0]).frame.height

        for i in 0..<tailSegments.count {
            let historyIndex = (i + 1) * segmentSpacing
            if historyIndex >= positionHistory.count {
                // Not enough history yet, hide off-screen
                tailSegments[i].setFrameOrigin(NSPoint(x: -100, y: screenH + 100))
                continue
            }
            let segIdx = positionHistory.count - 1 - historyIndex
            if segIdx < 0 {
                tailSegments[i].setFrameOrigin(NSPoint(x: -100, y: screenH + 100))
                continue
            }
            let pos = positionHistory[segIdx]
            // Center the segment on the head's recorded position (offset to center of PiP)
            let cx = pos.x + cachedPipSize.width / 2 - segmentSize / 2
            let cy = pos.y + cachedPipSize.height / 2 - segmentSize / 2
            // Convert AX coords to NS coords
            let nsY = screenH - cy - segmentSize
            tailSegments[i].setFrameOrigin(NSPoint(x: cx, y: nsY))
        }
    }

    // MARK: - Food

    private func spawnFood(screen: CGRect) {
        let margin: CGFloat = 40
        let x = CGFloat.random(in: (screen.minX + margin)...(screen.maxX - margin - foodSize))
        let y = CGFloat.random(in: (screen.minY + margin)...(screen.maxY - margin - foodSize))
        foodPos = CGPoint(x: x, y: y)
    }

    private func updateFoodWindow() {
        guard let fw = foodWindow else { return }
        let screenH = (NSScreen.main ?? NSScreen.screens[0]).frame.height
        let nsY = screenH - foodPos.y - foodSize
        fw.setFrameOrigin(NSPoint(x: foodPos.x, y: nsY))
    }

    // MARK: - Overlays

    private func createOverlays(screen: CGRect) {
        let screenH = (NSScreen.main ?? NSScreen.screens[0]).frame.height

        // Food window
        let fw = NSWindow(contentRect: NSRect(x: 0, y: 0, width: foodSize, height: foodSize),
                          styleMask: .borderless, backing: .buffered, defer: false)
        fw.isOpaque = false
        fw.backgroundColor = .clear
        fw.level = .floating
        fw.ignoresMouseEvents = true
        fw.hasShadow = false
        fw.collectionBehavior = [.canJoinAllSpaces, .stationary, .transient, .ignoresCycle]
        fw.contentView!.wantsLayer = true
        fw.contentView!.layer!.backgroundColor = foodColor.cgColor
        fw.contentView!.layer!.cornerRadius = foodSize / 2
        fw.orderFrontRegardless()
        foodWindow = fw

        // Score overlay
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
        if !gameOver {
            scoreLabel?.stringValue = "\(score)"
        }
    }
}
