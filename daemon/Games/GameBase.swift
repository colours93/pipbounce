import Cocoa
import ApplicationServices

/// Wrap a block in CATransaction with animations disabled.
/// Free function — no instance dependency, usable anywhere.
func withTransaction(_ body: () -> Void) {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    body()
    CATransaction.commit()
}

/// Shared base class for all PiP mini-games. Handles:
/// - Mach time conversion
/// - Game timer setup/teardown
/// - Score overlay creation
/// - PiP position restore on stop
/// - PiP size re-reading
/// - Border sync boilerplate
///
/// Subclasses implement `onStart()`, `onStop()`, `gameTick()`.
enum GameState { case ready, playing, gameOver }

class GameBase: MiniGame {
    var active = false
    var lastBounds = CGRect.zero

    // Shared refs
    var cachedAXWindow: AXUIElement?
    var cachedPipSize = CGSize.zero
    var borderRef: RGBBorder?
    var screenH: CGFloat = 0
    var lastMach: UInt64 = 0

    // Score overlay
    var scoreOverlay: NSWindow?
    var scoreLabel: NSTextField?
    var score = 0
    let layerPool = LayerPool()

    // Game over
    var state: GameState = .ready
    var gameOver: Bool { state == .gameOver }
    var gameEndMach: UInt64 = 0
    let gameOverDelay: CGFloat = 2.5

    // Timer
    private var gameTimer: DispatchSourceTimer?
    var timerIntervalMs: Int = 8  // subclass can override before super.start()

    // MARK: - Mach Time

    private static var timebaseInfo: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    func machToSeconds(_ ticks: UInt64) -> CGFloat {
        let info = Self.timebaseInfo
        return CGFloat(Double(ticks) * Double(info.numer) / Double(info.denom) / 1_000_000_000)
    }

    func secondsToMach(_ sec: Double) -> UInt64 {
        let info = Self.timebaseInfo
        return UInt64(sec * 1_000_000_000) * UInt64(info.denom) / UInt64(info.numer)
    }

    /// Current delta time clamped to 0.05s. Call at top of gameTick().
    func deltaTime() -> CGFloat {
        let now = mach_absolute_time()
        let dt = min(machToSeconds(now - lastMach), 0.05)
        lastMach = now
        return dt
    }

    // MARK: - MiniGame Protocol

    func start(screen: CGRect, pip: PipWindowInfo, border: RGBBorder) {
        cachedAXWindow = pip.axWindow
        cachedPipSize = pip.bounds.size
        borderRef = border
        screenH = (NSScreen.main ?? NSScreen.screens[0]).frame.height
        lastMach = mach_absolute_time()
        score = 0
        state = .playing

        onStart(screen: screen, pip: pip)

        active = true

        let t = DispatchSource.makeTimerSource(flags: .strict, queue: .main)
        t.schedule(deadline: .now(), repeating: .milliseconds(timerIntervalMs), leeway: .microseconds(100))
        t.setEventHandler { [weak self] in
            guard let self, self.active, self.cachedAXWindow != nil else { return }
            self.gameTick()
        }
        gameTimer = t
        t.resume()
    }

    func stop() {
        gameTimer?.cancel()
        gameTimer = nil
        active = false

        // Restore PiP to bottom-right
        if let axWindow = cachedAXWindow {
            let screen = getScreenFrame()
            var restorePos = CGPoint(x: screen.maxX - cachedPipSize.width - 20,
                                     y: screen.maxY - cachedPipSize.height - 20)
            if let val = AXValueCreate(.cgPoint, &restorePos) {
                AXUIElementSetAttributeValue(axWindow, kAXPositionAttribute as CFString, val)
            }
        }
        cachedAXWindow = nil

        borderRef?.rotationPadding = 0
        borderRef?.tilt(0)
        borderRef?.hide()

        onStop()
        layerPool.drain()

        borderRef = nil

        let sw = scoreOverlay
        onMain { sw?.orderOut(nil) }
        scoreOverlay = nil
        scoreLabel = nil
    }

    // MARK: - Subclass hooks

    /// Called during start() after base setup, before timer begins.
    /// Create overlays, set initial positions, reset game state here.
    func onStart(screen: CGRect, pip: PipWindowInfo) {
        fatalError("Subclass must override onStart()")
    }

    /// Called during stop() after timer cancelled. Clean up custom overlays here.
    func onStop() {
        // Optional override
    }

    /// Called every timer tick. Implement game logic here.
    func gameTick() {
        fatalError("Subclass must override gameTick()")
    }

