import Cocoa
import ApplicationServices
import QuartzCore
import ScreenCaptureKit
import CoreMedia

// MARK: - Settings

class Settings {
    var enabled = true
    var cooldown: TimeInterval = 0.4
    var margin: CGFloat = 20
    var cornerSize: CGFloat = 100
    var glow = true
    var hotkeyCode: UInt16 = 2       // "d" key
    var hotkeyFlags: UInt32 = 0x108  // cmd+shift
}

let settings = Settings()
var audioMonitor: AudioMonitor!

// MARK: - PiP Window Discovery

struct PipWindowInfo {
    let bounds: CGRect
    let axWindow: AXUIElement
}

func findPipWindow() -> PipWindowInfo? {
    let chromeApps = NSWorkspace.shared.runningApplications.filter {
        ($0.localizedName ?? "").contains("Chrome")
            || ($0.bundleIdentifier ?? "").contains("chrome")
    }

    for app in chromeApps {
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement] else { continue }

        for window in windows {
            if let info = extractPipInfo(from: window) {
                return info
            }
        }
    }

    return nil
}

private func extractPipInfo(from window: AXUIElement) -> PipWindowInfo? {
    var titleRef: CFTypeRef?
    _ = AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef)
    let title = (titleRef as? String) ?? ""

    var posRef: CFTypeRef?
    var sizeRef: CFTypeRef?
    guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posRef) == .success,
          AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef) == .success else {
        return nil
    }

    var pos = CGPoint.zero
    var size = CGSize.zero
    AXValueGetValue(posRef as! AXValue, .cgPoint, &pos)
    AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)

    let titleLower = title.lowercased()
    let isPip = titleLower.contains("picture in picture")
        || titleLower.contains("picture-in-picture")

    // Document PiP windows appear as small, always-on-top, landscape windows with a blank title.
    let isDocPip = (title == "" || title == "about:blank")
        && size.width >= 200 && size.width <= 800
        && size.height >= 100 && size.height <= 600
        && (size.width / size.height) > 1.2

    guard isPip || isDocPip else { return nil }

    let bounds = CGRect(origin: pos, size: size)
    return PipWindowInfo(bounds: bounds, axWindow: window)
}

// MARK: - Screen Geometry

func getScreenFrame() -> CGRect {
    if let main = NSScreen.main {
        return CGRect(x: 0, y: 0, width: main.frame.width, height: main.frame.height)
    }
    return CGRect(x: 0, y: 0, width: 1920, height: 1080)
}

/// Returns the screen corner farthest from the mouse, offset by margin and window size.
func getFurthestCorner(from mousePos: CGPoint, windowSize: CGSize, screen: CGRect) -> CGPoint {
    let m = settings.margin
    let corners: [CGPoint] = [
        CGPoint(x: screen.minX + m, y: screen.minY + m),
        CGPoint(x: screen.maxX - windowSize.width - m, y: screen.minY + m),
        CGPoint(x: screen.minX + m, y: screen.maxY - windowSize.height - m),
        CGPoint(x: screen.maxX - windowSize.width - m, y: screen.maxY - windowSize.height - m),
    ]

    var best = corners[3]
    var bestDist: CGFloat = 0

    for corner in corners {
        let cx = corner.x + windowSize.width / 2
        let cy = corner.y + windowSize.height / 2
        let dx = mousePos.x - cx
        let dy = mousePos.y - cy
        let dist = dx * dx + dy * dy
        if dist > bestDist {
            bestDist = dist
            best = corner
        }
    }

    return best
}

// MARK: - HTTP Control Server

class ControlServer {
    private let port: UInt16 = 51789
    private var serverSocket: Int32 = -1

