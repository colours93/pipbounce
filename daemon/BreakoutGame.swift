import Cocoa
import ApplicationServices

let breakout = BreakoutGame()

class BreakoutGame: MiniGame {
    var active = false
    var lastBounds = CGRect.zero

    // Ball physics
    private var ballPos = CGPoint.zero
    private var velocity = CGPoint.zero
    private let baseSpeed: CGFloat = 350.0
    private let maxSpeed: CGFloat = 700.0
    private var launched = false

    // Paddle
    private var paddleWindow: NSWindow?
    private let paddleW: CGFloat = 120
    private let paddleH: CGFloat = 10
    private let paddleBottomMargin: CGFloat = 60
    private var paddleX: CGFloat = 0

    // Bricks
    private let brickCols = 10
    private let brickRows = 5
    private let brickW: CGFloat = 60
    private let brickH: CGFloat = 20
    private let brickSpacingX: CGFloat = 4
    private let brickSpacingY: CGFloat = 4
    private let brickTopMargin: CGFloat = 40

    private struct Brick {
        let layer: CALayer
        var alive: Bool
        let row: Int
    }
    private var bricks: [Brick] = []
    private var aliveBrickCount = 0

    // Overlay for bricks
    private var overlayWindow: NSWindow?
    private var overlayLayer: CALayer?

    // Score & lives
    private var score = 0
    private var lives = 3
    private var scoreOverlay: NSWindow?
    private var scoreLabel: NSTextField?

    // Game state
    private var gameOver = false
    private var gameWon = false
    private var gameEndMach: UInt64 = 0

    // Input
    private var wasMouseDown = false

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

    // Row colors (bottom to top): dark muted terminal aesthetic
    private let rowColors: [(bg: NSColor, border: NSColor)] = [
        (NSColor(red: 0.0, green: 0.35, blue: 0.15, alpha: 1),   // dark green
         NSColor(red: 0.0, green: 0.50, blue: 0.25, alpha: 0.6)),
        (NSColor(red: 0.0, green: 0.30, blue: 0.30, alpha: 1),   // dark teal
         NSColor(red: 0.0, green: 0.45, blue: 0.45, alpha: 0.6)),
        (NSColor(red: 0.20, green: 0.22, blue: 0.30, alpha: 1),  // dark slate
         NSColor(red: 0.30, green: 0.33, blue: 0.45, alpha: 0.6)),
        (NSColor(red: 0.30, green: 0.10, blue: 0.30, alpha: 1),  // dark purple
         NSColor(red: 0.45, green: 0.18, blue: 0.45, alpha: 0.6)),
        (NSColor(red: 0.40, green: 0.05, blue: 0.10, alpha: 1),  // dark crimson
         NSColor(red: 0.55, green: 0.12, blue: 0.18, alpha: 0.6)),
    ]

    // MARK: - MiniGame Protocol

    func start(screen: CGRect, pip: PipWindowInfo, border: RGBBorder) {
        score = 0
        lives = 3
        gameOver = false
        gameWon = false
        launched = false
        wasMouseDown = false
        bricks = []
        aliveBrickCount = 0

        cachedAXWindow = pip.axWindow
        cachedPipSize = pip.bounds.size
        borderRef = border
        screenH = (NSScreen.main ?? NSScreen.screens[0]).frame.height
        lastMach = mach_absolute_time()

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

        active = true
        print("Breakout started")

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

        let pw = paddleWindow, ow = overlayWindow, sw = scoreOverlay
        let cleanup = {
            pw?.orderOut(nil)
            ow?.orderOut(nil)
            sw?.orderOut(nil)
        }
        if Thread.isMainThread { cleanup() }
        else { DispatchQueue.main.async { cleanup() } }

        paddleWindow = nil
        overlayWindow = nil
        overlayLayer = nil
        scoreOverlay = nil
        scoreLabel = nil
        bricks = []
        print("Breakout stopped")
    }

    // MARK: - Overlay Creation