    // MARK: - Safety

    /// Check if the PiP window still exists. Auto-stops the game if not.
    /// Call at the top of gameTick() for resilience against PiP disappearing mid-game.
    @discardableResult
    func verifyPipAlive() -> Bool {
        guard let ax = cachedAXWindow else { stop(); return false }
        var ref: CFTypeRef?
        if AXUIElementCopyAttributeValue(ax, kAXPositionAttribute as CFString, &ref) != .success {
            print("[GameBase] PiP window lost — stopping game")
            stop()
            return false
        }
        return true
    }

    // MARK: - Shared Utilities

    /// Re-read PiP size from AX (call each tick for resize-aware games).
    /// Throttled to at most once per 500ms since PiP doesn't resize during gameplay.
    private var lastPipSizeRefresh: UInt64 = 0
    func refreshPipSize() {
        let now = mach_absolute_time()
        if lastPipSizeRefresh != 0 && machToSeconds(now - lastPipSizeRefresh) < 0.5 { return }
        lastPipSizeRefresh = now
        guard let axWindow = cachedAXWindow else { return }
        var sizeRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(axWindow, kAXSizeAttribute as CFString, &sizeRef) == .success,
           sizeRef != nil {
            var freshSize = CGSize.zero
            AXValueGetValue(sizeRef as! AXValue, .cgSize, &freshSize)
            if freshSize.width > 0 && freshSize.height > 0 {
                cachedPipSize = freshSize
            }
        }
    }

    /// Move PiP via Accessibility. Returns false if AX call failed (game should stop).
    @discardableResult
    func movePip(to point: CGPoint) -> Bool {
        guard let axWindow = cachedAXWindow else { return false }
        var pos = point
        guard let val = AXValueCreate(.cgPoint, &pos) else { return false }
        let err = AXUIElementSetAttributeValue(axWindow, kAXPositionAttribute as CFString, val)
        if err != .success {
            stop()
            return false
        }
        return true
    }

    /// Update border to track PiP bounds. Respects glow setting.
    func syncBorder(around bounds: CGRect) {
        lastBounds = bounds
        if settings.glow, let border = borderRef {
            border.show(around: bounds)
        } else {
            borderRef?.hide()
        }
    }

    /// Check game over timeout and auto-stop. Returns true if still in game-over state.
    func checkGameOverTimeout() -> Bool {
        guard gameOver else { return false }
        let now = mach_absolute_time()
        if machToSeconds(now - gameEndMach) > gameOverDelay { stop() }
        return true
    }

    /// Trigger game over state.
    func triggerGameOver(message: String) {
        state = .gameOver
        gameEndMach = mach_absolute_time()
        scoreLabel?.attributedStringValue = Self.styledMessage(message)
    }

    // Shared mint color for score displays
    static let scoreMint = NSColor(red: 0.55, green: 1.0, blue: 0.78, alpha: 1.0)

