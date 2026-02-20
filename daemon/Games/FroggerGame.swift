import Cocoa
import ApplicationServices



class FroggerGame: GameBase {

    // Lane layout
    private let laneCount = 8          // 0 = safe start, 1-6 = traffic, 7 = safe goal
    private var laneHeight: CGFloat = 0
    private var currentLane = 0

    // Frog position (AX coords)
    private var frogX: CGFloat = 0
    private var frogY: CGFloat = 0
    private var hopTarget: CGFloat? = nil
    private let hopDuration: CGFloat = 0.12
    private var hopElapsed: CGFloat = 0
    private var hopStart: CGFloat = 0
    private var hopDirection: Int = 1  // 1 = forward, -1 = backward

    // Cars
    private enum VehicleType {
        case motorcycle, car, truck

        var widthRange: ClosedRange<CGFloat> {
            switch self {
            case .motorcycle: return 20...30
            case .car: return 40...60
            case .truck: return 80...100
            }
        }

        var speedMultiplier: CGFloat {
            switch self {
            case .motorcycle: return 1.6
            case .car: return 1.0
            case .truck: return 0.6
            }
        }
    }

    // MARK: - Pixel Art Sprites (see FroggerSprites.swift)

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
    private let speedIncrement: CGFloat = 20

    // Lives
    private var lives = 3
    private var deathAnimating = false
    private var deathStart: UInt64 = 0
    private let deathDuration: CGFloat = 0.3
    private var deathShakeOriginX: CGFloat = 0

    // Near-miss
    private let nearMissThreshold: CGFloat = 12
    private var nearMissPulseEnd: UInt64 = 0

    // Goal celebration
    private var goalFlashEnd: UInt64 = 0

    // Game state
    private var gameOverMach: UInt64 = 0

    // Input
    private var wasMouseDown = false
    private var wasRightDown = false

    // Overlay
    private var overlayWindow: NSWindow?
    private var overlayLayer: CALayer?
    private var laneLayers: [CALayer] = []
    private var centerLineLayers: [CALayer] = []

    private var screenFrame = CGRect.zero

    // MARK: - GameBase Hooks

    override func onStart(screen: CGRect, pip: PipWindowInfo) {
        timerIntervalMs = 8
        lives = 3
        deathAnimating = false
        wasMouseDown = false
        wasRightDown = false
        currentLane = 0
        cars = []
        laneLayers = []
        centerLineLayers = []
        hopTarget = nil
        hopElapsed = 0
        nearMissPulseEnd = 0
        goalFlashEnd = 0
        gameOverMach = 0
        baseCarSpeed = 120

        screenFrame = screen
        laneHeight = screen.height / CGFloat(laneCount)

        // Frog starts at bottom center (safe zone, lane 0)
        frogX = screen.midX - cachedPipSize.width / 2
        frogY = laneYForLane(0)

        // Move PiP to start position
        movePip(to: CGPoint(x: frogX, y: frogY))

        if Thread.isMainThread {
            createOverlays(screen: screen)
        } else {
            DispatchQueue.main.sync { self.createOverlays(screen: screen) }
        }

        spawnAllCars(screen: screen)

        print("Frogger started")
    }

    override func onStop() {
        overlayWindow?.orderOut(nil)
        overlayWindow = nil
        overlayLayer = nil
        cars = []
        laneLayers = []
        centerLineLayers = []
        print("Frogger stopped")
    }

    // MARK: - Overlay Creation

    private func createOverlays(screen: CGRect) {
        // Full-screen game overlay for car layers
        let (ow, rootLayer) = createFullscreenOverlay(screen: screen)
        overlayLayer = rootLayer
        overlayWindow = ow

        // Lane background strips
        createLaneBackgrounds(screen: screen, rootLayer: rootLayer)

        // Score overlay (wider to fit lives dots)
        createScoreOverlay(screen: screen, width: 180)
        scoreLabel?.attributedStringValue = Self.styledScore(livesString() + "0")
    }

    private func livesString() -> String {
        return String(repeating: "\u{25CF} ", count: lives)
    }

    private func createLaneBackgrounds(screen: CGRect, rootLayer: CALayer) {
        // Safe zone lane 0 (bottom) - green tint
        addLaneStrip(lane: 0, screen: screen, rootLayer: rootLayer,
                     color: NSColor(red: 0.05, green: 0.15, blue: 0.05, alpha: 0.4))

        // Traffic lanes 1-6 - dark gray
        for lane in 1...6 {
            addLaneStrip(lane: lane, screen: screen, rootLayer: rootLayer,
                         color: NSColor(red: 0.10, green: 0.10, blue: 0.10, alpha: 0.35))
        }

        // Safe zone lane 7 (top) - green tint
        addLaneStrip(lane: 7, screen: screen, rootLayer: rootLayer,
                     color: NSColor(red: 0.05, green: 0.15, blue: 0.05, alpha: 0.4))

        // Dashed center-lines between traffic lanes
        for lane in 1..<6 {
            let y1 = laneYForLane(lane)
            let y2 = laneYForLane(lane + 1)
            let midAXY = (y1 + y2) / 2
            let nsY = screenH - midAXY - 1

            let lineLayer = CAShapeLayer()
            let path = CGMutablePath()
            path.move(to: CGPoint(x: screen.minX + 10, y: nsY))
            path.addLine(to: CGPoint(x: screen.maxX - 10, y: nsY))
            lineLayer.path = path
            lineLayer.strokeColor = NSColor(white: 0.3, alpha: 0.5).cgColor
            lineLayer.lineWidth = 1
            lineLayer.lineDashPattern = [8, 12]
            lineLayer.fillColor = nil
            rootLayer.addSublayer(lineLayer)
            centerLineLayers.append(lineLayer)
        }
    }

