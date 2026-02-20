import Cocoa

// MARK: - Perk Selection Overlay & HUD (Liquid Glass)

class BouncePerkUI {
    private weak var game: BounceGame?
    private var selectionWindow: NSWindow?
    private var cardGlassViews: [NSView] = []  // NSGlassEffectView instances
    private var offering: [Perk] = []
    private var hoveredIndex = -1
    private var wasMouseDown = false
    private var selectionCooldown: CGFloat = 0

    // HUD
    private var hudWindow: NSWindow?
    private var hudLabel: NSTextField?

    // Card layout constants
    private let cardW: CGFloat = 120
    private let cardH: CGFloat = 150
    private let gap: CGFloat = 14
    private let panelW: CGFloat = 430
    private let panelH: CGFloat = 220

    init(game: BounceGame) {
        self.game = game
    }

    // MARK: - Liquid Glass helpers

    /// Create an NSGlassEffectView wrapping contentView. Falls back to NSVisualEffectView.
    private static func makeGlass(contentView: NSView, cornerRadius: CGFloat = 16, tintColor: NSColor? = nil) -> NSView {
        if let glassClass = NSClassFromString("NSGlassEffectView") as? NSView.Type {
            let glass = glassClass.init(frame: contentView.frame)
            glass.setValue(contentView, forKey: "contentView")
            glass.setValue(cornerRadius, forKey: "cornerRadius")
            if let tint = tintColor {
                glass.setValue(tint, forKey: "tintColor")
            }
            return glass
        }
        // Fallback: frosted NSVisualEffectView
        let vfx = NSVisualEffectView(frame: contentView.frame)
        vfx.material = .popover
        vfx.blendingMode = .behindWindow
        vfx.state = .active
        vfx.wantsLayer = true
        vfx.layer?.cornerRadius = cornerRadius
        vfx.addSubview(contentView)
        return vfx
    }

    /// Create an NSGlassEffectContainerView wrapping contentView. Falls back to plain NSView.
    private static func makeGlassContainer(contentView: NSView, spacing: CGFloat = 8) -> NSView {
        if let containerClass = NSClassFromString("NSGlassEffectContainerView") as? NSView.Type {
            let container = containerClass.init(frame: contentView.frame)
            container.setValue(contentView, forKey: "contentView")
            container.setValue(spacing, forKey: "spacing")
            return container
        }
        // Fallback: just return the content directly
        return contentView
    }

    // MARK: - Selection Overlay