    /// Create the standard score overlay window — liquid glass pill (centered top of screen).
    func createScoreOverlay(screen: CGRect, width: CGFloat = 160) {
        let pillH: CGFloat = 36
        let sw = NSWindow(contentRect: NSRect(x: screen.midX - width / 2, y: screenH - 56,
                                               width: width, height: pillH),
                          styleMask: .borderless, backing: .buffered, defer: false)
        sw.isOpaque = false
        sw.backgroundColor = .clear
        sw.level = .floating
        sw.ignoresMouseEvents = true
        sw.hasShadow = true
        sw.collectionBehavior = [.canJoinAllSpaces, .stationary, .transient, .ignoresCycle]

        let vibrancy = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: width, height: pillH))
        vibrancy.material = .hudWindow
        vibrancy.blendingMode = .behindWindow
        vibrancy.state = .active
        vibrancy.wantsLayer = true
        vibrancy.layer?.cornerRadius = pillH / 2
        vibrancy.layer?.borderWidth = 0.5
        vibrancy.layer?.borderColor = NSColor(white: 1.0, alpha: 0.18).cgColor
        vibrancy.layer?.masksToBounds = true
        sw.contentView = vibrancy

        let label = NSTextField(frame: NSRect(x: 12, y: 0, width: width - 24, height: pillH))
        label.isEditable = false
        label.isBordered = false
        label.backgroundColor = .clear
        label.alignment = .center
        label.usesSingleLineMode = true
        label.cell?.isScrollable = false
        label.cell?.wraps = false
        // Vertically center text by using the cell's drawing rect
        (label.cell as? NSTextFieldCell)?.drawsBackground = false
        label.attributedStringValue = Self.styledScore("0")
        vibrancy.addSubview(label)
        sw.orderFrontRegardless()
        scoreOverlay = sw
        scoreLabel = label
    }

    /// Styled single-value score string (mint, glow, heavy mono).
    static func styledScore(_ value: String, size: CGFloat = 20) -> NSAttributedString {
        let shadow = NSShadow()
        shadow.shadowColor = scoreMint.withAlphaComponent(0.7)
        shadow.shadowBlurRadius = 12
        shadow.shadowOffset = .zero
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        return NSAttributedString(string: value, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: size, weight: .heavy),
            .foregroundColor: scoreMint,
            .kern: 2.0,
            .shadow: shadow,
            .paragraphStyle: style,
        ])
    }

    /// Styled "left : right" score string for versus modes.
    static func styledVersusScore(_ left: String, _ right: String, size: CGFloat = 20) -> NSAttributedString {
        let mint = scoreMint
        let dimMint = mint.withAlphaComponent(0.5)
        let font = NSFont.monospacedSystemFont(ofSize: size, weight: .heavy)
        let colonFont = NSFont.monospacedSystemFont(ofSize: size - 4, weight: .medium)
        let shadow = NSShadow()
        shadow.shadowColor = mint.withAlphaComponent(0.7)
        shadow.shadowBlurRadius = 12
        shadow.shadowOffset = .zero
        let style = NSMutableParagraphStyle()
        style.alignment = .center

        let result = NSMutableAttributedString()
        result.append(NSAttributedString(string: left, attributes: [
            .font: font, .foregroundColor: mint,
            .shadow: shadow, .paragraphStyle: style,
        ]))
        result.append(NSAttributedString(string: " : ", attributes: [
            .font: colonFont, .foregroundColor: dimMint,
            .shadow: shadow, .paragraphStyle: style,
        ]))
        result.append(NSAttributedString(string: right, attributes: [
            .font: font, .foregroundColor: mint,
            .shadow: shadow, .paragraphStyle: style,
        ]))
        return result
    }

    /// Styled message string (e.g. "YOU WIN", "GAME OVER").
    static func styledMessage(_ text: String, size: CGFloat = 18) -> NSAttributedString {
        let mint = scoreMint
        let shadow = NSShadow()
        shadow.shadowColor = mint.withAlphaComponent(0.7)
        shadow.shadowBlurRadius = 12
        shadow.shadowOffset = .zero
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        return NSAttributedString(string: text, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: size, weight: .heavy),
            .foregroundColor: mint, .kern: 8.0,
            .shadow: shadow, .paragraphStyle: style,
        ])
    }

    /// Pulse the score overlay (call on score change).
    func pulseScoreOverlay() {
        if let layer = scoreOverlay?.contentView?.layer {
            let pulse = CABasicAnimation(keyPath: "transform.scale")
            pulse.fromValue = 1.08
            pulse.toValue = 1.0
            pulse.duration = 0.2
            pulse.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer.add(pulse, forKey: "scorePulse")
        }
    }

    /// Create a fullscreen overlay window for game graphics. Returns (window, rootLayer).
    func createFullscreenOverlay(screen: CGRect) -> (NSWindow, CALayer) {
        let ow = createFloatingWindow(frame: NSRect(x: 0, y: 0, width: screen.width, height: screenH))
        guard let rootLayer = ow.contentView?.layer else {
            fatalError("[GameBase] Overlay window missing layer after wantsLayer=true")
        }
        ow.orderFrontRegardless()
        return (ow, rootLayer)
    }

    /// Get current mouse position. Returns nil if CGEvent fails.
    func mousePosition() -> CGPoint? {
        guard let event = CGEvent(source: nil) else { return nil }
        return event.location
    }

    /// Whether left mouse button is currently pressed.
    var isMouseDown: Bool {
        NSEvent.pressedMouseButtons & 1 != 0
    }

    // MARK: - Pixel Art Renderer

    /// Render a pixel art sprite from a 2D array of hex colors to a CGImage.
    /// Pass 0 for transparent pixels. Uses nearest-neighbor scaling for crisp pixels.
    /// Usage: `let img = GameBase.renderPixelArt(pixels, scale: 3)`
    /// Then: `layer.contents = img; layer.magnificationFilter = .nearest`
    static func renderPixelArt(_ pixels: [[UInt32]], scale: Int = 1) -> CGImage? {
        let h = pixels.count
        guard h > 0 else { return nil }
        let w = pixels[0].count
        guard w > 0 else { return nil }
        let sw = w * scale
        let sh = h * scale
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: sw, pixelsHigh: sh,
                                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                    isPlanar: false, colorSpaceName: .deviceRGB,
                                    bytesPerRow: sw * 4, bitsPerPixel: 32)!
        let data = rep.bitmapData!
        for py in 0..<h {
            for px in 0..<w {
                let hex = pixels[py][px]
                if hex == 0 { continue } // transparent
                let r = UInt8((hex >> 16) & 0xFF)
                let g = UInt8((hex >> 8) & 0xFF)
                let b = UInt8(hex & 0xFF)
                let a: UInt8 = hex > 0xFFFFFF ? UInt8((hex >> 24) & 0xFF) : 255
                for sy in 0..<scale {
                    for sx in 0..<scale {
                        let i = ((py * scale + sy) * sw + (px * scale + sx)) * 4
                        data[i]   = r
                        data[i+1] = g
                        data[i+2] = b
                        data[i+3] = a
                    }
                }
            }
        }
        return rep.cgImage
    }

    /// Create a CALayer with pixel art contents. Sets nearest-neighbor filtering.
    static func pixelArtLayer(_ pixels: [[UInt32]], scale: Int = 1, size: CGSize? = nil) -> CALayer {
        let layer = CALayer()
        layer.contents = renderPixelArt(pixels, scale: scale)
        layer.magnificationFilter = .nearest
        layer.minificationFilter = .nearest
        if let s = size {
            layer.bounds = CGRect(origin: .zero, size: s)
        } else {
            let h = pixels.count
            let w = h > 0 ? pixels[0].count : 0
            layer.bounds = CGRect(x: 0, y: 0, width: w * scale, height: h * scale)
        }
        return layer
    }

    // MARK: - Convenience Helpers

    /// Run a block on the main thread. Uses async dispatch when off-main
    /// to avoid deadlocks. If you need synchronous return, use `onMainSync`.
    func onMain(_ body: @escaping () -> Void) {
        if Thread.isMainThread { body() }
        else { DispatchQueue.main.async { body() } }
    }

    /// Run a block on the main thread and wait for the result.
    /// Warning: Will deadlock if called from a queue the main thread is waiting on.
    func onMainSync<T>(_ body: () -> T) -> T {
        if Thread.isMainThread { return body() }
        return DispatchQueue.main.sync { body() }
    }

    /// Convert AX Y coordinate (top-down) to NS/Quartz Y (bottom-up).
    func axToNS(y: CGFloat, height: CGFloat) -> CGFloat {
        screenH - y - height
    }

    /// Create a floating borderless window (for game overlays, death screens, etc.).
    func createFloatingWindow(frame: NSRect) -> NSWindow {
        let w = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.level = .floating
        w.ignoresMouseEvents = true
        w.hasShadow = false
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .transient, .ignoresCycle]
        guard let cv = w.contentView else {
            fatalError("[GameBase] NSWindow created without contentView")
        }
        cv.wantsLayer = true
        return w
    }

    /// Current input state for clean polling.
    struct GameInput {
        let mouse: CGPoint?
        let mouseDown: Bool
        let rightMouseDown: Bool
    }

    func currentInput() -> GameInput {
        GameInput(
            mouse: mousePosition(),
            mouseDown: NSEvent.pressedMouseButtons & 1 != 0,
            rightMouseDown: NSEvent.pressedMouseButtons & 2 != 0
        )
    }

    /// Clamp a velocity vector to a maximum speed.
    static func clampSpeed(_ vel: inout CGPoint, max maxSpeed: CGFloat) {
        let speed = sqrt(vel.x * vel.x + vel.y * vel.y)
        guard speed > maxSpeed else { return }
        let scale = maxSpeed / speed
        vel.x *= scale
        vel.y *= scale
    }

    // MARK: - Collision Helpers

    static func rectsCollide(_ a: CGRect, _ b: CGRect) -> Bool {
        return a.intersects(b)
    }

    static func circleHitsRect(center: CGPoint, radius: CGFloat, rect: CGRect) -> Bool {
        let cx = max(rect.minX, min(center.x, rect.maxX))
        let cy = max(rect.minY, min(center.y, rect.maxY))
        let dx = center.x - cx, dy = center.y - cy
        return dx * dx + dy * dy <= radius * radius
    }

    static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = a.x - b.x, dy = a.y - b.y
        return sqrt(dx * dx + dy * dy)
    }

    static func pointInRect(_ point: CGPoint, _ rect: CGRect) -> Bool {
        return rect.contains(point)
    }
}