    private func createOverlays(screen: CGRect) {
        // Full-screen overlay for bricks
        let ow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: screen.width, height: screenH),
                          styleMask: .borderless, backing: .buffered, defer: false)
        ow.isOpaque = false
        ow.backgroundColor = .clear
        ow.level = .floating
        ow.ignoresMouseEvents = true
        ow.hasShadow = false
        ow.collectionBehavior = [.canJoinAllSpaces, .stationary, .transient, .ignoresCycle]
        ow.contentView!.wantsLayer = true

        let rootLayer = ow.contentView!.layer!
        overlayLayer = rootLayer

        // Compute brick grid origin to center it
        let totalGridW = CGFloat(brickCols) * brickW + CGFloat(brickCols - 1) * brickSpacingX
        let gridOriginX = (screen.width - totalGridW) / 2

        for row in 0..<brickRows {
            for col in 0..<brickCols {
                let layer = CALayer()
                let bx = gridOriginX + CGFloat(col) * (brickW + brickSpacingX)
                let by = brickTopMargin + CGFloat(row) * (brickH + brickSpacingY)
                // AX y-down -> CALayer y-up
                layer.frame = CGRect(x: bx, y: screenH - by - brickH, width: brickW, height: brickH)
                layer.backgroundColor = rowColors[row].bg.cgColor
                layer.borderColor = rowColors[row].border.cgColor
                layer.borderWidth = 1
                layer.cornerRadius = 3
                rootLayer.addSublayer(layer)
                bricks.append(Brick(layer: layer, alive: true, row: row))
                aliveBrickCount += 1
            }
        }

        ow.orderFrontRegardless()
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
        pw.contentView!.layer!.backgroundColor = NSColor(red: 0.25, green: 0.25, blue: 0.25, alpha: 1).cgColor
        pw.contentView!.layer!.borderColor = NSColor(red: 0.0, green: 0.45, blue: 0.2, alpha: 0.7).cgColor
        pw.contentView!.layer!.borderWidth = 1
        pw.contentView!.layer!.cornerRadius = paddleH / 2
        pw.orderFrontRegardless()
        paddleWindow = pw

        // Score overlay
        let sw = NSWindow(contentRect: NSRect(x: screen.midX - 100, y: screenH - 55, width: 200, height: 44),
                          styleMask: .borderless, backing: .buffered, defer: false)
        sw.isOpaque = false
        sw.backgroundColor = NSColor.black.withAlphaComponent(0.6)
        sw.level = .floating
        sw.ignoresMouseEvents = true
        sw.hasShadow = false
        sw.collectionBehavior = [.canJoinAllSpaces, .stationary, .transient, .ignoresCycle]

        let label = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 44))
        label.isEditable = false
        label.isBordered = false
        label.backgroundColor = .clear
        label.textColor = .white
        label.font = NSFont.monospacedSystemFont(ofSize: 20, weight: .bold)
        label.alignment = .center
        label.stringValue = formatScore()
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

        // End screen timeout
        if gameOver || gameWon {
            if machToSeconds(now - gameEndMach) > 2.0 { stop() }
            return
        }

        // --- Input ---
        guard let event = CGEvent(source: nil) else { return }
        let mousePos = event.location
        let mouseDown = NSEvent.pressedMouseButtons & 1 != 0

        // Paddle follows mouse X
        paddleX = max(screen.minX, min(screen.maxX - paddleW, mousePos.x - paddleW / 2))
        let paddleY = screen.maxY - paddleBottomMargin

        if !launched {
            // Ball sits on paddle
            ballPos = CGPoint(x: paddleX + paddleW / 2 - size.width / 2,
                              y: paddleY - size.height)

            // Click to launch
            if mouseDown && !wasMouseDown {
                launched = true
                let angle = CGFloat.random(in: -0.3...0.3)
                velocity = CGPoint(x: baseSpeed * sin(angle), y: -baseSpeed * cos(angle))
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
            }

            // Left wall bounce
            if ballPos.x <= screen.minX {
                ballPos.x = screen.minX
                velocity.x = abs(velocity.x)
            }

            // Right wall bounce
            if ballPos.x + size.width >= screen.maxX {
                ballPos.x = screen.maxX - size.width
                velocity.x = -abs(velocity.x)
            }

            // Paddle collision
            let ballBottom = ballPos.y + size.height
            let ballCenterX = ballPos.x + size.width / 2
            if ballBottom >= paddleY && ballBottom <= paddleY + paddleH + 8 && velocity.y > 0 {
                if ballCenterX >= paddleX && ballCenterX <= paddleX + paddleW {
                    ballPos.y = paddleY - size.height
                    // Deflection based on hit position
                    let hitNorm = (ballCenterX - paddleX) / paddleW  // 0..1
                    let deflect = (hitNorm - 0.5) * 2.0  // -1..1
                    let spd = sqrt(velocity.x * velocity.x + velocity.y * velocity.y)
                    let newSpeed = min(spd * 1.02, maxSpeed)  // slight speed increase
                    let maxAngle: CGFloat = 1.2  // ~69 degrees max from vertical
                    let angle = deflect * maxAngle
                    velocity.x = newSpeed * sin(angle)
                    velocity.y = -newSpeed * cos(angle)
                }
            }

            // Brick collisions
            let ballRect = CGRect(origin: ballPos, size: size)
            let totalGridW = CGFloat(brickCols) * brickW + CGFloat(brickCols - 1) * brickSpacingX
            let gridOriginX = (screen.width - totalGridW) / 2

            for i in 0..<bricks.count where bricks[i].alive {
                let row = i / brickCols
                let col = i % brickCols
                let bx = gridOriginX + CGFloat(col) * (brickW + brickSpacingX)
                let by = brickTopMargin + CGFloat(row) * (brickH + brickSpacingY)
                let brickRect = CGRect(x: bx, y: by, width: brickW, height: brickH)

                if ballRect.intersects(brickRect) {
                    bricks[i].alive = false
                    bricks[i].layer.isHidden = true
                    aliveBrickCount -= 1
                    score += 10

                    // Determine bounce direction based on overlap
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

                    // Win check
                    if aliveBrickCount <= 0 {
                        gameWon = true
                        gameEndMach = now
                        scoreLabel?.stringValue = "CLEARED! \(score)"
                        print("Breakout cleared: score=\(score)")
                    } else {
                        scoreLabel?.stringValue = formatScore()
                    }
                    break  // one brick per frame
                }
            }

            // Ball falls below screen
            if ballPos.y > screen.maxY + 20 {
                lives -= 1
                if lives <= 0 {
                    gameOver = true
                    gameEndMach = now
                    scoreLabel?.stringValue = "GAME OVER \(score)"
                    print("Breakout game over: score=\(score)")
                } else {
                    // Reset ball to paddle
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
        }

        // --- Move PiP ---
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

        // --- Update visuals ---
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        // Paddle position
        paddleWindow?.setFrame(
            NSRect(x: paddleX, y: screenH - paddleY - paddleH,
                   width: paddleW, height: paddleH), display: true)

        // Border
        if settings.glow, let border = borderRef {
            border.show(around: bounds)
        } else {
            borderRef?.hide()
        }

        CATransaction.commit()
    }

    // MARK: - Helpers

    private func formatScore() -> String {
        return "\(score)  \(String(repeating: "\u{2665}", count: lives))"
    }
}