    func start() {
        DispatchQueue.global(qos: .utility).async { [self] in
            serverSocket = socket(AF_INET, SOCK_STREAM, 0)
            guard serverSocket >= 0 else {
                print("Failed to create socket")
                return
            }

            var opt: Int32 = 1
            setsockopt(serverSocket, SOL_SOCKET, SO_REUSEADDR, &opt, socklen_t(MemoryLayout<Int32>.size))

            var addr = sockaddr_in()
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = port.bigEndian
            addr.sin_addr.s_addr = inet_addr("127.0.0.1")

            let bindResult = withUnsafePointer(to: &addr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    bind(serverSocket, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            guard bindResult == 0 else {
                print("Failed to bind to port \(port)")
                return
            }

            listen(serverSocket, 5)
            print("Control server listening on http://127.0.0.1:\(port)")

            while true {
                let client = accept(serverSocket, nil, nil)
                guard client >= 0 else { continue }
                handleClient(client)
            }
        }
    }

    private func handleClient(_ fd: Int32) {
        defer { close(fd) }

        var buffer = [UInt8](repeating: 0, count: 4096)
        let n = read(fd, &buffer, buffer.count)
        guard n > 0 else { return }

        let request = String(bytes: buffer[..<n], encoding: .utf8) ?? ""
        let firstLine = request.components(separatedBy: "\r\n").first ?? ""

        let bodyStart = request.range(of: "\r\n\r\n")
        let body = bodyStart.map { String(request[$0.upperBound...]) } ?? ""

        let cors = "Access-Control-Allow-Origin: *\r\n"
            + "Access-Control-Allow-Methods: GET, POST, OPTIONS\r\n"
            + "Access-Control-Allow-Headers: Content-Type"

        if firstLine.starts(with: "OPTIONS") {
            let resp = "HTTP/1.1 204 No Content\r\n\(cors)\r\n\r\n"
            write(fd, resp, resp.utf8.count)
            return
        }

        guard let responseBody = routeRequest(firstLine: firstLine, body: body) else {
            let resp = "HTTP/1.1 404 Not Found\r\n\(cors)\r\nContent-Length: 2\r\n\r\n{}"
            write(fd, resp, resp.utf8.count)
            return
        }

        let resp = "HTTP/1.1 200 OK\r\n"
            + "Content-Type: application/json\r\n"
            + "\(cors)\r\n"
            + "Content-Length: \(responseBody.utf8.count)\r\n\r\n"
            + responseBody
        write(fd, resp, resp.utf8.count)
    }

    private func routeRequest(firstLine: String, body: String) -> String? {
        if firstLine.contains("GET /status") {
            let pip = findPipWindow()
            return "{\"enabled\":\(settings.enabled),"
                + "\"cooldown\":\(settings.cooldown),"
                + "\"margin\":\(Int(settings.margin)),"
                + "\"cornerSize\":\(Int(settings.cornerSize)),"
                + "\"glow\":\(settings.glow),"
                + "\"hotkeyCode\":\(settings.hotkeyCode),"
                + "\"hotkeyFlags\":\(settings.hotkeyFlags),"
                + "\"audioLevel\":\(String(format: "%.3f", audioMonitor.level)),"
                + "\"pipActive\":\(pip != nil)}"
        }

        if firstLine.contains("POST /toggle") {
            settings.enabled.toggle()
            print(settings.enabled ? "Dodge enabled" : "Dodge paused")
            return "{\"enabled\":\(settings.enabled)}"
        }

        if firstLine.contains("POST /restart") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                cleanup()
                exit(0)
            }
            return "{\"restarting\":true}"
        }

        if firstLine.contains("POST /settings") {
            applySettings(from: body)
            return "{\"enabled\":\(settings.enabled),"
                + "\"cooldown\":\(settings.cooldown),"
                + "\"margin\":\(Int(settings.margin)),"
                + "\"cornerSize\":\(Int(settings.cornerSize)),"
                + "\"glow\":\(settings.glow)}"
        }

        return nil
    }

    private func applySettings(from body: String) {
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        if let c = json["cooldown"] as? Double { settings.cooldown = c }
        if let m = json["margin"] as? Double { settings.margin = CGFloat(m) }
        if let e = json["enabled"] as? Bool { settings.enabled = e }
        if let cs = json["cornerSize"] as? Double { settings.cornerSize = CGFloat(cs) }
        if let g = json["glow"] as? Bool { settings.glow = g }
        if let hk = json["hotkeyCode"] as? Int { settings.hotkeyCode = UInt16(hk) }
        if let hf = json["hotkeyFlags"] as? Int { settings.hotkeyFlags = UInt32(hf) }

        print("Settings updated: cooldown=\(settings.cooldown)"
              + " margin=\(Int(settings.margin))"
              + " cornerSize=\(Int(settings.cornerSize))"
              + " enabled=\(settings.enabled)")
    }
}

// MARK: - Audio Level Monitor

class AudioMonitor: NSObject, SCStreamOutput, SCStreamDelegate {
    private(set) var level: CGFloat = 0
    private var stream: SCStream?
    private var smoothed: CGFloat = 0