    func showSelection(perks: [Perk], screen: CGRect, screenH: CGFloat) {
        offering = perks
        hoveredIndex = -1

        let panelX = screen.midX - panelW / 2
        let panelY = screenH - screen.midY - panelH / 2

        let win = NSWindow(contentRect: NSRect(x: panelX, y: panelY, width: panelW, height: panelH),
                           styleMask: .borderless, backing: .buffered, defer: false)
        win.isOpaque = false
        win.backgroundColor = .clear
        win.level = .floating
        win.ignoresMouseEvents = false
        win.hasShadow = true
        win.collectionBehavior = [.canJoinAllSpaces, .stationary, .transient, .ignoresCycle]

        // Inner content view that will be wrapped in glass
        let content = NSView(frame: NSRect(x: 0, y: 0, width: panelW, height: panelH))

        // Header
        let level = game?.perkState.paddleLevel ?? 0
        let header = NSTextField(frame: NSRect(x: 0, y: panelH - 40, width: panelW, height: 30))
        header.isEditable = false
        header.isBordered = false
        header.backgroundColor = .clear
        header.textColor = NSColor(white: 1.0, alpha: 0.9)
        header.font = NSFont.monospacedSystemFont(ofSize: 15, weight: .bold)
        header.alignment = .center
        header.stringValue = "LVL \(level + 1) — CHOOSE A PERK"
        content.addSubview(header)

        // Build card glass views inside a stack → glass container
        let totalW = CGFloat(perks.count) * cardW + CGFloat(perks.count - 1) * gap
        let startX = (panelW - totalW) / 2
        let cardY: CGFloat = 14

        cardGlassViews.removeAll()

        // Stack to hold cards
        let cardStack = NSView(frame: NSRect(x: startX, y: cardY,
                                              width: totalW,
                                              height: cardH))

        for (i, perk) in perks.enumerated() {
            let x = CGFloat(i) * (cardW + gap)

            // Card content
            let cardContent = NSView(frame: NSRect(x: 0, y: 0, width: cardW, height: cardH))
            cardContent.wantsLayer = true

            // Icon (48×48)
            let iconLayer = CALayer()
            iconLayer.contents = perk.icon
            iconLayer.magnificationFilter = .nearest
            iconLayer.minificationFilter = .nearest
            iconLayer.frame = CGRect(x: (cardW - 48) / 2, y: cardH - 62, width: 48, height: 48)
            cardContent.layer?.addSublayer(iconLayer)

            // Name
            let nameLabel = NSTextField(frame: NSRect(x: 4, y: 46, width: cardW - 8, height: 20))
            nameLabel.isEditable = false
            nameLabel.isBordered = false
            nameLabel.backgroundColor = .clear
            nameLabel.textColor = perk.color
            nameLabel.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .bold)
            nameLabel.alignment = .center
            nameLabel.stringValue = perk.name
            cardContent.addSubview(nameLabel)

            // Description
            let descLabel = NSTextField(frame: NSRect(x: 4, y: 24, width: cardW - 8, height: 20))
            descLabel.isEditable = false
            descLabel.isBordered = false
            descLabel.backgroundColor = .clear
            descLabel.textColor = NSColor(white: 0.95, alpha: 0.7)
            descLabel.font = NSFont.systemFont(ofSize: 9, weight: .medium)
            descLabel.alignment = .center
            descLabel.stringValue = perk.desc
            cardContent.addSubview(descLabel)

            // Duration badge
            let badge = NSTextField(frame: NSRect(x: 4, y: 4, width: cardW - 8, height: 16))
            badge.isEditable = false
            badge.isBordered = false
            badge.backgroundColor = .clear
            badge.font = NSFont.monospacedSystemFont(ofSize: 9, weight: .medium)
            badge.alignment = .center
            if perk.isTemporary {
                badge.textColor = NSColor(white: 1.0, alpha: 0.45)
                badge.stringValue = "\(Int(perk.duration))s"
            } else {
                badge.textColor = NSColor(white: 1.0, alpha: 0.35)
                badge.stringValue = "PERMANENT"
            }
            cardContent.addSubview(badge)

            // Wrap card in individual glass
            let cardGlass = BouncePerkUI.makeGlass(contentView: cardContent,
                                                    cornerRadius: 10,
                                                    tintColor: perk.color.withAlphaComponent(0.08))
            cardGlass.frame = NSRect(x: x, y: 0, width: cardW, height: cardH)
            cardStack.addSubview(cardGlass)
            cardGlassViews.append(cardGlass)
        }

        // Wrap card stack in glass container (groups glass elements)
        let container = BouncePerkUI.makeGlassContainer(contentView: cardStack, spacing: gap)
        container.frame = NSRect(x: startX, y: cardY, width: totalW, height: cardH)
        content.addSubview(container)

        // Wrap entire panel in glass
        let panelGlass = BouncePerkUI.makeGlass(contentView: content, cornerRadius: 20)
        panelGlass.frame = NSRect(x: 0, y: 0, width: panelW, height: panelH)
        win.contentView = panelGlass

