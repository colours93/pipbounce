import Cocoa
import ApplicationServices

let cursorhunt = CursorHuntGame()

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

    // MARK: - GameBase Hooks

    override func onStart(screen: CGRect, pip: PipWindowInfo) {
        position = pip.bounds.origin
        velocity = .zero
        baseAccel = 400
        maxSpeed = 500
        survivalTime = 0
        tiltAngle = 0
        startMach = mach_absolute_time()

        if Thread.isMainThread {
            createScoreOverlay(screen: screen)
        } else {
            DispatchQueue.main.sync { self.createScoreOverlay(screen: screen) }
        }
        scoreLabel?.stringValue = "0.0s"
        print("Cursor Hunt started")
    }

    override func onStop() {
        print("Cursor Hunt stopped")
    }

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
        scoreLabel?.stringValue = String(format: "%.1fs", survivalTime)

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
        let dist = sqrt(dx * dx + dy * dy)

        if dist > 1 {
            velocity.x += (dx / dist) * baseAccel * dt
            velocity.y += (dy / dist) * baseAccel * dt
        }

        // Friction
        velocity.x *= friction
        velocity.y *= friction

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
        if pipRect.contains(mousePos) {
            triggerGameOver(message: String(format: "CAUGHT %.1fs", survivalTime))
            print("Cursor Hunt game over: \(survivalTime)s")
        }

        // Move PiP
        if !movePip(to: position) { return }

        // Border
        let bounds = CGRect(origin: position, size: size)

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        syncBorder(around: bounds)
        if speed > 20 {
            let targetTilt = atan2(velocity.y, velocity.x) * 0.4
            tiltAngle += (targetTilt - tiltAngle) * 0.2
        } else {
            tiltAngle *= 0.9
        }
        borderRef?.tilt(tiltAngle)

        CATransaction.commit()
    }
}
