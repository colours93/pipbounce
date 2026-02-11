import Cocoa
import ApplicationServices

class XPipDaemon {
    private var lastDodgeTime = Date.distantPast
    private var interacting = false
    private var wasOnPip = false
    private let rgbBorder = RGBBorder()

    private var animating = false
    private var animStart = CGPoint.zero
    private var animEnd = CGPoint.zero
    private var animStartMach: UInt64 = 0
    private let animDuration: Double = 0.18
    private var animWindow: AXUIElement?
    private var animSize = CGSize.zero
    private var animCurrentPos = CGPoint.zero
    private var animTimer: DispatchSourceTimer?
    private static var timebaseInfo: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    func start() {
        if !AXIsProcessTrusted() {
            print("Accessibility permission required")
        }

        installHotkey()
        print("xpip daemon started")

        Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func tick() {
        // Pong and dodge animation have their own high-frequency timers.
        // Bail immediately -- don't block main queue with expensive AX IPC.
        if pong.active || flappy.active || bounce.active || invaders.active
            || frogger.active || runner.active || snake.active
            || breakout.active || asteroids.active || animating { return }

        guard let event = CGEvent(source: nil) else { return }
        let mousePos = event.location

        guard let pip = findPipWindow() else {
            interacting = false
            wasOnPip = false
            rgbBorder.hide()
            return
        }

        // Normal mode -- border tracks real AX position
        if settings.glow {
            rgbBorder.show(around: pip.bounds)
        } else {
            rgbBorder.hide()
        }

        guard settings.enabled else { return }

        let onPip = pip.bounds.contains(mousePos)

        if onPip && !wasOnPip {
            if isInPipCorner(mousePos: mousePos, pipBounds: pip.bounds) {
                interacting = true
            } else {
                interacting = false
                dodgeIfReady(pip: pip, mousePos: mousePos)
            }
        }

        if !onPip && wasOnPip {
            interacting = false
        }

        wasOnPip = onPip
    }

    private func stepAnimation() {
        let elapsed = mach_absolute_time() - animStartMach
        let info = Self.timebaseInfo
        let sec = Double(elapsed * UInt64(info.numer) / UInt64(info.denom)) / 1_000_000_000
        let t = min(sec / animDuration, 1.0)
        let ease = 1.0 - pow(1.0 - t, 3.0)

        let x = animStart.x + (animEnd.x - animStart.x) * CGFloat(ease)
        let y = animStart.y + (animEnd.y - animStart.y) * CGFloat(ease)
        var pos = CGPoint(x: x, y: y)
        animCurrentPos = pos

        // Move PiP via AX, then IMMEDIATELY move border -- same call, microseconds apart
        if let win = animWindow, let val = AXValueCreate(.cgPoint, &pos) {
            AXUIElementSetAttributeValue(win, kAXPositionAttribute as CFString, val)
        }
        if settings.glow {
            rgbBorder.show(around: CGRect(origin: pos, size: animSize))
        } else {
            rgbBorder.hide()
        }

        if t >= 1.0 {
            animTimer?.cancel()
            animTimer = nil
            animating = false
            animWindow = nil
        }
    }

    private func dodgeIfReady(pip: PipWindowInfo, mousePos: CGPoint) {
        let now = Date()
        guard now.timeIntervalSince(lastDodgeTime) >= settings.cooldown else { return }

        let screen = getScreenFrame()
        let target = getFurthestCorner(from: mousePos, windowSize: pip.bounds.size, screen: screen)

        let alreadyThere = abs(pip.bounds.origin.x - target.x) < 30
            && abs(pip.bounds.origin.y - target.y) < 30
        guard !alreadyThere else { return }

        animStart = pip.bounds.origin
        animEnd = target
        animSize = pip.bounds.size
        animCurrentPos = pip.bounds.origin
        animStartMach = mach_absolute_time()
        animWindow = pip.axWindow
        animating = true
        lastDodgeTime = now

        animTimer?.cancel()
        let t = DispatchSource.makeTimerSource(flags: .strict, queue: .main)
        t.schedule(deadline: .now(), repeating: .milliseconds(2), leeway: .microseconds(100))
        t.setEventHandler { [weak self] in self?.stepAnimation() }
        animTimer = t
        t.resume()
    }

    /// Toggle any MiniGame. Stops the current game if one is active.
    func toggleGame(_ game: MiniGame) {
        // Stop any running game first
        let allGames: [MiniGame] = [pong, flappy, bounce, invaders, frogger, runner, snake, breakout, asteroids]
        for g in allGames where g.active {
            g.stop()
            rgbBorder.tilt(0)
            rgbBorder.hide()
        }

        // If the requested game was already active, we just stopped it
        if !game.active, let pip = findPipWindow() {
            game.start(screen: getScreenFrame(), pip: pip, border: rgbBorder)
        }
    }

    private func isInPipCorner(mousePos: CGPoint, pipBounds: CGRect) -> Bool {
        let cs = min(settings.cornerSize, min(pipBounds.width, pipBounds.height) / 2)
        let nearLeft = mousePos.x - pipBounds.minX < cs
        let nearRight = pipBounds.maxX - mousePos.x < cs
        let nearTop = mousePos.y - pipBounds.minY < cs
        let nearBottom = pipBounds.maxY - mousePos.y < cs
        return (nearLeft || nearRight) && (nearTop || nearBottom)
    }
}
