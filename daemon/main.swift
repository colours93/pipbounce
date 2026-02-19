import Cocoa

let pidPath = NSString("~/.pipbounce/pipbounce.pid").expandingTildeInPath

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

setbuf(stdout, nil)
setbuf(stderr, nil)

killExisting()
writePid()

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

settings.load()
let server = ControlServer()
server.start()
let daemon = PipBounceDaemon()

signal(SIGINT) { _ in cleanup(); exit(0) }
signal(SIGTERM) { _ in cleanup(); exit(0) }

DispatchQueue.main.async {
    daemon.start()
}

app.run()