        win.orderFrontRegardless()
        selectionWindow = win
        wasMouseDown = true
        selectionCooldown = 0.3
    }

    func tickSelection() {
        guard let win = selectionWindow, offering.count > 0 else { return }
        guard let mousePos = game?.mousePosition() else { return }

        if selectionCooldown > 0 {
            selectionCooldown -= 0.002
            wasMouseDown = game?.isMouseDown ?? false
            return
        }

        // Convert mouse to window coords
        let winFrame = win.frame
        let localX = mousePos.x - winFrame.minX
        let screenH = game?.screenH ?? 0
        let localY = (screenH - mousePos.y) - winFrame.minY

        let totalW = CGFloat(offering.count) * cardW + CGFloat(offering.count - 1) * gap
        let startX = (panelW - totalW) / 2
        let cardY: CGFloat = 14

        var newHover = -1
        for i in 0..<offering.count {
            let x = startX + CGFloat(i) * (cardW + gap)
            let rect = CGRect(x: x, y: cardY, width: cardW, height: cardH)
            if rect.contains(CGPoint(x: localX, y: localY)) {
                newHover = i
                break
            }
        }

        // Update hover via tintColor on glass views
        if newHover != hoveredIndex {
            hoveredIndex = newHover
            for (i, glassView) in cardGlassViews.enumerated() {
                let isHovered = i == hoveredIndex
                if glassView.responds(to: Selector(("setTintColor:"))) {
                    // NSGlassEffectView path
                    let tint = isHovered
                        ? offering[i].color.withAlphaComponent(0.25)
                        : offering[i].color.withAlphaComponent(0.08)
                    glassView.setValue(tint, forKey: "tintColor")
                } else {
                    // Fallback: layer border
                    withTransaction {
                        if isHovered {
                            glassView.layer?.borderColor = offering[i].color.withAlphaComponent(0.6).cgColor
                            glassView.layer?.borderWidth = 1.5
                        } else {
                            glassView.layer?.borderColor = NSColor(white: 1.0, alpha: 0.12).cgColor
                            glassView.layer?.borderWidth = 0.5
                        }
                    }
                }
            }
        }

        // Click: require fresh mouse-down edge
        let mouseDown = game?.isMouseDown ?? false
        if mouseDown && !wasMouseDown && hoveredIndex >= 0 && hoveredIndex < offering.count {
            let picked = offering[hoveredIndex]
            game?.perkState.pickPerk(picked)
            dismissSelection()
            game?.isPerkSelecting = false
            game?.wasMouseDown = true
        }
        wasMouseDown = mouseDown
    }

    func dismissSelection() {
        selectionWindow?.orderOut(nil)
        selectionWindow = nil
        cardGlassViews.removeAll()
        offering.removeAll()
        hoveredIndex = -1
    }

    // MARK: - HUD (glass pill)

    func createHUD(screen: CGRect, screenH: CGFloat) {
        let hudW: CGFloat = 400
        let hudH: CGFloat = 26
        let hudX = screen.midX - hudW / 2
        let hudY = screenH - screen.minY - 90

        let win = NSWindow(contentRect: NSRect(x: hudX, y: hudY, width: hudW, height: hudH),
                           styleMask: .borderless, backing: .buffered, defer: false)
        win.isOpaque = false
        win.backgroundColor = .clear
        win.level = .floating
        win.ignoresMouseEvents = true
        win.hasShadow = false
        win.collectionBehavior = [.canJoinAllSpaces, .stationary, .transient, .ignoresCycle]

        let label = NSTextField(frame: NSRect(x: 8, y: 0, width: hudW - 16, height: hudH))
        label.isEditable = false
        label.isBordered = false
        label.backgroundColor = .clear
        label.textColor = NSColor(white: 1.0, alpha: 0.85)
        label.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .medium)
        label.alignment = .center
        label.stringValue = ""

        let labelContainer = NSView(frame: NSRect(x: 0, y: 0, width: hudW, height: hudH))
        labelContainer.addSubview(label)

        let hudGlass = BouncePerkUI.makeGlass(contentView: labelContainer, cornerRadius: hudH / 2)
        hudGlass.frame = NSRect(x: 0, y: 0, width: hudW, height: hudH)
        win.contentView = hudGlass
        win.orderFrontRegardless()

        hudWindow = win
        hudLabel = label
    }

    func updateHUD(perkState: PerkState) {
        guard let label = hudLabel else { return }

        var parts: [String] = []

        for (perk, remaining) in perkState.activeTemporary {
            parts.append("\(perk.name) \(String(format: "%.1f", remaining))s")
        }

        for (perk, count) in perkState.permanentStacks where count > 0 {
            parts.append("\(perk.name) ×\(count)")
        }

        label.stringValue = parts.joined(separator: "  ·  ")

        if parts.isEmpty {
            hudWindow?.orderOut(nil)
        } else if let win = hudWindow, !win.isVisible {
            win.orderFrontRegardless()
        }
    }

    func cleanup() {
        dismissSelection()
        hudWindow?.orderOut(nil)
        hudWindow = nil
        hudLabel = nil
    }
}
