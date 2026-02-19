import Cocoa
import ApplicationServices

let frogger = FroggerGame()

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

    // MARK: - Pixel Art Sprites

    private enum Sprites {
        // ── Cyberpunk Hoverbike variants: 10x8 pixels, displayed at 2x = 20x16 ──
        // Futuristic hoverbike: sleek helmet rider, carbon fiber body, neon accent strips, thruster exhaust (no wheels)

        static let motorcyclePink: CGImage? = {
            let _ : UInt32 = 0
            let N : UInt32 = 0xFF0066  // hot pink neon
            let Nd: UInt32 = 0xCC0044  // dark pink neon
            let B : UInt32 = 0x1A1A2A  // carbon fiber body
            let D : UInt32 = 0x252535  // carbon fiber dark
            let K : UInt32 = 0x111118  // near-black (rider)
            let V : UInt32 = 0x334455  // visor tint
            let T : UInt32 = 0xFF4400  // thruster glow
            let Tb: UInt32 = 0xFF8844  // thruster bright
            let pixels: [[UInt32]] = [
                [0, 0, 0, 0, K, K, 0, 0, 0, 0],  // helmet top
                [0, 0, 0, K, V, V, K, 0, 0, 0],  // helmet + visor
                [0, 0, 0, 0, K, K, N, 0, 0, 0],  // visor + neon strip
                [0, 0, N, B, K, K, B, N, 0, 0],  // handlebars + neon tips
                [0, 0, 0, B, D, D, B, 0, 0, 0],  // torso on bike
                [Tb, T, D, B, Nd,Nd, B, D, 0, 0],  // thruster + neon engine strip
                [0, T, D, N, D, D, N, D, 0, 0],  // hover glow (neon underline)
                [0, 0, Nd, 0, Nd,Nd, 0, Nd, 0, 0],  // thruster exhaust dots
            ]
            return renderPixelArt(pixels, scale: 2)
        }()

        static let motorcycleCyan: CGImage? = {
            let _ : UInt32 = 0
            let N : UInt32 = 0x00FFEE  // cyan neon
            let Nd: UInt32 = 0x00BBAA  // dark cyan neon
            let B : UInt32 = 0x1A1A2A
            let D : UInt32 = 0x252535
            let K : UInt32 = 0x111118
            let V : UInt32 = 0x334455
            let T : UInt32 = 0x00CCBB  // cyan thruster
            let Tb: UInt32 = 0x44FFEE  // cyan thruster bright
            let pixels: [[UInt32]] = [
                [0, 0, 0, 0, K, K, 0, 0, 0, 0],
                [0, 0, 0, K, V, V, K, 0, 0, 0],
                [0, 0, 0, 0, K, K, N, 0, 0, 0],
                [0, 0, N, B, K, K, B, N, 0, 0],
                [0, 0, 0, B, D, D, B, 0, 0, 0],
                [Tb, T, D, B, Nd,Nd, B, D, 0, 0],
                [0, T, D, N, D, D, N, D, 0, 0],
                [0, 0, Nd, 0, Nd,Nd, 0, Nd, 0, 0],
            ]
            return renderPixelArt(pixels, scale: 2)
        }()

        static let motorcycleYellow: CGImage? = {
            let _ : UInt32 = 0
            let N : UInt32 = 0xFFCC00  // yellow neon
            let Nd: UInt32 = 0xDD9900  // dark yellow neon
            let B : UInt32 = 0x1A1A2A
            let D : UInt32 = 0x252535
            let K : UInt32 = 0x111118
            let V : UInt32 = 0x334455
            let T : UInt32 = 0xDDAA00  // yellow thruster
            let Tb: UInt32 = 0xFFDD44  // yellow thruster bright
            let pixels: [[UInt32]] = [
                [0, 0, 0, 0, K, K, 0, 0, 0, 0],
                [0, 0, 0, K, V, V, K, 0, 0, 0],
                [0, 0, 0, 0, K, K, N, 0, 0, 0],
                [0, 0, N, B, K, K, B, N, 0, 0],
                [0, 0, 0, B, D, D, B, 0, 0, 0],
                [Tb, T, D, B, Nd,Nd, B, D, 0, 0],
                [0, T, D, N, D, D, N, D, 0, 0],
                [0, 0, Nd, 0, Nd,Nd, 0, Nd, 0, 0],
            ]
            return renderPixelArt(pixels, scale: 2)
        }()

        static let motorcycles: [CGImage?] = [motorcyclePink, motorcycleCyan, motorcycleYellow]

        // ── Cyberpunk Cyber-Sedan variants: 20x8 pixels, displayed at 2x = 40x16 ──
        // Low-slung sedan: tinted windows, neon underglow, cyan LED headlights
        static func makeCar(body: UInt32, dark: UInt32, roof: UInt32, neon: UInt32) -> CGImage? {
            let _ : UInt32 = 0
            let B  = body        // main body
            let D  = dark        // underside shade
            let R  = roof        // roof highlight
            let L  = neon        // neon accent color
            let W : UInt32 = 0x223355  // tinted windshield (dark)
            let Wh: UInt32 = 0x334466  // tinted windshield reflection
            let K : UInt32 = 0x111118  // tire
            let G : UInt32 = 0x252535  // wheel well
            let H : UInt32 = 0x555566  // hubcap
            let Y : UInt32 = 0x00FFEE  // cyan LED headlight
            let Yg: UInt32 = 0x00BBAA  // headlight glow
            let T : UInt32 = 0xFF0044  // taillight (neon red)
            let C : UInt32 = 0x333344  // dark chrome bumper
            let pixels: [[UInt32]] = [
                [0, 0, 0, 0, 0, R, R, R, R, R, R, R, R, R, 0, 0, 0, 0, 0, 0],  // roof top
                [0, 0, 0, 0, R, R, B, B, B, B, B, B, B, R, R, 0, 0, 0, 0, 0],  // roof
                [0, 0, 0, R, W, W, Wh,W, W, W, W, W, Wh,W, W, R, 0, 0, 0, 0],  // tinted windshield
                [0, 0, C, B, B, B, B, B, B, B, B, B, B, B, B, B, B, C, Yg, 0],  // hood + dark bumper
                [0, T, B, B, B, B, B, B, D, D, B, B, B, B, B, B, B, B, Y, 0],  // body + door line
                [0, T, L, L, L, L, L, L, L, L, L, L, L, L, L, L, L, L, Y, 0],  // NEON UNDERGLOW STRIP
                [0, 0, D, G, K, K, G, D, D, D, D, D, D, G, K, K, G, D, 0, 0],  // wheel wells
                [0, 0, 0, K, K, H, K, 0, 0, 0, 0, 0, 0, K, H, K, K, 0, 0, 0],  // wheels + hubcaps
            ]
            return renderPixelArt(pixels, scale: 2)
        }

        static let carRedPink:    CGImage? = makeCar(body: 0x661122, dark: 0x330A11, roof: 0x882233, neon: 0xFF0066)
        static let carBlueCyan:   CGImage? = makeCar(body: 0x112244, dark: 0x0A1133, roof: 0x223366, neon: 0x00FFEE)
        static let carBlackGreen: CGImage? = makeCar(body: 0x1A1A22, dark: 0x0D0D11, roof: 0x2A2A33, neon: 0x00FF66)
        static let carPurpleMag:  CGImage? = makeCar(body: 0x331144, dark: 0x1A0A22, roof: 0x442266, neon: 0xFF00CC)
        static let carSilverBlue: CGImage? = makeCar(body: 0x778899, dark: 0x445566, roof: 0x99AABB, neon: 0x4488FF)

        static let cars: [CGImage?] = [carRedPink, carBlueCyan, carBlackGreen, carPurpleMag, carSilverBlue]

        // ── Cyberpunk Armored Cyber-Hauler variants: 32x8 pixels, displayed at 2x ──
        // Armored truck: LED running lights, neon strip on cargo, thruster exhaust
        static func makeTruck(cab: UInt32, cabDark: UInt32, cargo: UInt32, cargoDark: UInt32, neon: UInt32) -> CGImage? {
            let _ : UInt32 = 0
            let A  = cab         // cab body
            let Ad = cabDark     // cab shade
            let B  = cargo       // cargo body
            let Bd = cargoDark   // cargo shade
            let L  = neon        // neon accent
            let W : UInt32 = 0x223355  // tinted windshield
            let Wh: UInt32 = 0x334466  // windshield reflection
            let K : UInt32 = 0x111118  // tire
            let G : UInt32 = 0x252535  // wheel well
            let H : UInt32 = 0x555566  // hubcap
            let Y : UInt32 = 0x00FFEE  // cyan LED headlight
            let Yg: UInt32 = 0x00BBAA  // headlight glow
            let T : UInt32 = 0xFF0044  // taillight neon
            let C : UInt32 = 0x333344  // dark chrome bumper
            let Th: UInt32 = 0xFF6622  // thruster glow (replaces exhaust)
            let Tb: UInt32 = 0xFF8844  // thruster bright
            let pixels: [[UInt32]] = [
                [0, 0, L, 0, L, 0, L, 0, L, 0, L, 0, L, 0, L, 0, L, 0, L, 0, 0, 0, 0, 0, 0, Tb,Th, 0, A, A, Yg, 0],
                [0, T, B, B, B, B, B, B, B, B, B, B, B, B, B, B, B, B, B, B, B, 0, 0, Th, A, A, A, A, A, A, Y, 0],
                [0, T, B, B, B, B, B, B, B, B, B, B, B, B, B, B, B, B, B, B, B, 0, W, Wh, W, A, A, A, A, A, Y, 0],
                [0, 0, B, B, B, B, B, B, B, B, B, B, B, B, B, B, B, B, B, B, B, 0, A, A, A, A, A, A, A, A, C, 0],
                [0, 0, Bd,Bd,Bd,Bd,Bd,Bd,Bd,Bd,Bd,Bd,Bd,Bd,Bd,Bd,Bd,Bd,Bd,Bd,Bd, 0, Ad,Ad,Ad,Ad,Ad,Ad,Ad,Ad, C, 0],
                [0, 0, L, L, L, L, L, L, L, L, L, L, L, L, L, L, L, L, L, L, L, 0, L, L, L, L, L, L, L, L, 0, 0],
                [0, 0, Bd, G, K, K, G, Bd,Bd, G, K, K, G, Bd,Bd,Bd,Bd,Bd,Bd,Bd, 0, 0, Ad, G, K, K, G, Ad, 0, 0, 0, 0],
                [0, 0, 0, K, K, H, K, 0, 0, K, H, K, K, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, K, K, H, K, 0, 0, 0, 0, 0],
            ]
            return renderPixelArt(pixels, scale: 2)
        }

        static let truckMilitary:   CGImage? = makeTruck(cab: 0x2A2A22, cabDark: 0x1A1A14, cargo: 0x222218, cargoDark: 0x15150F, neon: 0xFF2200)
        static let truckCorporate:  CGImage? = makeTruck(cab: 0x999999, cabDark: 0x666666, cargo: 0xAAAAAA, cargoDark: 0x777777, neon: 0x00FFEE)
        static let truckIndustrial: CGImage? = makeTruck(cab: 0x887722, cabDark: 0x554411, cargo: 0xAA9933, cargoDark: 0x776622, neon: 0xFF8800)

        static let trucks: [CGImage?] = [truckMilitary, truckCorporate, truckIndustrial]
    }

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
        createScoreOverlay(screen: screen, width: 200)
        scoreLabel?.stringValue = livesString() + "0"
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
                case .motorcycle: sprite = Sprites.motorcycles.randomElement()!
                case .car:        sprite = Sprites.cars.randomElement()!
                case .truck:      sprite = Sprites.trucks.randomElement()!
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
        let mousePos = NSEvent.mouseLocation
        // Convert NS coords to AX coords for X
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
                    scoreLabel?.stringValue = livesString() + "\(score)"
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
        if hopTarget == nil {
            for car in cars {
                let carRect = CGRect(x: car.x, y: car.y, width: car.width, height: carHeight)
                if frogRect.intersects(carRect) {
                    triggerDeath(now: now)
                    break
                }
                // Near-miss detection
                let expanded = carRect.insetBy(dx: -nearMissThreshold, dy: -nearMissThreshold)
                if expanded.intersects(frogRect) && !carRect.intersects(frogRect) {
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

        CATransaction.begin()
        CATransaction.setDisableActions(true)

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

        CATransaction.commit()
    }


    // MARK: - Death & Game Over

    private func triggerDeath(now: UInt64) {
        lives -= 1
        if lives <= 0 {
            gameOver = true
            gameOverMach = now
            scoreLabel?.stringValue = "GAME OVER \(score)"
            print("Frogger game over: score=\(score)")
            return
        }
        // Start death animation
        deathAnimating = true
        deathStart = now
        deathShakeOriginX = frogX
        hopTarget = nil
        scoreLabel?.stringValue = livesString() + "\(score)"
        print("Frogger death: lives=\(lives)")
    }
}
