import Cocoa

class OnboardingWindow {
    private var window: NSWindow?
    private var statusLabel: NSTextField?
    private var pollTimer: DispatchSourceTimer?

    func show() {
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 320),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        w.title = "XPip Setup"
        w.center()
        w.isReleasedWhenClosed = false
        w.level = .floating

        let content = NSView(frame: w.contentView!.bounds)
        content.autoresizingMask = [.width, .height]
        w.contentView = content

        var y: CGFloat = 280

        // Title
        let title = makeLabel("XPip needs Accessibility access", bold: true, size: 16)
        title.frame = NSRect(x: 20, y: y, width: 380, height: 24)
        content.addSubview(title)
        y -= 12

        // Explanation
        let explanation = makeLabel(
            "Accessibility permission lets XPip detect and move\n"
            + "Picture-in-Picture windows when your cursor approaches.",
            bold: false, size: 13
        )
        explanation.frame = NSRect(x: 20, y: y - 40, width: 380, height: 40)
        content.addSubview(explanation)
        y -= 64

        // Steps
        let steps = [
            "1. Click the button below to open System Settings",
            "2. Click the lock 🔒 to make changes (if locked)",
            "3. Click \"+\" and add XPip, or toggle it on",
        ]
        for step in steps {
            let label = makeLabel(step, bold: false, size: 13)
            label.frame = NSRect(x: 30, y: y, width: 360, height: 20)
            content.addSubview(label)
            y -= 24
        }

        // Path hint
        y -= 4
        let pathLabel = makeLabel(
            "App location: ~/.xpip/xpip.app",
            bold: false, size: 11
        )
        pathLabel.textColor = .secondaryLabelColor
        pathLabel.frame = NSRect(x: 30, y: y, width: 360, height: 16)
        content.addSubview(pathLabel)
        y -= 32

        // Open Settings button
        let button = NSButton(frame: NSRect(x: 120, y: y, width: 180, height: 32))
        button.title = "Open Accessibility Settings"
        button.bezelStyle = .rounded
        button.target = self
        button.action = #selector(openSettings)
        content.addSubview(button)
        y -= 40

        // Status indicator
        let status = makeLabel("⏳ Waiting for permission…", bold: false, size: 13)
        status.frame = NSRect(x: 20, y: y, width: 380, height: 20)
        status.alignment = .center
        content.addSubview(status)
        statusLabel = status

        window = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        startPolling()
    }

    private func startPolling() {
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + 1, repeating: 1)
        t.setEventHandler { [weak self] in
            if AXIsProcessTrusted() {
                self?.onGranted()
            }
        }
        t.resume()
        pollTimer = t
    }

    private func onGranted() {
        pollTimer?.cancel()
        pollTimer = nil
        statusLabel?.stringValue = "✅ Permission granted!"

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.window?.close()
            self?.window = nil
        }
    }

    @objc private func openSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    private func makeLabel(_ text: String, bold: Bool, size: CGFloat) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = bold ? NSFont.boldSystemFont(ofSize: size) : NSFont.systemFont(ofSize: size)
        label.maximumNumberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        return label
    }
}
