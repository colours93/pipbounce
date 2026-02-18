import Cocoa
import ApplicationServices

let flappy = FlappyGame()

class FlappyGame: GameBase {

    // Physics
    private var velocity: CGFloat = 0
    private let gravity: CGFloat = 900
    private let flapImpulse: CGFloat = -360
    private let maxFallSpeed: CGFloat = 700

    // Bird position (AX coords)
    private var birdX: CGFloat = 0
    private var birdY: CGFloat = 0

    // Pipes
    private struct PipePair {
        let topWindow: NSWindow
        let bottomWindow: NSWindow
        var x: CGFloat
        let gapCenterY: CGFloat
        var scored: Bool
    }
    private var pipes: [PipePair] = []
    private let pipeBodyWidth: CGFloat = 56
    private let pipeCapWidth: CGFloat = 70
    private let pipeCapHeight: CGFloat = 28
    private var pipeGap: CGFloat = 200
    private var pipeInterval: CGFloat = 260
    private let baseScrollSpeed: CGFloat = 200
    private let maxScrollSpeed: CGFloat = 350

    // Pixel-art sprites
    private enum Sprites {
        // Palette
        private static let H: UInt32 = 0x8ED43C  // highlight green
        private static let L: UInt32 = 0x5FA316  // light green
        private static let M: UInt32 = 0x4E8C12  // medium green
        private static let D: UInt32 = 0x33660A  // dark green (shadow/edge)
        private static let B: UInt32 = 0x264D08  // border dark
        private static let O: UInt32 = 0          // transparent

        // Pipe cap 22x8: wider cap with lip, highlight top, shadow bottom, dark edges
        static let pipeCap: [[UInt32]] = [
            [B,B,B,B,B,B,B,B,B,B,B,B,B,B,B,B,B,B,B,B,B,B],
            [B,D,H,H,H,L,L,L,L,L,L,L,L,L,L,L,L,L,H,H,D,B],
            [B,D,H,H,L,L,L,L,L,L,L,L,L,L,L,L,L,L,L,H,D,B],
            [B,D,L,M,M,M,M,M,M,M,M,M,M,M,M,M,M,M,M,L,D,B],
            [B,D,L,M,M,M,M,M,M,M,M,M,M,M,M,M,M,M,M,L,D,B],
            [B,D,M,M,M,M,M,M,M,M,M,M,M,M,M,M,M,M,M,M,D,B],
            [B,D,D,D,M,M,M,M,M,M,M,M,M,M,M,M,M,M,D,D,D,B],
            [B,B,B,B,B,B,B,B,B,B,B,B,B,B,B,B,B,B,B,B,B,B],
        ]

        // Pipe body 18x8: tiled vertically, left shadow, right highlight, brick lines
        static let pipeBody: [[UInt32]] = [
            [B,D,D,M,M,M,M,M,M,M,M,M,M,M,M,L,H,B],
            [B,D,D,M,M,M,M,M,M,M,M,M,M,M,M,L,H,B],
            [B,D,D,D,D,D,D,D,D,D,D,D,D,D,D,D,D,B],
            [B,D,D,M,M,M,M,M,M,M,M,M,M,M,M,L,H,B],
            [B,D,D,M,M,M,M,M,M,M,M,M,M,M,M,L,H,B],
            [B,D,D,D,D,D,D,D,D,D,D,D,D,D,D,D,D,B],
            [B,D,D,M,M,M,M,M,M,M,M,M,M,M,M,L,H,B],
            [B,D,D,M,M,M,M,M,M,M,M,M,M,M,M,L,H,B],
        ]

        static let pipeCapImage: CGImage? = renderPixelArt(pipeCap, scale: 3)
        static let pipeBodyImage: CGImage? = renderPixelArt(pipeBody, scale: 3)

        private static func renderPixelArt(_ pixels: [[UInt32]], scale: Int) -> CGImage? {
            GameBase.renderPixelArt(pixels, scale: scale)
        }
    }

    // Scoring
    private var bestScore = 0

    // Input
    private var wasMouseDown = false

    // Wobble (border glow only — can't rotate Chrome's window)
    private var tiltAngle: CGFloat = 0

    // Game state
    private var started = false

