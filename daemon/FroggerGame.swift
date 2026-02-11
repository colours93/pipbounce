import Cocoa
import ApplicationServices

let frogger = FroggerGame()

class FroggerGame: MiniGame {
    var active = false
    var lastBounds = CGRect.zero

    // Lane layout
    private let laneCount = 8          // 0 = safe start, 1-6 = traffic, 7 = safe goal
    private var laneHeight: CGFloat = 0
    private var currentLane = 0

    // Frog position (AX coords)
    private var frogX: CGFloat = 0
    private var frogY: CGFloat = 0
    private var hopTarget: CGFloat? = nil
    private let hopDuration: CGFloat = 0.15
    private var hopElapsed: CGFloat = 0
    private var hopStart: CGFloat = 0

    // Cars
    private struct Car {
        let layer: CALayer
        var x: CGFloat         // AX coords
        let y: CGFloat         // AX coords (fixed per lane)
        let width: CGFloat
        let height: CGFloat = 16
        let speed: CGFloat     // pixels/sec, negative = left, positive = right
        let lane: Int
    }
    private var cars: [Car] = []
    private let carHeight: CGFloat = 16
    private var baseCarSpeed: CGFloat = 120
    private let speedIncrement: CGFloat = 15

    // Scoring
    private var score = 0
    private var scoreOverlay: NSWindow?
    private var scoreLabel: NSTextField?

    // Game state
    private var gameOver = false
    private var gameOverMach: UInt64 = 0

    // Input
    private var wasMouseDown = false

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
    private var screenFrame = CGRect.zero

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

    // Car colors -- dark terminal aesthetic
    private let carColors: [NSColor] = [
        NSColor(red: 0.50, green: 0.08, blue: 0.08, alpha: 1),   // dark red
        NSColor(red: 0.30, green: 0.30, blue: 0.30, alpha: 1),   // dark gray
        NSColor(red: 0.45, green: 0.12, blue: 0.12, alpha: 1),   // muted red
        NSColor(red: 0.25, green: 0.22, blue: 0.22, alpha: 1),   // charcoal
        NSColor(red: 0.40, green: 0.15, blue: 0.10, alpha: 1),   // rust
        NSColor(red: 0.20, green: 0.20, blue: 0.25, alpha: 1),   // slate
    ]

    // MARK: - MiniGame Protocol

    func start(screen: CGRect, pip: PipWindowInfo, border: RGBBorder) {
        score = 0
        gameOver = false
        wasMouseDown = false
        currentLane = 0
        cars = []
        hopTarget = nil
        hopElapsed = 0

        cachedAXWindow = pip.axWindow
        cachedPipSize = pip.bounds.size
        borderRef = border
        screenH = (NSScreen.main ?? NSScreen.screens[0]).frame.height
        screenFrame = screen
        lastMach = mach_absolute_time()

        laneHeight = screen.height / CGFloat(laneCount)

        // Frog starts at bottom center (safe zone, lane 0)
        frogX = screen.midX - cachedPipSize.width / 2
        frogY = laneYForLane(0)

        // Move PiP to start position
        var initPos = CGPoint(x: frogX, y: frogY)
        if let val = AXValueCreate(.cgPoint, &initPos) {
            AXUIElementSetAttributeValue(pip.axWindow, kAXPositionAttribute as CFString, val)
        }

        if Thread.isMainThread {
            createOverlays(screen: screen)
        } else {
            DispatchQueue.main.sync { self.createOverlays(screen: screen) }
        }

        spawnAllCars(screen: screen)

        active = true
        print("Frogger started")

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
        cars = []
        print("Frogger stopped")
    }

    // MARK: - Overlay Creation

