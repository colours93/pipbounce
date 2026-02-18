import Foundation

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
                + "\"pong\":\(pong.active),"
                + "\"flappy\":\(flappy.active),"
                + "\"bounce\":\(bounce.active),"
                + "\"bounceAuto\":\(bounce.active && !bounce.paddleMode),"
                + "\"bouncePaddle\":\(bounce.active && bounce.paddleMode),"
                + "\"invaders\":\(invaders.active),"
                + "\"frogger\":\(frogger.active),"
                + "\"runner\":\(runner.active),"
                + "\"snake\":\(snake.active),"
                + "\"breakout\":\(breakout.active),"
                + "\"asteroids\":\(asteroids.active),"
                + "\"cursorhunt\":\(cursorhunt.active),"
                + "\"doodlejump\":\(doodlejump.active),"
                + "\"pacman\":\(pacman.active),"
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
                daemon.toggleGame(pong)
                sema.signal()
            }
            sema.wait()
            return "{\"pong\":\(pong.active)}"
        }

        if firstLine.contains("POST /flappy") {
            let sema = DispatchSemaphore(value: 0)
            DispatchQueue.main.async {
                daemon.toggleGame(flappy)
                sema.signal()
            }
            sema.wait()
            return "{\"flappy\":\(flappy.active)}"
        }

        if firstLine.contains("POST /bounce-paddle") {
            let sema = DispatchSemaphore(value: 0)
            DispatchQueue.main.async {
                bounce.paddleMode = true
                daemon.toggleGame(bounce)
                sema.signal()
            }
            sema.wait()
            return "{\"bouncePaddle\":\(bounce.active)}"
        }

        if firstLine.contains("POST /bounce") {
            let sema = DispatchSemaphore(value: 0)
            DispatchQueue.main.async {
                bounce.paddleMode = false
                daemon.toggleGame(bounce)
                sema.signal()
            }
            sema.wait()
            return "{\"bounceAuto\":\(bounce.active)}"
        }

        if firstLine.contains("POST /invaders") {
            let sema = DispatchSemaphore(value: 0)
            DispatchQueue.main.async {
                daemon.toggleGame(invaders)
                sema.signal()
            }
            sema.wait()
            return "{\"invaders\":\(invaders.active)}"
        }

        if firstLine.contains("POST /frogger") {
            let sema = DispatchSemaphore(value: 0)
            DispatchQueue.main.async { daemon.toggleGame(frogger); sema.signal() }
            sema.wait()
            return "{\"frogger\":\(frogger.active)}"
        }

        if firstLine.contains("POST /runner") {
            let sema = DispatchSemaphore(value: 0)
            DispatchQueue.main.async { daemon.toggleGame(runner); sema.signal() }
            sema.wait()
            return "{\"runner\":\(runner.active)}"
        }

        if firstLine.contains("POST /snake") {
            let sema = DispatchSemaphore(value: 0)
            DispatchQueue.main.async { daemon.toggleGame(snake); sema.signal() }
            sema.wait()
            return "{\"snake\":\(snake.active)}"
        }

        if firstLine.contains("POST /breakout") {
            let sema = DispatchSemaphore(value: 0)
            DispatchQueue.main.async { daemon.toggleGame(breakout); sema.signal() }
            sema.wait()
            return "{\"breakout\":\(breakout.active)}"
        }

        if firstLine.contains("POST /asteroids") {
            let sema = DispatchSemaphore(value: 0)
            DispatchQueue.main.async { daemon.toggleGame(asteroids); sema.signal() }
            sema.wait()
            return "{\"asteroids\":\(asteroids.active)}"
        }

        if firstLine.contains("POST /cursorhunt") {
            let sema = DispatchSemaphore(value: 0)
            DispatchQueue.main.async { daemon.toggleGame(cursorhunt); sema.signal() }
            sema.wait()
            return "{\"cursorhunt\":\(cursorhunt.active)}"
        }

        if firstLine.contains("POST /doodlejump") {
            let sema = DispatchSemaphore(value: 0)
            DispatchQueue.main.async { daemon.toggleGame(doodlejump); sema.signal() }
            sema.wait()
            return "{\"doodlejump\":\(doodlejump.active)}"
        }

        if firstLine.contains("POST /pacman") {
            let sema = DispatchSemaphore(value: 0)
            DispatchQueue.main.async { daemon.toggleGame(pacman); sema.signal() }
            sema.wait()
            return "{\"pacman\":\(pacman.active)}"
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