    func start() {
        Task {
            guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false),
                  let display = content.displays.first else { return }

            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            config.capturesAudio = true
            config.sampleRate = 44100
            config.channelCount = 1
            config.width = 1
            config.height = 1

            let s = SCStream(filter: filter, configuration: config, delegate: self)
            try? s.addStreamOutput(self, type: .audio, sampleHandlerQueue: .global(qos: .userInteractive))
            try? await s.startCapture()
            stream = s
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer buf: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio,
              let block = CMSampleBufferGetDataBuffer(buf) else { return }
        var length = 0
        var ptr: UnsafeMutablePointer<Int8>?
        CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil,
                                    totalLengthOut: &length, dataPointerOut: &ptr)
        guard let raw = ptr else { return }
        let count = length / MemoryLayout<Float>.size
        guard count > 0 else { return }
        let floats = raw.withMemoryRebound(to: Float.self, capacity: count) {
            UnsafeBufferPointer(start: $0, count: count)
        }
        var sum: Float = 0
        for s in floats { sum += s * s }
        let rms = CGFloat(sqrt(sum / Float(count)))
        let scaled = min(rms * 10, 1.0)
        smoothed = smoothed * 0.3 + scaled * 0.7
        level = smoothed
    }

    func stream(_ s: SCStream, didStopWithError error: Error) {}
}

// MARK: - Global Hotkey

func installHotkey() {
    let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
    guard let tap = CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .defaultTap,
        eventsOfInterest: mask,
        callback: { _, _, event, _ -> Unmanaged<CGEvent>? in
            let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            let flags = UInt32(event.flags.rawValue >> 16) & 0xFFF
            if keyCode == settings.hotkeyCode && flags == settings.hotkeyFlags {
                settings.enabled.toggle()
                print(settings.enabled ? "Dodge enabled (hotkey)" : "Dodge paused (hotkey)")
                return nil
            }
            return Unmanaged.passRetained(event)
        },
        userInfo: nil
    ) else {
        print("Failed to create hotkey tap")
        return
    }

    let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
    print("Hotkey registered")
}

// MARK: - RGB Border Overlay

class RGBBorder {
    private var window: NSWindow?
    private let borderWidth: CGFloat = 1.5
    private let containerLayer = CALayer()
    private let gradientLayer = CAGradientLayer()
    private let maskLayer = CAShapeLayer()

    func show(around rect: CGRect) {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let flippedY = screen.frame.height - rect.maxY
        let outerRect = rect.insetBy(dx: -borderWidth, dy: -borderWidth)
        let frame = NSRect(x: outerRect.origin.x, y: flippedY - borderWidth,
                           width: outerRect.width, height: outerRect.height)

        if window == nil {
            let w = NSWindow(contentRect: frame, styleMask: .borderless,
                             backing: .buffered, defer: false)
            w.isOpaque = false
            w.backgroundColor = .clear
            w.level = .floating
            w.ignoresMouseEvents = true
            w.hasShadow = false
            w.collectionBehavior = [.canJoinAllSpaces, .stationary]

            let view = NSView(frame: w.contentView!.bounds)
            view.wantsLayer = true
            w.contentView!.addSubview(view)

            view.layer!.addSublayer(containerLayer)

            gradientLayer.type = .conic
            gradientLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
            gradientLayer.endPoint = CGPoint(x: 0.5, y: 0)
            gradientLayer.colors = [
                NSColor.red.cgColor,
                NSColor.yellow.cgColor,
                NSColor.green.cgColor,
                NSColor.cyan.cgColor,
                NSColor.blue.cgColor,
                NSColor.magenta.cgColor,
                NSColor.red.cgColor,
            ]
            containerLayer.addSublayer(gradientLayer)

            maskLayer.fillRule = .evenOdd
            containerLayer.mask = maskLayer

            let spin = CABasicAnimation(keyPath: "transform.rotation.z")
            spin.fromValue = 0
            spin.toValue = 2 * Double.pi
            spin.duration = 3
            spin.repeatCount = .infinity
            gradientLayer.add(spin, forKey: "spin")

            w.orderFrontRegardless()
            window = w
        }

        window?.setFrame(frame, display: false)

        let viewBounds = NSRect(origin: .zero, size: frame.size)
        containerLayer.frame = viewBounds
        window?.contentView?.subviews.first?.frame = viewBounds

        let diag = sqrt(viewBounds.width * viewBounds.width + viewBounds.height * viewBounds.height)
        let gradSize = diag + 20
        gradientLayer.frame = NSRect(
            x: (viewBounds.width - gradSize) / 2,
            y: (viewBounds.height - gradSize) / 2,
            width: gradSize, height: gradSize)

        let outer = NSBezierPath(roundedRect: viewBounds, xRadius: 6, yRadius: 6)
        let inner = NSBezierPath(roundedRect: viewBounds.insetBy(dx: borderWidth, dy: borderWidth),
                                 xRadius: 4, yRadius: 4)
        let path = CGMutablePath()
        path.addPath(outer.cgPath)
        path.addPath(inner.cgPath)
        maskLayer.path = path
    }

