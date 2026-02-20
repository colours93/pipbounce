import Cocoa
import ApplicationServices
import UserNotifications

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
    private var cachedPipWindow: AXUIElement?
    private var lastDiscoveryTime = Date.distantPast
    private let discoveryInterval: TimeInterval = 0.5
    private var tickTimer: DispatchSourceTimer?
    private static var timebaseInfo: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    private var accessibilityPollTimer: DispatchSourceTimer?
    private var onboardingWindow: OnboardingWindow?

    func start() {
        if AXIsProcessTrusted() {
            finishStart()
        } else {
            print("Accessibility permission not granted — waiting for grant…")
            let onboarding = OnboardingWindow()
            onboardingWindow = onboarding
            onboarding.show()
            startAccessibilityPoll()
        }
    }

    private func startAccessibilityPoll() {
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + 3, repeating: 3)
        t.setEventHandler { [weak self] in
            if AXIsProcessTrusted() {
                self?.accessibilityPollTimer?.cancel()
                self?.accessibilityPollTimer = nil
                self?.onboardingWindow = nil
                print("Accessibility permission granted")
                self?.finishStart()
            }
        }
        t.resume()
        accessibilityPollTimer = t
    }

    private func finishStart() {
        installHotkey()
        print("xpip daemon started")

        let t = DispatchSource.makeTimerSource(flags: .strict, queue: .main)
        t.schedule(deadline: .now(), repeating: .milliseconds(16), leeway: .microseconds(500))
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        tickTimer = t
    }

    private func showAccessibilityNotification() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "XPip"
            content.body = "Accessibility access required. Opening System Settings…"
            content.sound = .default
            let request = UNNotificationRequest(identifier: "accessibility", content: content, trigger: nil)
            center.add(request)
        }
    }

    private func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    private func quickCheck(_ element: AXUIElement) -> PipWindowInfo? {
        var posVal: AnyObject?
        var sizeVal: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posVal) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeVal) == .success
        else { return nil }

        var pos = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(posVal as! AXValue, .cgPoint, &pos),
              AXValueGetValue(sizeVal as! AXValue, .cgSize, &size)
        else { return nil }

        return PipWindowInfo(bounds: CGRect(origin: pos, size: size), axWindow: element)
    }

    private func tick() {
        if Games.anyActive || animating { return }

        guard let event = CGEvent(source: nil) else { return }
        let mousePos = event.location

        let pip: PipWindowInfo?
        if let cached = cachedPipWindow, let info = quickCheck(cached) {
            pip = info
        } else {
            let now = Date()
            guard now.timeIntervalSince(lastDiscoveryTime) >= discoveryInterval else {
                return
            }
            lastDiscoveryTime = now
            pip = findPipWindow()
            cachedPipWindow = pip?.axWindow
        }

        guard let pip else {
            interacting = false
            wasOnPip = false
            cachedPipWindow = nil
            rgbBorder.hide()
            return
        }

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
        t.schedule(deadline: .now(), repeating: .milliseconds(16), leeway: .milliseconds(2))
        t.setEventHandler { [weak self] in self?.stepAnimation() }
        animTimer = t
        t.resume()
    }

    func toggleGame(_ game: MiniGame) {
        for g in Games.all.values where g.active {
            g.stop()
            rgbBorder.tilt(0)
            rgbBorder.hide()
        }

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
