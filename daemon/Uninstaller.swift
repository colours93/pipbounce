import Cocoa

enum Uninstaller {
    static func confirmAndUninstall() {
        let alert = NSAlert()
        alert.messageText = "Uninstall XPip?"
        alert.informativeText = "This will stop the daemon and remove all XPip files.\n\nThe Chrome extension must be removed separately from chrome://extensions."
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
        let labels = ["com.xpip.daemon", "com.pipbounce.daemon"]
        let installDirs = ["~/.xpip", "~/.pipbounce"].map { NSString(string: $0).expandingTildeInPath }
        let fm = FileManager.default

        // 1. Bootout launchd agent(s) and remove plist(s).
        for label in labels {
            let plistPath = NSString(string: "~/Library/LaunchAgents/\(label).plist").expandingTildeInPath
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            proc.arguments = ["bootout", "gui/\(getuid())/\(label)"]
            try? proc.run()
            proc.waitUntilExit()
            try? fm.removeItem(atPath: plistPath)
        }

        // 2. Remove install directories (new + legacy).
        for installDir in installDirs {
            try? fm.removeItem(atPath: installDir)
        }

        print("XPip uninstalled.")
    }
}