    private func createOverlays(screen: CGRect) {
        // Full-screen game overlay for car layers
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

    // MARK: - Lane Helpers

    /// Returns the AX y-coordinate for the center of a lane (frog top-left y)
    private func laneYForLane(_ lane: Int) -> CGFloat {
        // Lane 0 is at the bottom of the screen, lane 7 is at the top
        // AX coords: y=0 is top of screen, y increases downward
        let screen = screenFrame
        let bottomY = screen.maxY - cachedPipSize.height - 10
        let topY = screen.minY + 10
        let totalTravel = bottomY - topY
        let step = totalTravel / CGFloat(laneCount - 1)
        return bottomY - CGFloat(lane) * step
    }

    /// Returns the AX y-coordinate for the center of a traffic lane (for cars)
    private func laneCenterY(_ lane: Int) -> CGFloat {
        return laneYForLane(lane) + cachedPipSize.height / 2 - carHeight / 2
    }

    // MARK: - Car Spawning

    private func spawnAllCars(screen: CGRect) {
        guard let rootLayer = overlayLayer else { return }

        // Traffic lanes are 1 through 6
        for lane in 1...6 {
            let direction: CGFloat = lane % 2 == 0 ? 1 : -1
            let speedMultiplier = 0.7 + CGFloat(lane) * 0.15
            let speed = baseCarSpeed * speedMultiplier * direction

            // Spawn 3-5 cars per lane, spread across the screen width
            let carCount = Int.random(in: 3...5)
            let spacing = screen.width / CGFloat(carCount)

            for i in 0..<carCount {
                let carWidth = CGFloat.random(in: 32...64)
                let x = screen.minX + CGFloat(i) * spacing + CGFloat.random(in: -20...20)
                let y = laneCenterY(lane)
                let color = carColors[Int.random(in: 0..<carColors.count)]

                let layer = CALayer()
                layer.backgroundColor = color.cgColor
                layer.cornerRadius = 3
                // Position in NSWindow coords (y-up)
                layer.frame = CGRect(x: x, y: screenH - y - carHeight, width: carWidth, height: carHeight)
                rootLayer.addSublayer(layer)

                cars.append(Car(layer: layer, x: x, y: y,
                                width: carWidth, speed: speed, lane: lane))
            }
        }
    }

    // MARK: - Game Loop

    private func gameTick() {
        guard active, let axWindow = cachedAXWindow else { return }

        let screen = getScreenFrame()
        screenFrame = screen
        let size = cachedPipSize
        let now = mach_absolute_time()
        let dt = min(machToSeconds(now - lastMach), 0.05)
        lastMach = now

        // End screen
        if gameOver {
            if machToSeconds(now - gameOverMach) > 2.0 { stop() }
            return
        }

        // --- Input ---
        let mouseDown = NSEvent.pressedMouseButtons & 1 != 0
        if mouseDown && !wasMouseDown && hopTarget == nil {
            // Hop forward one lane
            if currentLane < laneCount - 1 {
                currentLane += 1
                hopStart = frogY
                hopTarget = laneYForLane(currentLane)
                hopElapsed = 0
            }
        }
        wasMouseDown = mouseDown

        // --- Hop animation ---
        if let target = hopTarget {
            hopElapsed += dt
            let t = min(hopElapsed / hopDuration, 1.0)
            // Smooth ease-out
            let eased = 1.0 - (1.0 - t) * (1.0 - t)
            frogY = hopStart + (target - hopStart) * eased
            if t >= 1.0 {
                frogY = target
                hopTarget = nil

                // Check if frog reached the goal (top lane)
                if currentLane >= laneCount - 1 {
                    score += 1
                    scoreLabel?.stringValue = "\(score)"
                    // Speed up cars slightly
                    baseCarSpeed += speedIncrement
                    // Reset frog to bottom
                    currentLane = 0
                    frogY = laneYForLane(0)
                    print("Frogger score: \(score)")
                }
            }
        }

        // --- Move cars ---
        for i in 0..<cars.count {
            cars[i].x += cars[i].speed * dt

            // Wrap around screen edges
            if cars[i].speed > 0 && cars[i].x > screen.maxX + 20 {
                cars[i].x = screen.minX - cars[i].width - 20
            } else if cars[i].speed < 0 && cars[i].x + cars[i].width < screen.minX - 20 {
                cars[i].x = screen.maxX + 20
            }
        }

        // --- Collision detection ---
        let frogRect = CGRect(x: frogX + 4, y: frogY + 4,
                              width: size.width - 8, height: size.height - 8)
        for car in cars {
            let carRect = CGRect(x: car.x, y: car.y, width: car.width, height: carHeight)
            if frogRect.intersects(carRect) {
                triggerGameOver(now: now)
                break
            }
        }

        // --- Move PiP ---
        var newPos = CGPoint(x: frogX, y: frogY)
        if let val = AXValueCreate(.cgPoint, &newPos) {
            let err = AXUIElementSetAttributeValue(axWindow, kAXPositionAttribute as CFString, val)
            if err != .success {
                stop()
                return
            }
        }

        // --- Update visuals ---
        let bounds = CGRect(origin: CGPoint(x: frogX, y: frogY), size: size)
        lastBounds = bounds

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        // Update car layer positions
        for car in cars {
            car.layer.frame = CGRect(x: car.x, y: screenH - car.y - carHeight,
                                     width: car.width, height: carHeight)
        }

        // Border
        if settings.glow, let border = borderRef {
            border.show(around: bounds)
        } else {
            borderRef?.hide()
        }

        CATransaction.commit()
    }

    // MARK: - Game Over

    private func triggerGameOver(now: UInt64) {
        gameOver = true
        gameOverMach = now
        scoreLabel?.stringValue = "GAME OVER \(score)"
        print("Frogger game over: score=\(score)")
    }
}