    private func addLaneStrip(lane: Int, screen: CGRect, rootLayer: CALayer, color: NSColor) {
        let axY = laneYForLane(lane)
        let stripHeight = cachedPipSize.height + 10
        let nsY = screenH - axY - stripHeight

        let layer = CALayer()
        layer.backgroundColor = color.cgColor
        layer.frame = CGRect(x: screen.minX, y: nsY, width: screen.width, height: stripHeight)
        rootLayer.addSublayer(layer)
        laneLayers.append(layer)
    }

    // MARK: - Lane Helpers

    private func laneYForLane(_ lane: Int) -> CGFloat {
        let screen = screenFrame
        let bottomY = screen.maxY - cachedPipSize.height - 10
        let topY = screen.minY + 10
        let totalTravel = bottomY - topY
        let step = totalTravel / CGFloat(laneCount - 1)
        return bottomY - CGFloat(lane) * step
    }

    private func laneCenterY(_ lane: Int) -> CGFloat {
        return laneYForLane(lane) + cachedPipSize.height / 2 - carHeight / 2
    }

    // MARK: - Car Spawning

    private func spawnAllCars(screen: CGRect) {
        guard let rootLayer = overlayLayer else { return }

        for lane in 1...6 {
            let direction: CGFloat = lane % 2 == 0 ? 1 : -1
            let laneSpeedBase = 0.7 + CGFloat(lane) * 0.15

            let carCount = Int.random(in: 3...5)
            let spacing = screen.width / CGFloat(carCount)

            for i in 0..<carCount {
                let type: VehicleType = [.motorcycle, .car, .car, .truck].randomElement()!
                let carWidth = CGFloat.random(in: type.widthRange)
                let speed = baseCarSpeed * laneSpeedBase * type.speedMultiplier * direction
                let x = screen.minX + CGFloat(i) * spacing + CGFloat.random(in: -20...20)
                let y = laneCenterY(lane)
                let goesRight = direction > 0

                // Pick a random sprite for this vehicle type
                let sprite: CGImage?
                switch type {
                case .motorcycle: sprite = FroggerSprites.motorcycles.randomElement()!
                case .car:        sprite = FroggerSprites.cars.randomElement()!
                case .truck:      sprite = FroggerSprites.trucks.randomElement()!
                }

                let layer = CALayer()
                layer.contents = sprite
                layer.magnificationFilter = .nearest
                layer.minificationFilter = .nearest
                layer.contentsGravity = .resizeAspectFill

                // Flip sprite horizontally when going left
                if !goesRight {
                    layer.transform = CATransform3DMakeScale(-1, 1, 1)
                }

                layer.frame = CGRect(x: x, y: screenH - y - carHeight, width: carWidth, height: carHeight)
                rootLayer.addSublayer(layer)

                cars.append(Car(layer: layer, x: x, y: y,
                                width: carWidth, speed: speed, lane: lane))
            }
        }
    }

    private func respawnCars() {
        // Remove old car layers
        for car in cars {
            car.layer.removeFromSuperlayer()
        }
        cars = []
        spawnAllCars(screen: screenFrame)
    }

    // MARK: - Game Loop

