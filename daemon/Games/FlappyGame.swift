import Cocoa
import ApplicationServices

class FlappyGame: GameBase {

    private enum Config {
        static let gravity: CGFloat = 900
        static let flapImpulse: CGFloat = -360
        static let maxFallSpeed: CGFloat = 700
        static let pipeBodyWidth: CGFloat = 56
        static let pipeCapWidth: CGFloat = 70
        static let pipeCapHeight: CGFloat = 28
        static let baseScrollSpeed: CGFloat = 200
        static let maxScrollSpeed: CGFloat = 350
        static let bobDivisor: Double = 200_000_000
    }

    private enum Phase { case idle, flying, dead }

    private var phase: Phase = .idle
    private var velocity: CGFloat = 0
    private var birdX: CGFloat = 0
    private var birdY: CGFloat = 0

    private struct PipePair {
        let topBody: CALayer
        let topCap: CALayer
        let bottomBody: CALayer
        let bottomCap: CALayer
        var x: CGFloat
        let gapCenterY: CGFloat
        var scored: Bool
    }
    private var pipes: [PipePair] = []
    private var pipeOverlay: NSWindow?
    private var pipeRootLayer: CALayer?
    private var pipeGap: CGFloat = 200
    private var pipeInterval: CGFloat = 260
    private var bestScore = 0
    private var wasMouseDown = false
    private var tiltAngle: CGFloat = 0
    private var deathOverlay: NSWindow?

    override func onStart(screen: CGRect, pip: PipWindowInfo) {
        timerIntervalMs = 4

        velocity = 0
        state = .playing
        phase = .idle
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

        onMain {
            let (ow, root) = self.createFullscreenOverlay(screen: screen)
            self.pipeOverlay = ow
            self.pipeRootLayer = root
            self.createScoreOverlay(screen: screen, width: 100)
        }

        print("Flappy started")
    }

    override func onStop() {
        phase = .idle
        borderRef?.rotationPadding = 0

        for p in pipes {
            p.topBody.removeFromSuperlayer()
            p.topCap.removeFromSuperlayer()
            p.bottomBody.removeFromSuperlayer()
            p.bottomCap.removeFromSuperlayer()
        }
        pipes = []

        let po = pipeOverlay
        let dw = deathOverlay
        onMain {
            po?.orderOut(nil)
            dw?.orderOut(nil)
        }
        pipeOverlay = nil
        pipeRootLayer = nil
        deathOverlay = nil
        print("Flappy stopped")
    }

    // MARK: - Game Loop

