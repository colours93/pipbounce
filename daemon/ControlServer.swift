import Foundation

class ControlServer {
    private let port: UInt16 = 51789
    private var serverSocket: Int32 = -1
    private let clientQueue = DispatchQueue(label: "com.pipbounce.clients", attributes: .concurrent)

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
                clientQueue.async { [self] in
                    self.handleClient(client)
                }
            }
        }
    }

    private func handleClient(_ fd: Int32) {
        defer { close(fd) }

        // Set 2-second read timeout
        var tv = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        var buffer = [UInt8](repeating: 0, count: 8192)
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

    private func toggleOnMain(_ game: MiniGame) {
        let sema = DispatchSemaphore(value: 0)
        DispatchQueue.main.async { daemon.toggleGame(game); sema.signal() }
        sema.wait()
    }

    private func routeRequest(firstLine: String, body: String) -> String? {
        if firstLine.contains("GET /status") {
            var result = ""
            let sema = DispatchSemaphore(value: 0)
            DispatchQueue.main.async {
                let pip = findPipWindow()
                let bounce = Games.bounce
                var parts = [
                    "\"enabled\":\(settings.enabled)",
                    "\"cooldown\":\(settings.cooldown)",
                    "\"margin\":\(Int(settings.margin))",
                    "\"cornerSize\":\(Int(settings.cornerSize))",
                    "\"glow\":\(settings.glow)",
                    "\"glowColor\":\"\(settings.glowColor)\"",
                    "\"hotkeyCode\":\(settings.hotkeyCode)",
                    "\"hotkeyFlags\":\(settings.hotkeyFlags)",
                ]
                for (name, game) in Games.all {
                    parts.append("\"\(name)\":\(game.active)")
                }
                parts.append("\"bounceAuto\":\(bounce.active && !bounce.paddleMode)")
                parts.append("\"bouncePaddle\":\(bounce.active && bounce.paddleMode)")
                parts.append("\"pipActive\":\(pip != nil)")
                result = "{\(parts.joined(separator: ","))}"
                sema.signal()
            }
            sema.wait()
            return result
        }

        if firstLine.contains("GET /debug") { return debugPipDiscovery() }

        if firstLine.contains("POST /toggle") {
            settings.enabled.toggle()
            print(settings.enabled ? "Dodge enabled" : "Dodge paused")
            return "{\"enabled\":\(settings.enabled)}"
        }

        if firstLine.contains("POST /restart") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { cleanup(); exit(0) }
            return "{\"restarting\":true}"
        }

        // Bounce has special paddle-mode handling
        if firstLine.contains("POST /bounce-paddle") {
            let bounce = Games.bounce
            let sema = DispatchSemaphore(value: 0)
            DispatchQueue.main.async { bounce.paddleMode = true; daemon.toggleGame(bounce); sema.signal() }
            sema.wait()
            return "{\"bouncePaddle\":\(bounce.active)}"
        }
        if firstLine.contains("POST /bounce") {
            let bounce = Games.bounce
            let sema = DispatchSemaphore(value: 0)
            DispatchQueue.main.async { bounce.paddleMode = false; daemon.toggleGame(bounce); sema.signal() }
            sema.wait()
            return "{\"bounceAuto\":\(bounce.active)}"
        }

        // Generic game toggle: match "POST /<name>" against registry
        // Check pipong2 before pipong so "/pipong2" doesn't match "/pipong"
        let orderedKeys = Games.all.keys.sorted { $0.count > $1.count }
        for name in orderedKeys {
            if name == "bounce" { continue } // handled above
            if firstLine.contains("POST /\(name)"), let game = Games.all[name] {
                toggleOnMain(game)
                return "{\"\(name)\":\(game.active)}"
            }
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

        settings.save()
        print("Settings updated: cooldown=\(settings.cooldown)"
              + " margin=\(Int(settings.margin))"
              + " cornerSize=\(Int(settings.cornerSize))"
              + " enabled=\(settings.enabled)")
    }
}