    func pulse(_ level: CGFloat) {
        containerLayer.opacity = Float(0.05 + level * 0.95)
    }

    func hide() {
        window?.orderOut(nil)
        window = nil
    }
}

private extension NSBezierPath {
    var cgPath: CGPath {
        let path = CGMutablePath()
        var points = [CGPoint](repeating: .zero, count: 3)
        for i in 0..<elementCount {
            switch element(at: i, associatedPoints: &points) {
            case .moveTo: path.move(to: points[0])
            case .lineTo: path.addLine(to: points[0])
            case .curveTo, .cubicCurveTo: path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .closePath: path.closeSubpath()
            default: break
            }
        }
        return path
    }
}

// MARK: - Dodge Daemon

class XPipDaemon {
    private var lastDodgeTime = Date.distantPast
    private var interacting = false
    private var wasOnPip = false
    private let rgbBorder = RGBBorder()
    private let audio = AudioMonitor()

    private var animating = false
    private var animStart = CGPoint.zero
    private var animEnd = CGPoint.zero
    private var animStartMach: UInt64 = 0
    private let animDuration: Double = 0.18
    private var animWindow: AXUIElement?
    private var animSize = CGSize.zero
    private var animTimer: DispatchSourceTimer?
    private let animQueue = DispatchQueue(label: "xpip.anim", qos: .userInteractive)
    private static var timebaseInfo: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    func start() {
        if !AXIsProcessTrusted() {
            print("Accessibility permission required")
        }

        audioMonitor = audio
        audio.start()
        installHotkey()
        print("xpip daemon started")

        Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func tick() {
        guard !animating, settings.enabled,
              let event = CGEvent(source: nil) else { return }

        let mousePos = event.location

        guard let pip = findPipWindow() else {
            interacting = false
            wasOnPip = false
            rgbBorder.hide()
            return
        }

        if settings.glow {
            rgbBorder.show(around: pip.bounds)
            rgbBorder.pulse(audio.level)
        } else {
            rgbBorder.hide()
        }
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

        if let win = animWindow, let val = AXValueCreate(.cgPoint, &pos) {
            AXUIElementSetAttributeValue(win, kAXPositionAttribute as CFString, val)
            let size = self.animSize
            DispatchQueue.main.async { [weak self] in
                self?.rgbBorder.show(around: CGRect(origin: pos, size: size))
            }
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
        animStartMach = mach_absolute_time()
        animWindow = pip.axWindow
        animating = true
        lastDodgeTime = now

        animTimer?.cancel()
        let t = DispatchSource.makeTimerSource(flags: .strict, queue: animQueue)
        t.schedule(deadline: .now(), repeating: .milliseconds(8), leeway: .microseconds(500))
        t.setEventHandler { [weak self] in self?.stepAnimation() }
        animTimer = t
        t.resume()
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

// MARK: - PID Lock

let pidPath = NSString("~/.xpip/xpip.pid").expandingTildeInPath

func killExisting() {
    guard let pidStr = try? String(contentsOfFile: pidPath, encoding: .utf8),
          let oldPid = Int32(pidStr.trimmingCharacters(in: .whitespacesAndNewlines)),
          oldPid != getpid() else { return }

    kill(oldPid, SIGTERM)
    usleep(300_000)
}

func writePid() {
    let dir = (pidPath as NSString).deletingLastPathComponent
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    try? "\(getpid())".write(toFile: pidPath, atomically: true, encoding: .utf8)
}

func cleanup() {
    try? FileManager.default.removeItem(atPath: pidPath)
}

// MARK: - Entry Point

killExisting()
writePid()

let app = NSApplication.shared
let server = ControlServer()
server.start()
let daemon = XPipDaemon()
daemon.start()

signal(SIGINT) { _ in
    cleanup()
    exit(0)
}

signal(SIGTERM) { _ in
    cleanup()
    exit(0)
}

RunLoop.main.run()