    override func onStart(screen: CGRect, pip: PipWindowInfo) {
        timerIntervalMs = 4

        velocity = 0
        gameOver = false
        started = false
        tiltAngle = 0
        wasMouseDown = false
        pipes = []

        // Shrink PiP to a small bird size
        var smallSize = CGSize(width: 200, height: 112)
        if let val = AXValueCreate(.cgSize, &smallSize) {
            AXUIElementSetAttributeValue(pip.axWindow, kAXSizeAttribute as CFString, val)
        }
        var sizeRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(pip.axWindow, kAXSizeAttribute as CFString, &sizeRef) == .success,
           sizeRef != nil {
            var actualSize = CGSize.zero
            AXValueGetValue(sizeRef as! AXValue, .cgSize, &actualSize)
            cachedPipSize = actualSize
        } else {
            cachedPipSize = pip.bounds.size
        }

        borderRef?.rotationPadding = max(cachedPipSize.width, cachedPipSize.height) * 0.5
        pipeGap = cachedPipSize.height + 160
        pipeInterval = cachedPipSize.width + 250

        birdX = screen.width * 0.22
        birdY = screen.midY - cachedPipSize.height / 2

        // Move PiP to initial position
        var initPos = CGPoint(x: birdX, y: birdY)
        if let val = AXValueCreate(.cgPoint, &initPos) {
            AXUIElementSetAttributeValue(pip.axWindow, kAXPositionAttribute as CFString, val)
        }

        if Thread.isMainThread {
            createScoreOverlay(screen: screen, width: 120)
        } else {
            DispatchQueue.main.sync { self.createScoreOverlay(screen: screen, width: 120) }
        }

        print("Flappy started")
    }

    override func onStop() {
        started = false

        borderRef?.rotationPadding = 0

        let pipeList = pipes
        let doCleanup = {
            for p in pipeList {
                p.topWindow.orderOut(nil)
                p.bottomWindow.orderOut(nil)
            }
        }
        if Thread.isMainThread { doCleanup() }
        else { DispatchQueue.main.async { doCleanup() } }

        pipes = []
        print("Flappy stopped")
    }

    // MARK: - Game Loop

    override func gameTick() {
        guard active else { return }

        let screen = getScreenFrame()
        let size = cachedPipSize
        let dt = deltaTime()
        let now = mach_absolute_time()

        if gameOver {
            if machToSeconds(now - gameEndMach) > 2.0 { stop() }
            return
        }

        // Input
        let mouseDown = isMouseDown
        if mouseDown && !wasMouseDown { flap() }
        wasMouseDown = mouseDown

        // Physics
        if started {
            velocity += gravity * dt
            velocity = min(velocity, maxFallSpeed)
            birdY += velocity * dt
        } else {
            let bob = sin(Double(now) / 200_000_000.0) * 4
            birdY = screen.midY - size.height / 2 + CGFloat(bob)
        }

        // Wobble tilt (border glow only)
        if started {
            let targetTilt = velocity / 800.0
            let clampedTilt = max(-0.5, min(0.8, targetTilt))
            tiltAngle += (clampedTilt - tiltAngle) * 0.15
        } else {
            tiltAngle = 0
        }

        // Speed ramp: increases with score
        let scrollSpeed = min(baseScrollSpeed + CGFloat(score) * 5, maxScrollSpeed)

        // Scroll pipes
        if started {
            for i in 0..<pipes.count { pipes[i].x -= scrollSpeed * dt }
        }

        // Spawn pipes
        let lastPipeX = pipes.last?.x ?? -1000
        if started && (pipes.isEmpty || lastPipeX < screen.maxX - pipeInterval) {
            spawnPipe(screen: screen)
        }

        // Remove off-screen pipes
        let removeList = pipes.filter { $0.x + pipeCapWidth < -20 }
        pipes.removeAll { pair in pair.x + pipeCapWidth < -20 }
        for p in removeList {
            p.topWindow.orderOut(nil)
            p.bottomWindow.orderOut(nil)
        }

        // Scoring
        for i in 0..<pipes.count {
            if !pipes[i].scored && pipes[i].x + pipeBodyWidth / 2 < birdX {
                pipes[i].scored = true
                score += 1
                scoreLabel?.stringValue = "\(score)"
            }
        }

        // Collision: floor / ceiling
        if started && (birdY < screen.minY || birdY + size.height > screen.maxY) {
            birdY = max(screen.minY, min(screen.maxY - size.height, birdY))
            doGameOver()
            return
        }

        // Collision: pipes
        if started {
            let birdRect = CGRect(x: birdX + 4, y: birdY + 4,
                                  width: size.width - 8, height: size.height - 8)
            for pair in pipes {
                let capExtra = (pipeCapWidth - pipeBodyWidth) / 2
                let topH = pair.gapCenterY - pipeGap / 2
                let bottomY = pair.gapCenterY + pipeGap / 2
                let bottomH = screen.maxY - bottomY

                let topBody = CGRect(x: pair.x, y: 0, width: pipeBodyWidth, height: topH - pipeCapHeight)
                let topCap = CGRect(x: pair.x - capExtra, y: topH - pipeCapHeight,
                                    width: pipeCapWidth, height: pipeCapHeight)
                let bottomCap = CGRect(x: pair.x - capExtra, y: bottomY,
                                       width: pipeCapWidth, height: pipeCapHeight)
                let bottomBody = CGRect(x: pair.x, y: bottomY + pipeCapHeight,
                                        width: pipeBodyWidth, height: bottomH - pipeCapHeight)

                if birdRect.intersects(topBody) || birdRect.intersects(topCap) ||
                   birdRect.intersects(bottomCap) || birdRect.intersects(bottomBody) {
                    doGameOver()
                    return
                }
            }
        }

        let bounds = CGRect(x: birdX, y: birdY, width: size.width, height: size.height)
        lastBounds = bounds

        // Update visuals
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        movePip(to: CGPoint(x: birdX, y: birdY))

        updatePipeWindows(screen: screen)

        if settings.glow, let border = borderRef {
            border.show(around: bounds)
            border.tilt(tiltAngle)
        }

        CATransaction.commit()
    }

