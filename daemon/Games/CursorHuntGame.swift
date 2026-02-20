import Cocoa
import ApplicationServices



class CursorHuntGame: GameBase {

    // Physics
    private var position = CGPoint.zero
    private var velocity = CGPoint.zero
    private var baseAccel: CGFloat = 400
    private let accelRamp: CGFloat = 40
    private var maxSpeed: CGFloat = 500
    private let maxSpeedCap: CGFloat = 1600
    private let friction: CGFloat = 0.994

    // Scoring
    private var startMach: UInt64 = 0
    private var survivalTime: CGFloat = 0

    // Tilt
    private var tiltAngle: CGFloat = 0

    // Trail emitter
    private var trailWindow: NSWindow?
    private var trailEmitter: CAEmitterLayer?

    // MARK: - GameBase Hooks

    override func onStart(screen: CGRect, pip: PipWindowInfo) {
        position = pip.bounds.origin
        velocity = .zero
        baseAccel = 400
        maxSpeed = 500
        survivalTime = 0
        tiltAngle = 0
        startMach = mach_absolute_time()

        let setup = {
            self.createScoreOverlay(screen: screen)
            let (tw, tl) = self.createFullscreenOverlay(screen: screen)
            self.trailWindow = tw
            self.buildTrailEmitter(on: tl, screen: screen)
        }
        if Thread.isMainThread { setup() }
        else { DispatchQueue.main.sync { setup() } }

        scoreLabel?.attributedStringValue = Self.styledScore("0.0s")
        print("Cursor Hunt started")
    }

    override func onStop() {
        trailWindow?.orderOut(nil)
        trailWindow = nil
        trailEmitter = nil
        print("Cursor Hunt stopped")
    }

    private func buildTrailEmitter(on rootLayer: CALayer, screen: CGRect) {
        let emitter = CAEmitterLayer()
        emitter.emitterShape = .point
        emitter.emitterSize = CGSize(width: 4, height: 4)
        emitter.renderMode = .additive
        emitter.birthRate = 1

        // Purple core — the main trail color
        let purple = CAEmitterCell()
        purple.contents = Self.trailDot
        purple.birthRate = 45
        purple.lifetime = 0.6
        purple.lifetimeRange = 0.2
        purple.velocity = 30
        purple.velocityRange = 20
        purple.emissionRange = .pi * 2
        purple.scale = 0.15
        purple.scaleRange = 0.06
        purple.scaleSpeed = -0.15
        purple.alphaSpeed = -1.4
        purple.color = NSColor(red: 0.6, green: 0.1, blue: 0.9, alpha: 0.9).cgColor

        // Cyan sparks — bright accent
        let cyan = CAEmitterCell()
        cyan.contents = Self.trailDot
        cyan.birthRate = 25
        cyan.lifetime = 0.45
        cyan.lifetimeRange = 0.15
        cyan.velocity = 50
        cyan.velocityRange = 30
        cyan.emissionRange = .pi * 2
        cyan.scale = 0.10
        cyan.scaleRange = 0.04
        cyan.scaleSpeed = -0.18
        cyan.alphaSpeed = -2.0
        cyan.color = NSColor(red: 0.0, green: 0.85, blue: 1.0, alpha: 0.85).cgColor

        // Dark smoke — moody depth
        let dark = CAEmitterCell()
        dark.contents = Self.trailDot
        dark.birthRate = 20
        dark.lifetime = 0.8
        dark.lifetimeRange = 0.3
        dark.velocity = 15
        dark.velocityRange = 10
        dark.emissionRange = .pi * 2
        dark.scale = 0.25
        dark.scaleRange = 0.08
        dark.scaleSpeed = -0.10
        dark.alphaSpeed = -1.0
        dark.color = NSColor(red: 0.08, green: 0.0, blue: 0.12, alpha: 0.7).cgColor

        // Red embers — rare hot accents
        let red = CAEmitterCell()
        red.contents = Self.trailDot
        red.birthRate = 8
        red.lifetime = 0.35
        red.lifetimeRange = 0.1
        red.velocity = 70
        red.velocityRange = 40
        red.emissionRange = .pi * 2
        red.scale = 0.06
        red.scaleRange = 0.03
        red.scaleSpeed = -0.12
        red.alphaSpeed = -2.5
        red.color = NSColor(red: 1.0, green: 0.15, blue: 0.1, alpha: 0.8).cgColor

        emitter.emitterCells = [purple, cyan, dark, red]
        rootLayer.addSublayer(emitter)
        trailEmitter = emitter
    }