    override func gameTick() {
        guard active else { return }

        let screen = getScreenFrame()
        let size = cachedPipSize
        let dt = deltaTime()
        let now = mach_absolute_time()

        if phase == .dead {
            if machToSeconds(now - gameEndMach) > 3.0 { stop() }
            return
        }

        // Input
        let mouseDown = isMouseDown
        if mouseDown && !wasMouseDown { flap() }
        wasMouseDown = mouseDown

        let flying = phase == .flying

        // Physics
        if flying {
            velocity += Config.gravity * dt
            velocity = min(velocity, Config.maxFallSpeed)
            birdY += velocity * dt
        } else {
            let bob = sin(Double(now) / Config.bobDivisor) * 4
            birdY = screen.midY - size.height / 2 + CGFloat(bob)
        }

        // Wobble tilt
        tiltAngle = flying
            ? tiltAngle + (max(-0.5, min(0.8, velocity / 800.0)) - tiltAngle) * 0.15
            : 0

        // Speed ramp
        let scrollSpeed = min(Config.baseScrollSpeed + CGFloat(score) * 5, Config.maxScrollSpeed)

        if flying {
            for i in 0..<pipes.count { pipes[i].x -= scrollSpeed * dt }
        }

        // Spawn pipes
        let lastPipeX = pipes.last?.x ?? -1000
        if flying && (pipes.isEmpty || lastPipeX < screen.maxX - pipeInterval) {
            spawnPipe(screen: screen)
        }

        // Remove off-screen pipes
        pipes.removeAll { p in
            let offscreen = p.x + Config.pipeCapWidth < -20
            if offscreen {
                p.topBody.removeFromSuperlayer()
                p.topCap.removeFromSuperlayer()
                p.bottomBody.removeFromSuperlayer()
                p.bottomCap.removeFromSuperlayer()
            }
            return offscreen
        }

        // Scoring
        for i in 0..<pipes.count {
            if !pipes[i].scored && pipes[i].x + Config.pipeBodyWidth / 2 < birdX {
                pipes[i].scored = true
                score += 1
                scoreLabel?.attributedStringValue = Self.styledScore("\(score)")
            }
        }

        // Collision: floor / ceiling
        if flying && (birdY < screen.minY || birdY + size.height > screen.maxY) {
            birdY = max(screen.minY, min(screen.maxY - size.height, birdY))
            doGameOver(); return
        }

        // Collision: pipes
        if flying {
            let birdRect = CGRect(x: birdX + 4, y: birdY + 4,
                                  width: size.width - 8, height: size.height - 8)
            let capExtra = (Config.pipeCapWidth - Config.pipeBodyWidth) / 2
            for pair in pipes {
                let topH = pair.gapCenterY - pipeGap / 2
                let bottomY = pair.gapCenterY + pipeGap / 2
                let rects = [
                    CGRect(x: pair.x, y: 0, width: Config.pipeBodyWidth, height: topH - Config.pipeCapHeight),
                    CGRect(x: pair.x - capExtra, y: topH - Config.pipeCapHeight, width: Config.pipeCapWidth, height: Config.pipeCapHeight),
                    CGRect(x: pair.x - capExtra, y: bottomY, width: Config.pipeCapWidth, height: Config.pipeCapHeight),
                    CGRect(x: pair.x, y: bottomY + Config.pipeCapHeight, width: Config.pipeBodyWidth, height: screen.maxY - bottomY - Config.pipeCapHeight),
                ]
                if rects.contains(where: { Self.rectsCollide(birdRect, $0) }) {
                    doGameOver(); return
                }
            }
        }

        let bounds = CGRect(x: birdX, y: birdY, width: size.width, height: size.height)
        lastBounds = bounds

        withTransaction {
            movePip(to: CGPoint(x: birdX, y: birdY))
            updatePipeLayers(screen: screen)
            if settings.glow, let border = borderRef {
                border.show(around: bounds)
                border.tilt(tiltAngle)
            }
        }
    }

    // MARK: - Actions

    private func flap() {
        if phase == .idle { phase = .flying }
        velocity = Config.flapImpulse
    }

    private func doGameOver() {
        phase = .dead
        if score > bestScore { bestScore = score }
        triggerGameOver(message: "Game Over  \(score)")
        showYouDied()
        print("Flappy game over: score=\(score) best=\(bestScore)")
    }

    private func showYouDied() {
        let screen = getScreenFrame()

        let ow = createFloatingWindow(frame: NSRect(x: screen.minX, y: 0, width: screen.width, height: screenH))
        ow.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)

        let root = ow.contentView!.layer!

        // Dark vignette background
        let bg = CALayer()
        bg.frame = CGRect(x: 0, y: 0, width: screen.width, height: screenH)
        bg.backgroundColor = NSColor(red: 0, green: 0, blue: 0, alpha: 0.75).cgColor
        bg.opacity = 0
        root.addSublayer(bg)

        // "YOU DIED" text
        let text = CATextLayer()
        text.string = "YOU DIED"
        text.font = NSFont(name: "Times New Roman", size: 72) ?? NSFont.systemFont(ofSize: 72, weight: .bold)
        text.fontSize = 72
        text.foregroundColor = NSColor(red: 0.7, green: 0.1, blue: 0.1, alpha: 1.0).cgColor
        text.alignmentMode = .center
        text.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
        let textW: CGFloat = 600
        let textH: CGFloat = 100
        text.frame = CGRect(x: (screen.width - textW) / 2, y: (screenH - textH) / 2, width: textW, height: textH)
        text.opacity = 0
        root.addSublayer(text)

        ow.orderFrontRegardless()
        deathOverlay = ow

        // Fade in background
        let bgFade = CABasicAnimation(keyPath: "opacity")
        bgFade.fromValue = 0.0
        bgFade.toValue = 1.0
        bgFade.duration = 1.0
        bgFade.fillMode = .forwards
        bgFade.isRemovedOnCompletion = false
        bg.add(bgFade, forKey: "fadeIn")