    override func gameTick() {
        guard active, let _ = cachedAXWindow else { return }

        let screen = getScreenFrame()
        screenFrame = screen
        let now = mach_absolute_time()
        let dt = deltaTime()

        // Refresh pip size
        refreshPipSize()
        let size = cachedPipSize

        // End screen
        if gameOver {
            if machToSeconds(now - gameOverMach) > 2.0 { stop() }
            return
        }

        // Death animation
        if deathAnimating {
            let elapsed = machToSeconds(now - deathStart)
            if elapsed >= deathDuration {
                deathAnimating = false
                frogX = deathShakeOriginX
                // Reset to lane 0
                currentLane = 0
                frogY = laneYForLane(0)
                frogX = max(screen.minX, min(frogX, screen.maxX - size.width))
            } else {
                // Horizontal shake
                let shakeAmp: CGFloat = 14
                let freq: CGFloat = 30
                frogX = deathShakeOriginX + sin(elapsed * freq) * shakeAmp
                // Move PiP during shake
                movePip(to: CGPoint(x: frogX, y: frogY))
                // Flash border red
                borderRef?.show(around: CGRect(origin: CGPoint(x: frogX, y: frogY), size: size))
                return
            }
        }

        // --- Input: mouse X tracking ---
        guard let mousePos = mousePosition() else { return }
        let axMouseX = mousePos.x
        frogX = max(screen.minX, min(axMouseX - size.width / 2, screen.maxX - size.width))

        // --- Input: left click = hop forward ---
        let mouseDown = isMouseDown
        if mouseDown && !wasMouseDown && hopTarget == nil {
            if currentLane < laneCount - 1 {
                currentLane += 1
                hopStart = frogY
                hopTarget = laneYForLane(currentLane)
                hopElapsed = 0
                hopDirection = 1
            }
        }
        wasMouseDown = mouseDown

        // --- Input: right click = hop backward ---
        let rightDown = NSEvent.pressedMouseButtons & 2 != 0
        if rightDown && !wasRightDown && hopTarget == nil {
            if currentLane > 0 {
                currentLane -= 1
                hopStart = frogY
                hopTarget = laneYForLane(currentLane)
                hopElapsed = 0
                hopDirection = -1
            }
        }
        wasRightDown = rightDown

        // --- Hop animation ---
        if let target = hopTarget {
            hopElapsed += dt
            let t = min(hopElapsed / hopDuration, 1.0)
            let eased = 1.0 - (1.0 - t) * (1.0 - t)
            frogY = hopStart + (target - hopStart) * eased
            if t >= 1.0 {
                frogY = target
                hopTarget = nil

                // Check if frog reached the goal (top lane)
                if currentLane >= laneCount - 1 {
                    score += 1
                    scoreLabel?.attributedStringValue = Self.styledScore(livesString() + "\(score)")
                    baseCarSpeed += speedIncrement
                    // Goal celebration - flash border green
                    goalFlashEnd = now + secondsToMach(0.5)
                    // Re-randomize cars
                    respawnCars()
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

            if cars[i].speed > 0 && cars[i].x > screen.maxX + 20 {
                cars[i].x = screen.minX - cars[i].width - 20
            } else if cars[i].speed < 0 && cars[i].x + cars[i].width < screen.minX - 20 {
                cars[i].x = screen.maxX + 20
            }
        }

        // --- Collision detection (only when NOT hopping) ---
        let frogRect = CGRect(x: frogX + 4, y: frogY + 4,
                              width: size.width - 8, height: size.height - 8)

        var nearMiss = false
        for car in cars {
            let carRect = CGRect(x: car.x, y: car.y, width: car.width, height: carHeight)
            if Self.rectsCollide(frogRect, carRect) {
                triggerDeath(now: now)
                break
            }
            // Near-miss detection (only when not hopping)
            if hopTarget == nil {
                let expanded = carRect.insetBy(dx: -nearMissThreshold, dy: -nearMissThreshold)
                if Self.rectsCollide(expanded, frogRect) && !Self.rectsCollide(carRect, frogRect) {
                    nearMiss = true
                }
            }
        }

        if nearMiss && nearMissPulseEnd < now {
            nearMissPulseEnd = now + secondsToMach(0.15)
        }

        // --- Move PiP ---
        movePip(to: CGPoint(x: frogX, y: frogY))

        // --- Update visuals ---
        let bounds = CGRect(origin: CGPoint(x: frogX, y: frogY), size: size)
        lastBounds = bounds

        withTransaction {
            for car in cars {
                car.layer.frame = CGRect(x: car.x, y: screenH - car.y - carHeight,
                                         width: car.width, height: carHeight)
            }

            // Border with color effects
            if settings.glow, let border = borderRef {
                if goalFlashEnd > now {
                    // Temporarily save and override glow color for green flash
                    let saved = settings.glowColor
                    settings.glowColor = "green"
                    border.show(around: bounds)
                    settings.glowColor = saved
                } else if nearMissPulseEnd > now {
                    // Near-miss flash: bright yellow pulse
                    let saved = settings.glowColor
                    settings.glowColor = "yellow"
                    border.show(around: bounds)
                    settings.glowColor = saved
                } else {
                    border.show(around: bounds)
                }
            } else {
                borderRef?.hide()
            }
        }
    }


    // MARK: - Death & Game Over

    private func triggerDeath(now: UInt64) {
        lives -= 1
        if lives <= 0 {
            state = .gameOver
            gameOverMach = now
            scoreLabel?.attributedStringValue = Self.styledMessage("GAME OVER \(score)")
            print("Frogger game over: score=\(score)")
            return
        }
        // Start death animation
        deathAnimating = true
        deathStart = now
        deathShakeOriginX = frogX
        hopTarget = nil
        scoreLabel?.attributedStringValue = Self.styledScore(livesString() + "\(score)")
        print("Frogger death: lives=\(lives)")
    }
}
