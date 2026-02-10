import Cocoa
import ApplicationServices
import QuartzCore
import ScreenCaptureKit
import CoreMedia
import CoreVideo

// MARK: - Settings

class Settings {
    var enabled = true
    var cooldown: TimeInterval = 0.4
    var margin: CGFloat = 20
    var cornerSize: CGFloat = 100
    var glow = true
    var glowColor = "rainbow"        // rainbow, blue, red, purple, green
    var hotkeyCode: UInt16 = 2       // "d" key
    var hotkeyFlags: UInt32 = 0x108  // cmd+shift
}

let settings = Settings()
var audioMonitor: AudioMonitor!
let pong = PongGame()

// MARK: - PiP Window Discovery

struct PipWindowInfo {
    let bounds: CGRect
    let axWindow: AXUIElement
}

/// Returns rects of all windows above normal level (floating/PiP).
private func floatingWindowRects() -> [CGRect] {
    guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
        return []
    }
    var rects: [CGRect] = []
    for info in list {
        guard let layer = info[kCGWindowLayer as String] as? Int, layer > 0,
              let bd = info[kCGWindowBounds as String] as? [String: Any] else { continue }
        let x = (bd["X"] as? NSNumber)?.doubleValue ?? 0
        let y = (bd["Y"] as? NSNumber)?.doubleValue ?? 0
        let w = (bd["Width"] as? NSNumber)?.doubleValue ?? 0
        let h = (bd["Height"] as? NSNumber)?.doubleValue ?? 0
        rects.append(CGRect(x: x, y: y, width: w, height: h))
    }
    return rects
}

func findPipWindow() -> PipWindowInfo? {
    let chromeApps = NSWorkspace.shared.runningApplications.filter {
        ($0.localizedName ?? "").contains("Chrome")
            || ($0.bundleIdentifier ?? "").contains("chrome")
    }

    let floating = floatingWindowRects()

    for app in chromeApps {
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement] else { continue }

        for window in windows {
            if let info = extractPipInfo(from: window, floating: floating) {
                return info
            }
        }
    }

    return nil
}

