import Cocoa
import ApplicationServices

// MARK: - Settings

class Settings {
    var enabled = true
    var dodgeDistance: CGFloat = 200
    var cooldown: TimeInterval = 0.4
    var margin: CGFloat = 20
    var cornerSize: CGFloat = 100
}

let settings = Settings()

// MARK: - PiP Window Discovery

struct PipWindowInfo {
    let pid: pid_t
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
            if let info = extractPipInfo(from: window, pid: app.processIdentifier) {
                return info
            }
        }
    }

    return nil
}

private func extractPipInfo(from window: AXUIElement, pid: pid_t) -> PipWindowInfo? {
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
    return PipWindowInfo(pid: pid, bounds: bounds, axWindow: window)
}

// MARK: - Window Movement

func movePipWindow(_ pip: PipWindowInfo, to target: CGPoint) -> Bool {
    var newPos = target
    let posVal = AXValueCreate(.cgPoint, &newPos)!
    return AXUIElementSetAttributeValue(pip.axWindow, kAXPositionAttribute as CFString, posVal) == .success
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
                + "\"dodgeDistance\":\(Int(settings.dodgeDistance)),"
                + "\"cooldown\":\(settings.cooldown),"
                + "\"margin\":\(Int(settings.margin)),"
                + "\"cornerSize\":\(Int(settings.cornerSize)),"
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
                + "\"dodgeDistance\":\(Int(settings.dodgeDistance)),"
                + "\"cooldown\":\(settings.cooldown),"
                + "\"margin\":\(Int(settings.margin)),"
                + "\"cornerSize\":\(Int(settings.cornerSize))}"
        }

        return nil
    }

    private func applySettings(from body: String) {
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        if let d = json["dodgeDistance"] as? Double { settings.dodgeDistance = CGFloat(d) }
        if let c = json["cooldown"] as? Double { settings.cooldown = c }
        if let m = json["margin"] as? Double { settings.margin = CGFloat(m) }
        if let e = json["enabled"] as? Bool { settings.enabled = e }
        if let cs = json["cornerSize"] as? Double { settings.cornerSize = CGFloat(cs) }

        print("Settings updated: distance=\(Int(settings.dodgeDistance))"
              + " cooldown=\(settings.cooldown)"
              + " margin=\(Int(settings.margin))"
              + " cornerSize=\(Int(settings.cornerSize))"
              + " enabled=\(settings.enabled)")
    }
}

// MARK: - Dodge Daemon

class XPipDaemon {
    private var lastDodgeTime = Date.distantPast
    private var interacting = false
    private var wasOnPip = false

    func start() {
        if !AXIsProcessTrusted() {
            print("Accessibility permission required")
            let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
            AXIsProcessTrustedWithOptions(opts)
        }

        print("xpip daemon started")

        Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func tick() {
        guard settings.enabled,
              let event = CGEvent(source: nil) else { return }

        let mousePos = event.location

        guard let pip = findPipWindow() else {
            interacting = false
            wasOnPip = false
            return
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

    private func dodgeIfReady(pip: PipWindowInfo, mousePos: CGPoint) {
        let now = Date()
        guard now.timeIntervalSince(lastDodgeTime) >= settings.cooldown else { return }

        let screen = getScreenFrame()
        let target = getFurthestCorner(from: mousePos, windowSize: pip.bounds.size, screen: screen)

        // Skip if the window is already at the target corner.
        let alreadyThere = abs(pip.bounds.origin.x - target.x) < 30
            && abs(pip.bounds.origin.y - target.y) < 30
        guard !alreadyThere else { return }

        if movePipWindow(pip, to: target) {
            lastDodgeTime = now
        }
    }

    /// Returns true when the mouse is in one of the four corner zones of the PiP window,
    /// allowing the user to interact (resize/close) without triggering a dodge.
    private func isInPipCorner(mousePos: CGPoint, pipBounds: CGRect) -> Bool {
        let cs = settings.cornerSize
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