        // Fade in text slightly delayed
        let textFade = CABasicAnimation(keyPath: "opacity")
        textFade.fromValue = 0.0
        textFade.toValue = 1.0
        textFade.duration = 1.2
        textFade.beginTime = CACurrentMediaTime() + 0.3
        textFade.fillMode = .forwards
        textFade.isRemovedOnCompletion = false
        text.add(textFade, forKey: "fadeIn")
    }

    // MARK: - Pipe Creation

    private func spawnPipe(screen: CGRect) {
        guard let root = pipeRootLayer else { return }
        let minGapY = screen.minY + pipeGap / 2 + 60
        let maxGapY = screen.maxY - pipeGap / 2 - 60
        let gapY = CGFloat.random(in: minGapY...maxGapY)
        let x = screen.maxX + 20

        let capExtra = (Config.pipeCapWidth - Config.pipeBodyWidth) / 2
        let topH = gapY - pipeGap / 2
        let bottomY = gapY + pipeGap / 2
        let bottomH = screen.maxY - bottomY

        // Top body
        let topBody = CALayer()
        let topBodyH = max(topH - Config.pipeCapHeight, 0)
        topBody.frame = CGRect(x: x, y: screenH - topBodyH, width: Config.pipeBodyWidth, height: topBodyH)
        topBody.contents = FlappySprites.pipeBodyImage
        topBody.magnificationFilter = .nearest
        topBody.minificationFilter = .nearest
        topBody.contentsGravity = .resize
        root.addSublayer(topBody)

        // Top cap
        let topCap = CALayer()
        topCap.frame = CGRect(x: x - capExtra, y: screenH - topH, width: Config.pipeCapWidth, height: Config.pipeCapHeight)
        topCap.contents = FlappySprites.pipeCapImage
        topCap.magnificationFilter = .nearest
        topCap.minificationFilter = .nearest
        topCap.contentsGravity = .resize
        root.addSublayer(topCap)

        // Bottom body
        let bottomBody = CALayer()
        let bottomBodyH = max(bottomH - Config.pipeCapHeight, 0)
        bottomBody.frame = CGRect(x: x, y: 0, width: Config.pipeBodyWidth, height: bottomBodyH)
        bottomBody.contents = FlappySprites.pipeBodyImage
        bottomBody.magnificationFilter = .nearest
        bottomBody.minificationFilter = .nearest
        bottomBody.contentsGravity = .resize
        root.addSublayer(bottomBody)

        // Bottom cap
        let bottomCap = CALayer()
        bottomCap.frame = CGRect(x: x - capExtra, y: bottomBodyH, width: Config.pipeCapWidth, height: Config.pipeCapHeight)
        bottomCap.contents = FlappySprites.pipeCapImage
        bottomCap.magnificationFilter = .nearest
        bottomCap.minificationFilter = .nearest
        bottomCap.contentsGravity = .resize
        root.addSublayer(bottomCap)

        pipes.append(PipePair(topBody: topBody, topCap: topCap,
                              bottomBody: bottomBody, bottomCap: bottomCap,
                              x: x, gapCenterY: gapY, scored: false))
    }

    private func updatePipeLayers(screen: CGRect) {
        let capExtra = (Config.pipeCapWidth - Config.pipeBodyWidth) / 2

        for pair in pipes {
            let topH = pair.gapCenterY - pipeGap / 2
            let bottomY = pair.gapCenterY + pipeGap / 2
            let bottomH = screen.maxY - bottomY

            let topBodyH = max(topH - Config.pipeCapHeight, 0)
            pair.topBody.frame = CGRect(x: pair.x, y: screenH - topBodyH, width: Config.pipeBodyWidth, height: topBodyH)
            pair.topCap.frame = CGRect(x: pair.x - capExtra, y: screenH - topH, width: Config.pipeCapWidth, height: Config.pipeCapHeight)

            let bottomBodyH = max(bottomH - Config.pipeCapHeight, 0)
            pair.bottomBody.frame = CGRect(x: pair.x, y: 0, width: Config.pipeBodyWidth, height: bottomBodyH)
            pair.bottomCap.frame = CGRect(x: pair.x - capExtra, y: bottomBodyH, width: Config.pipeCapWidth, height: Config.pipeCapHeight)
        }
    }
}
