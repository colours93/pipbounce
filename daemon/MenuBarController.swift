import Cocoa

class MenuBarController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()

    // Menu items that need state updates
    private var dodgeItem: NSMenuItem!
    private var glowItem: NSMenuItem!
    private var accessibilityItem: NSMenuItem!
    private var gameItems: [(NSMenuItem, () -> Bool)] = []

    func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            if #available(macOS 11.0, *) {
                button.image = NSImage(systemSymbolName: "pip", accessibilityDescription: "XPip")
            } else {
                button.title = "XP"
            }
        }

        buildMenu()
        statusItem.menu = menu
        menu.delegate = self
    }

    private func buildMenu() {
        // Title + version
        let titleItem = NSMenuItem(title: "XPip", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        titleItem.attributedTitle = NSAttributedString(
            string: "XPip",
            attributes: [.font: NSFont.boldSystemFont(ofSize: 13)]
        )
        menu.addItem(titleItem)

        menu.addItem(NSMenuItem.separator())

        // Dodge toggle
        dodgeItem = NSMenuItem(title: "Dodge", action: #selector(toggleDodge), keyEquivalent: "")
        dodgeItem.target = self
        menu.addItem(dodgeItem)

        // Glow toggle
        glowItem = NSMenuItem(title: "Glow", action: #selector(toggleGlow), keyEquivalent: "")
        glowItem.target = self
        menu.addItem(glowItem)

        menu.addItem(NSMenuItem.separator())

        // Games submenu
        let gamesItem = NSMenuItem(title: "Games", action: nil, keyEquivalent: "")
        let gamesMenu = NSMenu()

        let gameEntries: [(String, MiniGame, Selector)] = [
            ("PiPong (1P)", Games.pipong, #selector(togglePipong)),
            ("PiPong (2P)", Games.pipong2, #selector(togglePipong2)),
            ("Flappy", Games.flappy, #selector(toggleFlappy)),
            ("Bounce (Auto)", Games.bounce, #selector(toggleBounceAuto)),
            ("Bounce (Paddle)", Games.bounce, #selector(toggleBouncePaddle)),
            ("Invaders", Games.invaders, #selector(toggleInvaders)),
            ("Frogger", Games.frogger, #selector(toggleFrogger)),
            ("Runner", Games.runner, #selector(toggleRunner)),
            ("Snake", Games.snake, #selector(toggleSnake)),
            ("Breakout", Games.breakout, #selector(toggleBreakout)),
            ("Asteroids", Games.asteroids, #selector(toggleAsteroids)),
            ("Cursor Hunt", Games.cursorhunt, #selector(toggleCursorHunt)),
            ("Doodle Jump", Games.doodlejump, #selector(toggleDoodleJump)),
            ("Pac-Man", Games.pacman, #selector(togglePacMan)),
        ]

        for (name, game, action) in gameEntries {
            let item = NSMenuItem(title: name, action: action, keyEquivalent: "")
            item.target = self
            gamesMenu.addItem(item)

            if name == "Bounce (Auto)" {
                gameItems.append((item, { Games.bounce.active && !Games.bounce.paddleMode }))
            } else if name == "Bounce (Paddle)" {
                gameItems.append((item, { Games.bounce.active && Games.bounce.paddleMode }))
            } else {
                gameItems.append((item, { game.active }))
            }
        }

        gamesItem.submenu = gamesMenu
        menu.addItem(gamesItem)

        menu.addItem(NSMenuItem.separator())

        // Accessibility status
        accessibilityItem = NSMenuItem(title: "Accessibility: Checking…", action: nil, keyEquivalent: "")
        accessibilityItem.isEnabled = false
        menu.addItem(accessibilityItem)

        menu.addItem(NSMenuItem.separator())

        // Restart
        let restartItem = NSMenuItem(title: "Restart Daemon", action: #selector(restartDaemon), keyEquivalent: "")
        restartItem.target = self
        menu.addItem(restartItem)

        // Uninstall
        let uninstallItem = NSMenuItem(title: "Uninstall…", action: #selector(uninstallApp), keyEquivalent: "")
        uninstallItem.target = self
        menu.addItem(uninstallItem)

        // Quit
        let quitItem = NSMenuItem(title: "Quit XPip", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    // MARK: - NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        // Update toggle states
        dodgeItem.state = settings.enabled ? .on : .off
        glowItem.state = settings.glow ? .on : .off

        // Update game checkmarks
        for (item, isActive) in gameItems {
            item.state = isActive() ? .on : .off
        }

        // Accessibility status
        if AXIsProcessTrusted() {
            accessibilityItem.title = "Accessibility: Granted"
        } else {
            accessibilityItem.title = "Accessibility: Required"
            accessibilityItem.attributedTitle = NSAttributedString(
                string: "⚠ Accessibility: Required",
                attributes: [.foregroundColor: NSColor.systemRed]
            )
        }

        // Dim icon when disabled
        statusItem.button?.alphaValue = settings.enabled ? 1.0 : 0.5
    }

    // MARK: - Actions

    @objc private func toggleDodge() {
        settings.enabled.toggle()
        settings.save()
        statusItem.button?.alphaValue = settings.enabled ? 1.0 : 0.5
        print(settings.enabled ? "Dodge enabled (menu)" : "Dodge paused (menu)")
    }

    @objc private func toggleGlow() {
        settings.glow.toggle()
        settings.save()
        print(settings.glow ? "Glow enabled (menu)" : "Glow disabled (menu)")
    }

    @objc private func togglePipong() { daemon.toggleGame(Games.pipong) }
    @objc private func togglePipong2() { daemon.toggleGame(Games.pipong2) }
    @objc private func toggleFlappy() { daemon.toggleGame(Games.flappy) }
    @objc private func toggleBounceAuto() { Games.bounce.paddleMode = false; daemon.toggleGame(Games.bounce) }
    @objc private func toggleBouncePaddle() { Games.bounce.paddleMode = true; daemon.toggleGame(Games.bounce) }
    @objc private func toggleInvaders() { daemon.toggleGame(Games.invaders) }
    @objc private func toggleFrogger() { daemon.toggleGame(Games.frogger) }
    @objc private func toggleRunner() { daemon.toggleGame(Games.runner) }
    @objc private func toggleSnake() { daemon.toggleGame(Games.snake) }
    @objc private func toggleBreakout() { daemon.toggleGame(Games.breakout) }
    @objc private func toggleAsteroids() { daemon.toggleGame(Games.asteroids) }
    @objc private func toggleCursorHunt() { daemon.toggleGame(Games.cursorhunt) }
    @objc private func toggleDoodleJump() { daemon.toggleGame(Games.doodlejump) }
    @objc private func togglePacMan() { daemon.toggleGame(Games.pacman) }

    @objc private func restartDaemon() {
        cleanup()
        exit(0) // launchd KeepAlive will restart
    }

    @objc private func uninstallApp() {
        Uninstaller.confirmAndUninstall()
    }

    @objc private func quitApp() {
        cleanup()
        // Remove KeepAlive so launchd doesn't restart us
        let label = "com.xpip.daemon"
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        proc.arguments = ["bootout", "gui/\(getuid())/\(label)"]
        try? proc.run()
        proc.waitUntilExit()
        exit(0)
    }
}
