import Cocoa

enum Uninstaller {
    static func confirmAndUninstall() {
        let alert = NSAlert()
        alert.messageText = "Uninstall PipBounce?"
        alert.informativeText = "This will stop the daemon and remove all PipBounce files.\n\nThe Chrome extension must be removed separately from chrome://extensions."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Uninstall")
        alert.addButton(withTitle: "Cancel")

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()

        if response == .alertFirstButtonReturn {
            performUninstall()
            exit(0)
        }
    }

    static func performUninstall() {
        let label = "com.pipbounce.daemon"
        let plistPath = NSString(string: "~/Library/LaunchAgents/\(label).plist").expandingTildeInPath
        let installDir = NSString(string: "~/.pipbounce").expandingTildeInPath
        let fm = FileManager.default

        // 1. Bootout launchd agent
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        proc.arguments = ["bootout", "gui/\(getuid())/\(label)"]
        try? proc.run()
        proc.waitUntilExit()

        // 2. Remove plist
        try? fm.removeItem(atPath: plistPath)

        // 3. Remove install directory
        try? fm.removeItem(atPath: installDir)

        print("PipBounce uninstalled.")
    }
}
