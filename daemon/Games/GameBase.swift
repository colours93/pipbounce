import Cocoa
import ApplicationServices

/// Shared base class for all PiP mini-games. Handles:
/// - Mach time conversion
/// - Game timer setup/teardown
/// - Score overlay creation
/// - PiP position restore on stop
/// - PiP size re-reading
/// - Border sync boilerplate
///
/// Subclasses implement `onStart()`, `onStop()`, `gameTick()`.
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

    // Game over
    var gameOver = false
    var gameEndMach: UInt64 = 0
    let gameOverDelay: CGFloat = 2.5

    // Timer
    private var gameTimer: DispatchSourceTimer?
    var timerIntervalMs: Int = 2  // subclass can override before super.start()

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
        gameOver = false

        onStart(screen: screen, pip: pip)

        active = true

        let t = DispatchSource.makeTimerSource(flags: .strict, queue: .main)
        t.schedule(deadline: .now(), repeating: .milliseconds(timerIntervalMs), leeway: .microseconds(100))
        t.setEventHandler { [weak self] in
            guard let self, self.active else { return }
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

        borderRef = nil

        let sw = scoreOverlay
        let cleanup = { sw?.orderOut(nil) }
        if Thread.isMainThread { cleanup() }
        else { DispatchQueue.main.async { cleanup() } }
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

    // MARK: - Shared Utilities

    /// Re-read PiP size from AX (call each tick for resize-aware games)
    func refreshPipSize() {
        guard let axWindow = cachedAXWindow else { return }
        var sizeRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(axWindow, kAXSizeAttribute as CFString, &sizeRef) == .success {
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
        gameOver = true
        gameEndMach = mach_absolute_time()
        scoreLabel?.stringValue = message
    }

    /// Create the standard score overlay window (centered top of screen).
    func createScoreOverlay(screen: CGRect, width: CGFloat = 160) {
        let sw = NSWindow(contentRect: NSRect(x: screen.midX - width / 2, y: screenH - 55,
                                               width: width, height: 44),
                          styleMask: .borderless, backing: .buffered, defer: false)
        sw.isOpaque = false
        sw.backgroundColor = .clear
        sw.level = .floating
        sw.ignoresMouseEvents = true
        sw.hasShadow = false
        sw.collectionBehavior = [.canJoinAllSpaces, .stationary, .transient, .ignoresCycle]

        let vibrancy = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: width, height: 44))
        vibrancy.material = .hudWindow
        vibrancy.blendingMode = .behindWindow
        vibrancy.state = .active
        vibrancy.wantsLayer = true
        vibrancy.layer?.cornerRadius = 8
        sw.contentView = vibrancy

        let label = NSTextField(frame: NSRect(x: 0, y: 0, width: width, height: 44))
        label.isEditable = false
        label.isBordered = false
        label.backgroundColor = .clear
        label.textColor = .white
        label.font = NSFont.monospacedSystemFont(ofSize: 24, weight: .bold)
        label.alignment = .center
        label.stringValue = "0"
        vibrancy.addSubview(label)
        sw.orderFrontRegardless()
        scoreOverlay = sw
        scoreLabel = label
    }

    /// Create a fullscreen overlay window for game graphics. Returns (window, rootLayer).
    func createFullscreenOverlay(screen: CGRect) -> (NSWindow, CALayer) {
        let ow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: screen.width, height: screenH),
                          styleMask: .borderless, backing: .buffered, defer: false)
        ow.isOpaque = false
        ow.backgroundColor = .clear
        ow.level = .floating
        ow.ignoresMouseEvents = true
        ow.hasShadow = false
        ow.collectionBehavior = [.canJoinAllSpaces, .stationary, .transient, .ignoresCycle]
        ow.contentView!.wantsLayer = true
        let rootLayer = ow.contentView!.layer!
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
}