    private static let trailDot: CGImage? = {
        let sz: CGFloat = 12
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(sz),
                                    pixelsHigh: Int(sz), bitsPerSample: 8,
                                    samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        // Radial gradient for soft glow
        let ctx = NSGraphicsContext.current!.cgContext
        let colors = [NSColor.white.cgColor, NSColor(white: 1.0, alpha: 0.0).cgColor] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
            ctx.drawRadialGradient(gradient,
                                   startCenter: CGPoint(x: sz/2, y: sz/2), startRadius: 0,
                                   endCenter: CGPoint(x: sz/2, y: sz/2), endRadius: sz/2,
                                   options: [])
        }
        NSGraphicsContext.restoreGraphicsState()
        return rep.cgImage
    }()

    // MARK: - Game Loop

    override func gameTick() {
        guard active, let _ = cachedAXWindow else { return }

        refreshPipSize()

        let screen = getScreenFrame()
        let size = cachedPipSize
        let dt = deltaTime()

        // Game over pause
        if checkGameOverTimeout() { return }

        // Survival time
        let now = mach_absolute_time()
        survivalTime = machToSeconds(now - startMach)
        scoreLabel?.attributedStringValue = Self.styledScore(String(format: "%.1fs", survivalTime))

        // Ramp difficulty — logarithmic curve so it keeps getting harder past 28s
        let rampT = log(1 + survivalTime * 0.15) / log(1 + 30 * 0.15)  // normalized 0..~1 at 30s
        baseAccel = 400 + 1200 * rampT
        maxSpeed = min(500 + 1100 * rampT, maxSpeedCap)

        // Get mouse position
        guard let mousePos = mousePosition() else { return }

        // Accelerate toward cursor
        let pipCenter = CGPoint(x: position.x + size.width / 2, y: position.y + size.height / 2)
        let dx = mousePos.x - pipCenter.x
        let dy = mousePos.y - pipCenter.y
        let dist = Self.distance(mousePos, pipCenter)

        if dist > 1 {
            velocity.x += (dx / dist) * baseAccel * dt
            velocity.y += (dy / dist) * baseAccel * dt
        }

        // Friction
        velocity.x *= pow(friction, dt * 500)
        velocity.y *= pow(friction, dt * 500)

        // Clamp speed
        let speed = sqrt(velocity.x * velocity.x + velocity.y * velocity.y)
        if speed > maxSpeed {
            velocity.x *= maxSpeed / speed
            velocity.y *= maxSpeed / speed
        }

        // Move
        position.x += velocity.x * dt
        position.y += velocity.y * dt

        // Screen clamp
        position.x = max(screen.minX, min(position.x, screen.maxX - size.width))
        position.y = max(screen.minY, min(position.y, screen.maxY - size.height))

        // Collision: cursor inside PiP
        let pipRect = CGRect(origin: position, size: size).insetBy(dx: 4, dy: 4)
        if Self.pointInRect(mousePos, pipRect) {
            triggerGameOver(message: String(format: "CAUGHT %.1fs", survivalTime))
            print("Cursor Hunt game over: \(survivalTime)s")
        }

        // Move PiP
        if !movePip(to: position) { return }

        // Trail emitter follows PiP center, intensity scales with speed
        if let emitter = trailEmitter {
            let nsX = position.x + size.width / 2
            let nsY = screenH - (position.y + size.height / 2)
            emitter.emitterPosition = CGPoint(x: nsX, y: nsY)
            // Ramp particle intensity with speed (0 at rest, full at maxSpeed)
            let intensity = min(speed / 400.0, 1.5)
            emitter.birthRate = intensity > 0.05 ? Float(intensity) : 0
        }

        // Border
        let bounds = CGRect(origin: position, size: size)

        withTransaction {
            syncBorder(around: bounds)
            if speed > 20 {
                let targetTilt = atan2(velocity.y, velocity.x) * 0.4
                tiltAngle += (targetTilt - tiltAngle) * (1.0 - pow(1.0 - 0.2, dt * 500))
            } else {
                tiltAngle *= pow(0.9, dt * 500)
            }
            borderRef?.tilt(tiltAngle)
        }
    }
}