private func extractPipInfo(from window: AXUIElement, floating: [CGRect]) -> PipWindowInfo? {
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

    // Document PiP: untitled, landscape, AND confirmed floating (above normal window level).
    // The floating check prevents matching Chrome popups like the omnibox dropdown.
    let matchesFloat = floating.contains { r in
        abs(r.origin.x - pos.x) < 3 && abs(r.origin.y - pos.y) < 3
            && abs(r.width - size.width) < 3 && abs(r.height - size.height) < 3
    }
    let isDocPip = (title == "" || title == "about:blank")
        && matchesFloat
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
                + "\"glowColor\":\"\(settings.glowColor)\","
                + "\"hotkeyCode\":\(settings.hotkeyCode),"
                + "\"hotkeyFlags\":\(settings.hotkeyFlags),"
                + "\"audioLevel\":\(String(format: "%.3f", audioMonitor.level)),"
                + "\"pong\":\(pong.active),"
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

        if firstLine.contains("POST /pong") {
            let sema = DispatchSemaphore(value: 0)
            DispatchQueue.main.async {
                daemon.togglePong()
                sema.signal()
            }
            sema.wait()
            return "{\"pong\":\(pong.active)}"
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
        if let gc = json["glowColor"] as? String { settings.glowColor = gc }
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
    private var gotFirstBuffer = false

    func start() {
        DispatchQueue.global(qos: .userInitiated).async {
            self.startAsync()
        }
    }

    private func startAsync() {
        let sema = DispatchSemaphore(value: 0)
        var content: SCShareableContent?
        var fetchError: Error?

        SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: false) { result, error in
            content = result
            fetchError = error
            sema.signal()
        }
        sema.wait()

        if let error = fetchError {
            print("Audio: failed to get content - \(error.localizedDescription)")
            return
        }
        guard let display = content?.displays.first else {
            print("Audio: no displays found")
            return
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.sampleRate = 48000
        config.channelCount = 2
        config.width = 2
        config.height = 2

        let s = SCStream(filter: filter, configuration: config, delegate: self)
        do {
            try s.addStreamOutput(self, type: .audio, sampleHandlerQueue: .global(qos: .userInteractive))
        } catch {
            print("Audio: failed to add output - \(error.localizedDescription)")
            return
        }

        let startSema = DispatchSemaphore(value: 0)
        var startError: Error?
        s.startCapture { error in
            startError = error
            startSema.signal()
        }
        startSema.wait()

        if let error = startError {
            print("Audio: failed to start capture - \(error.localizedDescription)")
            return
        }

        stream = s
        print("Audio: stream started")
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer buf: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }

        if !gotFirstBuffer {
            gotFirstBuffer = true
            print("Audio: receiving buffers")
        }

        guard let block = CMSampleBufferGetDataBuffer(buf) else { return }
        var length = 0
        var ptr: UnsafeMutablePointer<Int8>?
        CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil,
                                    totalLengthOut: &length, dataPointerOut: &ptr)
        guard let raw = ptr, length > 0 else { return }

        let floatCount = length / MemoryLayout<Float>.size
        guard floatCount > 0 else { return }

        var sum: Float = 0
        raw.withMemoryRebound(to: Float.self, capacity: floatCount) { floats in
            for i in 0..<floatCount {
                sum += floats[i] * floats[i]
            }
        }
        let rms = CGFloat(sqrt(sum / Float(floatCount)))
        let scaled = min(rms * 8, 1.0)
        smoothed = smoothed * 0.3 + scaled * 0.7
        level = smoothed
    }

    func stream(_ s: SCStream, didStopWithError error: Error) {
        print("Audio: stream stopped - \(error.localizedDescription)")
    }
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
    private let borderWidth: CGFloat = 2.5
    private let containerLayer = CALayer()
    private let gradientLayer = CAGradientLayer()
    private let maskLayer = CAShapeLayer()
    private var currentColor = ""

    private static let colorSets: [String: [CGColor]] = [
        "rainbow": [
            NSColor.red.cgColor, NSColor.yellow.cgColor, NSColor.green.cgColor,
            NSColor.cyan.cgColor, NSColor.blue.cgColor, NSColor.magenta.cgColor,
            NSColor.red.cgColor,
        ],
        "blue": [
            NSColor(red: 0.2, green: 0.5, blue: 1.0, alpha: 1).cgColor,
            NSColor(red: 0.1, green: 0.8, blue: 1.0, alpha: 1).cgColor,
            NSColor(red: 0.4, green: 0.6, blue: 1.0, alpha: 1).cgColor,
            NSColor(red: 0.0, green: 0.3, blue: 0.9, alpha: 1).cgColor,
            NSColor(red: 0.2, green: 0.5, blue: 1.0, alpha: 1).cgColor,
        ],
        "red": [
            NSColor(red: 1.0, green: 0.2, blue: 0.2, alpha: 1).cgColor,
            NSColor(red: 1.0, green: 0.5, blue: 0.3, alpha: 1).cgColor,
            NSColor(red: 1.0, green: 0.1, blue: 0.4, alpha: 1).cgColor,
            NSColor(red: 0.8, green: 0.0, blue: 0.1, alpha: 1).cgColor,
            NSColor(red: 1.0, green: 0.2, blue: 0.2, alpha: 1).cgColor,
        ],
        "purple": [
            NSColor(red: 0.7, green: 0.3, blue: 1.0, alpha: 1).cgColor,
            NSColor(red: 1.0, green: 0.4, blue: 0.8, alpha: 1).cgColor,
            NSColor(red: 0.5, green: 0.2, blue: 0.9, alpha: 1).cgColor,
            NSColor(red: 0.8, green: 0.5, blue: 1.0, alpha: 1).cgColor,
            NSColor(red: 0.7, green: 0.3, blue: 1.0, alpha: 1).cgColor,
        ],
        "green": [
            NSColor(red: 0.1, green: 0.9, blue: 0.4, alpha: 1).cgColor,
            NSColor(red: 0.3, green: 1.0, blue: 0.7, alpha: 1).cgColor,
            NSColor(red: 0.0, green: 0.7, blue: 0.3, alpha: 1).cgColor,
            NSColor(red: 0.2, green: 1.0, blue: 0.5, alpha: 1).cgColor,
            NSColor(red: 0.1, green: 0.9, blue: 0.4, alpha: 1).cgColor,
        ],
    ]

    /// rect is in AX coordinates (origin top-left, Y down).
    func show(around rect: CGRect) {
        let screenH = (NSScreen.main ?? NSScreen.screens[0]).frame.height

        // Convert AX coords → NSWindow frame (origin bottom-left, Y up)
        let nsFrame = NSRect(
            x: rect.origin.x - borderWidth,
            y: screenH - (rect.origin.y + rect.height) - borderWidth,
            width: rect.width + borderWidth * 2,
            height: rect.height + borderWidth * 2)

        if window == nil {
            let w = NSWindow(contentRect: nsFrame, styleMask: .borderless,
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

        // Update gradient colors if changed
        let color = settings.glowColor
        if color != currentColor {
            currentColor = color
            gradientLayer.colors = Self.colorSets[color] ?? Self.colorSets["rainbow"]!
        }

        window?.setFrame(nsFrame, display: true)

        // Disable implicit CoreAnimation transitions — all updates must be instant
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let viewBounds = NSRect(origin: .zero, size: nsFrame.size)
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

        CATransaction.commit()
    }

    func pulse(_ level: CGFloat) {
        containerLayer.opacity = Float(0.5 + level * 0.5)
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

// MARK: - Pong Mode

class PongGame {
    var active = false
    var lastBounds = CGRect.zero

    private var velocity = CGPoint.zero
    private let baseSpeed: CGFloat = 420.0
    private let maxSpeed: CGFloat = 900.0

    private var playerPaddle: NSWindow?
    private var aiPaddle: NSWindow?
    private var scoreOverlay: NSWindow?
    private var scoreLabel: NSTextField?

    private let paddleWidth: CGFloat = 8
    private let paddleMargin: CGFloat = 20
    private var paddleHeight: CGFloat = 150

    private var playerScore = 0
    private var aiScore = 0
    private var aiY: CGFloat = 0
    private let aiSpeed: CGFloat = 300.0

    private var pauseUntil: UInt64 = 0
    private var lastMach: UInt64 = 0
    private var ballPos = CGPoint.zero
    private var scoreChanged = false

    // Cached PiP reference — avoids findPipWindow() every frame
    private var cachedAXWindow: AXUIElement?
    private var cachedPipSize = CGSize.zero

    // Direct references for border/audio
    private var borderRef: RGBBorder?
    private var audioRef: AudioMonitor?

    // High-frequency timer on main queue — keeps PiP + border perfectly synchronized
    private var gameTimer: DispatchSourceTimer?

    private static var timebaseInfo: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    private func machToSeconds(_ ticks: UInt64) -> CGFloat {
        let info = Self.timebaseInfo
        return CGFloat(Double(ticks) * Double(info.numer) / Double(info.denom) / 1_000_000_000)
    }

    private func secondsToMach(_ sec: Double) -> UInt64 {
        let info = Self.timebaseInfo
        return UInt64(sec * 1_000_000_000) * UInt64(info.denom) / UInt64(info.numer)
    }

    func start(screen: CGRect, pip: PipWindowInfo, border: RGBBorder, audio: AudioMonitor) {
        playerScore = 0
        aiScore = 0
        scoreChanged = false
        paddleHeight = screen.height * 0.15
        aiY = screen.midY - paddleHeight / 2
        lastMach = mach_absolute_time()
        pauseUntil = 0

        cachedAXWindow = pip.axWindow
        cachedPipSize = pip.bounds.size
        ballPos = pip.bounds.origin
        borderRef = border
        audioRef = audio

        launchBall(direction: Bool.random() ? 1 : -1)

        if Thread.isMainThread {
            createOverlays(screen: screen)
        } else {
            DispatchQueue.main.sync { self.createOverlays(screen: screen) }
        }

        active = true
        print("Pong started")

        // 500fps on main queue — PiP move + border move happen in the SAME call,
        // microseconds apart, so they never desync
        let t = DispatchSource.makeTimerSource(flags: .strict, queue: .main)
        t.schedule(deadline: .now(), repeating: .milliseconds(2), leeway: .microseconds(100))
        t.setEventHandler { [weak self] in self?.gameTick() }
        gameTimer = t
        t.resume()
    }

    private func gameTick() {
        guard active, let axWindow = cachedAXWindow else { return }

        guard let event = CGEvent(source: nil) else { return }
        let mousePos = event.location
        let screen = getScreenFrame()
        let size = cachedPipSize

        let now = mach_absolute_time()
        let dt = min(machToSeconds(now - lastMach), 0.05)
        lastMach = now

        // Pause after score — paddles still track mouse
        if pauseUntil > 0 {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            updatePaddlePositions(playerY: mousePos.y - paddleHeight / 2, screen: screen)
            let bounds = CGRect(origin: ballPos, size: size)
            lastBounds = bounds
            updateBorder(bounds)
            if scoreChanged { updateScore(); scoreChanged = false }
            CATransaction.commit()
            if now < pauseUntil { return }
            pauseUntil = 0
        }

        // Physics
        ballPos.x += velocity.x * dt
        ballPos.y += velocity.y * dt

        if ballPos.y <= screen.minY {
            ballPos.y = screen.minY
            velocity.y = abs(velocity.y)
        }
        if ballPos.y + size.height >= screen.maxY {
            ballPos.y = screen.maxY - size.height
            velocity.y = -abs(velocity.y)
        }

        let spd = sqrt(velocity.x * velocity.x + velocity.y * velocity.y)
        if spd > maxSpeed {
            let s = maxSpeed / spd
            velocity.x *= s
            velocity.y *= s
        }

        let pX = screen.minX + paddleMargin
        let pY = max(screen.minY, min(screen.maxY - paddleHeight, mousePos.y - paddleHeight / 2))

        let aiX = screen.maxX - paddleMargin - paddleWidth
        let ballCY = ballPos.y + size.height / 2
        let aiTarget = ballCY - paddleHeight / 2
        let aiDiff = aiTarget - aiY
        aiY += max(-aiSpeed * dt, min(aiSpeed * dt, aiDiff))
        aiY = max(screen.minY, min(screen.maxY - paddleHeight, aiY))

        if ballPos.x <= pX + paddleWidth && ballPos.x >= pX - size.width / 2 && velocity.x < 0 {
            if ballCY >= pY && ballCY <= pY + paddleHeight {
                velocity.x = abs(velocity.x) * 1.05
                let hit = (ballCY - pY) / paddleHeight - 0.5
                velocity.y += hit * 200
                ballPos.x = pX + paddleWidth
            }
        }

        if ballPos.x + size.width >= aiX && ballPos.x + size.width <= aiX + paddleWidth + size.width / 2 && velocity.x > 0 {
            if ballCY >= aiY && ballCY <= aiY + paddleHeight {
                velocity.x = -(abs(velocity.x) * 1.05)
                let hit = (ballCY - aiY) / paddleHeight - 0.5
                velocity.y += hit * 200
                ballPos.x = aiX - size.width
            }
        }

        if ballPos.x + size.width < screen.minX - 30 {
            aiScore += 1
            scoreChanged = true
            ballPos = CGPoint(x: screen.midX - size.width / 2, y: screen.midY - size.height / 2)
            launchBall(direction: 1)
            pauseUntil = mach_absolute_time() + secondsToMach(0.8)
        }

        if ballPos.x > screen.maxX + 30 {
            playerScore += 1
            scoreChanged = true
            ballPos = CGPoint(x: screen.midX - size.width / 2, y: screen.midY - size.height / 2)
            launchBall(direction: -1)
            pauseUntil = mach_absolute_time() + secondsToMach(0.8)
        }

        // Move PiP THEN border — same thread, microseconds apart, perfectly synced
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

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        updatePaddlePositions(playerY: pY, screen: screen)
        updateBorder(bounds)
        if scoreChanged { updateScore(); scoreChanged = false }
        CATransaction.commit()
    }

    private func updateBorder(_ bounds: CGRect) {
        if settings.glow, let border = borderRef {
            border.show(around: bounds)
            border.pulse(audioRef?.level ?? 0)
        } else {
            borderRef?.hide()
        }
    }

    func stop() {
        gameTimer?.cancel()
        gameTimer = nil
        active = false
        ballPos = .zero
        lastMach = 0
        cachedAXWindow = nil
        borderRef?.hide()
        borderRef = nil
        audioRef = nil

        let pw = playerPaddle, aw = aiPaddle, sw = scoreOverlay
        let cleanup = {
            pw?.orderOut(nil)
            aw?.orderOut(nil)
            sw?.orderOut(nil)
        }
        if Thread.isMainThread { cleanup() }
        else { DispatchQueue.main.async { cleanup() } }
        playerPaddle = nil
        aiPaddle = nil
        scoreOverlay = nil
        scoreLabel = nil
        print("Pong stopped")
    }

    private func launchBall(direction: CGFloat) {
        let angle = CGFloat.random(in: -0.4...0.4)
        velocity = CGPoint(x: baseSpeed * direction, y: baseSpeed * sin(angle))
    }

    private func createOverlays(screen: CGRect) {
        let h = (NSScreen.main ?? NSScreen.screens[0]).frame.height

        playerPaddle = makePaddleWindow(
            nsFrame: NSRect(x: screen.minX + paddleMargin,
                            y: h - screen.midY - paddleHeight / 2,
                            width: paddleWidth, height: paddleHeight))

        aiPaddle = makePaddleWindow(
            nsFrame: NSRect(x: screen.maxX - paddleMargin - paddleWidth,
                            y: h - screen.midY - paddleHeight / 2,
                            width: paddleWidth, height: paddleHeight))

        let sw = NSWindow(contentRect: NSRect(x: screen.midX - 80, y: h - 55, width: 160, height: 44),
                          styleMask: .borderless, backing: .buffered, defer: false)
        sw.isOpaque = false
        sw.backgroundColor = NSColor.black.withAlphaComponent(0.6)
        sw.level = .floating
        sw.ignoresMouseEvents = true
        sw.hasShadow = false
        sw.collectionBehavior = [.canJoinAllSpaces, .stationary]

        let label = NSTextField(frame: NSRect(x: 0, y: 0, width: 160, height: 44))
        label.isEditable = false
        label.isBordered = false
        label.backgroundColor = .clear
        label.textColor = .white
        label.font = NSFont.monospacedSystemFont(ofSize: 24, weight: .bold)
        label.alignment = .center
        label.stringValue = "0 : 0"
        sw.contentView!.addSubview(label)
        sw.orderFrontRegardless()

        scoreOverlay = sw
        scoreLabel = label
    }

    private func makePaddleWindow(nsFrame: NSRect) -> NSWindow {
        let w = NSWindow(contentRect: nsFrame, styleMask: .borderless, backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.level = .floating
        w.ignoresMouseEvents = true
        w.hasShadow = false
        w.collectionBehavior = [.canJoinAllSpaces, .stationary]
        w.contentView!.wantsLayer = true
        w.contentView!.layer!.backgroundColor = NSColor.white.cgColor
        w.contentView!.layer!.cornerRadius = paddleWidth / 2
        w.orderFrontRegardless()
        return w
    }

    private func updatePaddlePositions(playerY: CGFloat, screen: CGRect) {
        let h = (NSScreen.main ?? NSScreen.screens[0]).frame.height

        playerPaddle?.setFrame(
            NSRect(x: screen.minX + paddleMargin, y: h - playerY - paddleHeight,
                   width: paddleWidth, height: paddleHeight), display: true)

        let aY = max(screen.minY, min(screen.maxY - paddleHeight, aiY))
        aiPaddle?.setFrame(
            NSRect(x: screen.maxX - paddleMargin - paddleWidth, y: h - aY - paddleHeight,
                   width: paddleWidth, height: paddleHeight), display: true)
    }

    private func updateScore() {
        scoreLabel?.stringValue = "\(playerScore) : \(aiScore)"
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
    private var animCurrentPos = CGPoint.zero  // computed position, updated by stepAnimation
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

        audioMonitor = audio
        audio.start()
        installHotkey()
        print("xpip daemon started")

        Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func tick() {
        // Pong and dodge animation have their own high-frequency timers.
        // Bail immediately — don't block main queue with expensive AX IPC.
        if pong.active || animating { return }

        guard let event = CGEvent(source: nil) else { return }
        let mousePos = event.location

        guard let pip = findPipWindow() else {
            interacting = false
            wasOnPip = false
            rgbBorder.hide()
            return
        }

        // Normal mode — border tracks real AX position
        if settings.glow {
            rgbBorder.show(around: pip.bounds)
            rgbBorder.pulse(audio.level)
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

        // Move PiP via AX, then IMMEDIATELY move border — same call, microseconds apart
        if let win = animWindow, let val = AXValueCreate(.cgPoint, &pos) {
            AXUIElementSetAttributeValue(win, kAXPositionAttribute as CFString, val)
        }
        if settings.glow {
            rgbBorder.show(around: CGRect(origin: pos, size: animSize))
            rgbBorder.pulse(audio.level)
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

    func togglePong() {
        if pong.active {
            pong.stop()
            rgbBorder.hide()
        } else if let pip = findPipWindow() {
            pong.start(screen: getScreenFrame(), pip: pip, border: rgbBorder, audio: audio)
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

setbuf(stdout, nil)
setbuf(stderr, nil)

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
