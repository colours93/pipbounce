import Cocoa
import ApplicationServices

let bounce = BounceGame()

class BounceGame: MiniGame {
    var active = false
    var lastBounds = CGRect.zero

    // Physics
    private var position = CGPoint.zero
    private var velocity = CGPoint.zero
    private let gravity: CGFloat = 120
    private let elasticity: CGFloat = 0.9
    private let airFriction: CGFloat = 0.9993
    private let restThreshold: CGFloat = 3

    // Drag state
    private var isDragging = false
    private var wasMouseDown = false
    private var grabOffset = CGPoint.zero
    private var posHistory: [(pos: CGPoint, time: UInt64)] = []

    // Tilt
    private var tiltAngle: CGFloat = 0

    // Cached refs
    private var cachedAXWindow: AXUIElement?
    private var cachedPipSize = CGSize.zero
    private var borderRef: RGBBorder?
    private var gameTimer: DispatchSourceTimer?
    private var lastMach: UInt64 = 0

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
        position = pip.bounds.origin
        velocity = .zero
        isDragging = false
        wasMouseDown = false
        grabOffset = .zero
        posHistory = []
        tiltAngle = 0

        cachedAXWindow = pip.axWindow
        cachedPipSize = pip.bounds.size
        borderRef = border
        border.rotationPadding = max(pip.bounds.size.width, pip.bounds.size.height) * 0.3
        lastMach = mach_absolute_time()

        active = true
        print("Bounce started")

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

        borderRef?.tilt(0)
        borderRef?.rotationPadding = 0
        borderRef?.hide()
        borderRef = nil
        print("Bounce stopped")
    }

    // MARK: - Game Loop

    private func gameTick() {
        guard active, let axWindow = cachedAXWindow else { return }

        // Re-read actual PiP size each tick so resizing is handled correctly
        var sizeRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(axWindow, kAXSizeAttribute as CFString, &sizeRef) == .success {
            var freshSize = CGSize.zero
            AXValueGetValue(sizeRef as! AXValue, .cgSize, &freshSize)
            if freshSize.width > 0 && freshSize.height > 0 {
                cachedPipSize = freshSize
                borderRef?.rotationPadding = max(freshSize.width, freshSize.height) * 0.3
            }
        }

        let screen = getScreenFrame()
        let size = cachedPipSize
        let now = mach_absolute_time()
        let dt = min(machToSeconds(now - lastMach), 0.05)
        lastMach = now

        guard let event = CGEvent(source: nil) else { return }
        let mousePos = event.location
        let mouseDown = NSEvent.pressedMouseButtons & 1 != 0

        let pipRect = CGRect(origin: position, size: size)

        // --- Drag detection ---

        if mouseDown && !wasMouseDown && pipRect.contains(mousePos) {
            // Grab
            isDragging = true
            grabOffset = CGPoint(x: mousePos.x - position.x, y: mousePos.y - position.y)
            velocity = .zero
            posHistory = [(pos: mousePos, time: now)]
        } else if !mouseDown && wasMouseDown && isDragging {
            // Release — compute throw velocity from rolling window
            isDragging = false
            if posHistory.count >= 2, let first = posHistory.first, let last = posHistory.last {
                let elapsed = machToSeconds(last.time - first.time)
                if elapsed > 0.001 {
                    velocity.x = (last.pos.x - first.pos.x) / elapsed
                    velocity.y = (last.pos.y - first.pos.y) / elapsed
                }
            }
            posHistory = []
        }

        wasMouseDown = mouseDown

        // --- Update position ---

        if isDragging {
            // Follow cursor
            position.x = mousePos.x - grabOffset.x
            position.y = mousePos.y - grabOffset.y

            // Track position history for throw velocity
            posHistory.append((pos: mousePos, time: now))
            if posHistory.count > 8 { posHistory.removeFirst() }
        } else {
            // Free flight — apply gravity and friction
            velocity.y += gravity * dt
            velocity.x *= airFriction
            velocity.y *= airFriction

            position.x += velocity.x * dt
            position.y += velocity.y * dt

            // Bounce off screen edges
            if position.x < screen.minX {
                position.x = screen.minX
                velocity.x = abs(velocity.x) * elasticity
            }
            if position.x + size.width > screen.maxX {
                position.x = screen.maxX - size.width
                velocity.x = -abs(velocity.x) * elasticity
            }
            if position.y < screen.minY {
                position.y = screen.minY
                velocity.y = abs(velocity.y) * elasticity
            }
            if position.y + size.height > screen.maxY {
                position.y = screen.maxY - size.height
                velocity.y = -abs(velocity.y) * elasticity
            }

            // Hard clamp — ensures PiP can never escape screen regardless of size changes
            position.x = max(screen.minX, min(position.x, screen.maxX - size.width))
            position.y = max(screen.minY, min(position.y, screen.maxY - size.height))

            // Rest detection
            let speed = sqrt(velocity.x * velocity.x + velocity.y * velocity.y)
            if speed < restThreshold {
                velocity = .zero
            }
        }

        // --- Move PiP via AX ---
        var newPos = position
        if let val = AXValueCreate(.cgPoint, &newPos) {
            let err = AXUIElementSetAttributeValue(axWindow, kAXPositionAttribute as CFString, val)
            if err != .success {
                stop()
                return
            }
        }

        // --- Update border ---
        let bounds = CGRect(origin: position, size: size)
        lastBounds = bounds

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        if settings.glow, let border = borderRef {
            border.show(around: bounds)

            // Tilt based on velocity direction
            if !isDragging {
                let speed = sqrt(velocity.x * velocity.x + velocity.y * velocity.y)
                if speed > 20 {
                    let targetTilt = atan2(velocity.y, velocity.x) * 0.15
                    tiltAngle += (targetTilt - tiltAngle) * 0.08
                } else {
                    tiltAngle *= 0.9
                }
            } else {
                tiltAngle *= 0.9
            }
            border.tilt(tiltAngle)
        }

        CATransaction.commit()
    }
}