    // MARK: - Actions

    private func flap() {
        if !started { started = true }
        velocity = flapImpulse
    }

    private func doGameOver() {
        if score > bestScore { bestScore = score }
        triggerGameOver(message: "Game Over  \(score)")
        print("Flappy game over: score=\(score) best=\(bestScore)")
    }

    // MARK: - Pipe Creation

    private func spawnPipe(screen: CGRect) {
        let minGapY = screen.minY + pipeGap / 2 + 60
        let maxGapY = screen.maxY - pipeGap / 2 - 60
        let gapY = CGFloat.random(in: minGapY...maxGapY)
        let x = screen.maxX + 20

        let topW = makePipeWindow(screen: screen, isTop: true, x: x, gapCenterY: gapY)
        let botW = makePipeWindow(screen: screen, isTop: false, x: x, gapCenterY: gapY)

        pipes.append(PipePair(topWindow: topW, bottomWindow: botW,
                              x: x, gapCenterY: gapY, scored: false))
    }

    private func makePipeWindow(screen: CGRect, isTop: Bool, x: CGFloat, gapCenterY: CGFloat) -> NSWindow {
        let capExtra = (pipeCapWidth - pipeBodyWidth) / 2

        let pipeH: CGFloat
        let nsY: CGFloat
        if isTop {
            pipeH = gapCenterY - pipeGap / 2
            nsY = screenH - pipeH
        } else {
            let gapBottom = gapCenterY + pipeGap / 2
            pipeH = screen.maxY - gapBottom
            nsY = 0
        }

        let w = NSWindow(contentRect: NSRect(x: x - capExtra, y: nsY,
                                              width: pipeCapWidth, height: max(pipeH, 1)),
                         styleMask: .borderless, backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.level = .floating
        w.ignoresMouseEvents = true
        w.hasShadow = false
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .transient, .ignoresCycle]
        w.contentView!.wantsLayer = true

        buildPipeLayers(in: w, height: pipeH, isTop: isTop)
        w.orderFrontRegardless()
        return w
    }

    private func buildPipeLayers(in window: NSWindow, height: CGFloat, isTop: Bool) {
        guard let layer = window.contentView?.layer else { return }
        let capExtra = (pipeCapWidth - pipeBodyWidth) / 2

        let bodyH = max(height - pipeCapHeight, 0)
        let bodyY: CGFloat = isTop ? pipeCapHeight : 0
        let bodyLayer = CALayer()
        bodyLayer.frame = NSRect(x: capExtra, y: bodyY, width: pipeBodyWidth, height: bodyH)
        bodyLayer.contents = Sprites.pipeBodyImage
        bodyLayer.magnificationFilter = .nearest
        bodyLayer.minificationFilter = .nearest
        bodyLayer.contentsGravity = .resize

        let capY: CGFloat = isTop ? 0 : height - pipeCapHeight
        let capLayer = CALayer()
        capLayer.frame = NSRect(x: 0, y: capY, width: pipeCapWidth, height: pipeCapHeight)
        capLayer.contents = Sprites.pipeCapImage
        capLayer.magnificationFilter = .nearest
        capLayer.minificationFilter = .nearest
        capLayer.contentsGravity = .resize

        layer.addSublayer(bodyLayer)
        layer.addSublayer(capLayer)
    }

    private func updatePipeWindows(screen: CGRect) {
        let capExtra = (pipeCapWidth - pipeBodyWidth) / 2

        for pair in pipes {
            let nsX = pair.x - capExtra
            let topH = pair.gapCenterY - pipeGap / 2
            pair.topWindow.setFrameOrigin(NSPoint(x: nsX, y: screenH - topH))
            pair.bottomWindow.setFrameOrigin(NSPoint(x: nsX, y: 0))
        }
    }
}
