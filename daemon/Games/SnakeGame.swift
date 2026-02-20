import Cocoa
import ApplicationServices



class SnakeGame: GameBase {

    // Movement
    private let baseSpeed: CGFloat = 200.0
    private let speedPerFood: CGFloat = 6.0
    private let maxSpeed: CGFloat = 420.0
    private var currentSpeed: CGFloat = 200.0
    private var currentAngle: CGFloat = 0
    private let maxTurnRate: CGFloat = 6.0  // rad/s
    private var headPos = CGPoint.zero       // world coordinates

    // Click boost
    private var wasMouseDown = false
    private var boostUntilMach: UInt64 = 0
    private var boostCooldownMach: UInt64 = 0
    private let boostMultiplier: CGFloat = 2.0
    private let boostDuration: Double = 0.3
    private let boostCooldown: Double = 2.0

    // Distance-based tail tracking
    private var distanceSamples: [CGPoint] = []
    private var distanceAccum: CGFloat = 0
    private let sampleDistance: CGFloat = 6.0
    private let segmentSpacingSamples = 5

    // Tail
    private var tailSegments: [NSWindow] = []
    private let segmentSize: CGFloat = 20
    private let minSegScale: CGFloat = 0.6
    private let maxSegScale: CGFloat = 0.9

    // Food (world coordinates)
    private var foodWindow: NSWindow?
    private let foodSize: CGFloat = 22
    private var foodPos = CGPoint.zero

    // Camera
    private var cameraX: CGFloat = 0
    private var cameraY: CGFloat = 0
    private let cameraLerp: CGFloat = 0.08

    // World size (3x screen, set at start)
    private var worldW: CGFloat = 0
    private var worldH: CGFloat = 0

    private var savedScreen = CGRect.zero

    // Particle burst overlay
    private var particleWindow: NSWindow?


    // MARK: - Pixel Art Sprites (see SnakeSprites.swift)


    // MARK: - Coordinate conversion

    private func wrap(_ val: CGFloat, _ max: CGFloat) -> CGFloat {
        let v = val.truncatingRemainder(dividingBy: max)
        return v < 0 ? v + max : v
    }

    /// Shortest signed delta on a wrapping axis (result in -max/2...max/2)
    private func wrapDelta(_ a: CGFloat, _ b: CGFloat, _ wMax: CGFloat) -> CGFloat {
        var d = a - b
        if d > wMax / 2 { d -= wMax }
        if d < -wMax / 2 { d += wMax }
        return d
    }

    /// Wrap-aware world-to-screen: positions objects relative to camera across world boundaries
    private func worldToScreen(_ wx: CGFloat, _ wy: CGFloat) -> CGPoint {
        CGPoint(x: wrapDelta(wx, cameraX, worldW) + savedScreen.minX,
                y: wrapDelta(wy, cameraY, worldH) + savedScreen.minY)
    }

    private func screenToWorld(_ sx: CGFloat, _ sy: CGFloat) -> CGPoint {
        CGPoint(x: sx + cameraX - savedScreen.minX,
                y: sy + cameraY - savedScreen.minY)
    }

    // MARK: - GameBase Hooks

    override func onStart(screen: CGRect, pip: PipWindowInfo) {
        timerIntervalMs = 8
        distanceSamples = []
        distanceAccum = 0
        tailSegments = []
        lastSpriteCount = 0
        currentSpeed = baseSpeed
        wasMouseDown = false
        boostUntilMach = 0
        boostCooldownMach = 0
        savedScreen = screen

        // World = 3x screen
        worldW = screen.width * 3
        worldH = screen.height * 3

        // Start in center of world
        headPos = CGPoint(x: worldW / 2 - pip.bounds.size.width / 2,
                          y: worldH / 2 - pip.bounds.size.height / 2)
        currentAngle = 0

        // Center camera
        cameraX = headPos.x + cachedPipSize.width / 2 - screen.width / 2
        cameraY = headPos.y + cachedPipSize.height / 2 - screen.height / 2

        distanceSamples.append(headPos)

        var initPos = worldToScreen(headPos.x, headPos.y)
        if let val = AXValueCreate(.cgPoint, &initPos) {
            AXUIElementSetAttributeValue(pip.axWindow, kAXPositionAttribute as CFString, val)
        }

        if Thread.isMainThread {
            createOverlays(screen: screen)
        } else {
            DispatchQueue.main.sync { self.createOverlays(screen: screen) }
        }

        spawnFood()

        print("Snake started (world=\(Int(worldW))x\(Int(worldH)))")
    }

    override func onStop() {
        let fw = foodWindow
        let pw = particleWindow
        let segs = tailSegments
        let cleanup = {
            fw?.orderOut(nil)
            pw?.orderOut(nil)
            for s in segs { s.orderOut(nil) }
        }
        if Thread.isMainThread { cleanup() }
        else { DispatchQueue.main.async { cleanup() } }

        foodWindow = nil
        particleWindow = nil
        tailSegments = []
        distanceSamples = []
        print("Snake stopped")
    }

    // MARK: - Game Loop

    override func gameTick() {
        guard active, let _ = cachedAXWindow else { return }

        let screen = getScreenFrame()
        savedScreen = screen
        let dt = deltaTime()

        refreshPipSize()
        let size = cachedPipSize

        if checkGameOverTimeout() { return }

        // Click boost
        let mouseDown = isMouseDown
        let now = mach_absolute_time()
        if mouseDown && !wasMouseDown && now >= boostCooldownMach {
            boostUntilMach = now + secondsToMach(boostDuration)
            boostCooldownMach = now + secondsToMach(boostCooldown)
        }
        wasMouseDown = mouseDown

        let boosting = now < boostUntilMach
        let speedMul: CGFloat = boosting ? boostMultiplier : 1.0
        let effectiveSpeed = min(currentSpeed * speedMul, maxSpeed * boostMultiplier)

        // Mouse -> world for steering
        guard let mousePos = mousePosition() else { return }
        let mouseWorld = screenToWorld(mousePos.x, mousePos.y)

        let headCenterX = headPos.x + size.width / 2
        let headCenterY = headPos.y + size.height / 2
        let dx = wrapDelta(mouseWorld.x, headCenterX, worldW)
        let dy = wrapDelta(mouseWorld.y, headCenterY, worldH)
        let dist = sqrt(dx * dx + dy * dy)

        if dist > 2.0 {
            let targetAngle = atan2(dy, dx)
            var diff = targetAngle - currentAngle
            while diff > .pi { diff -= 2 * .pi }
            while diff < -.pi { diff += 2 * .pi }
            let maxTurn = maxTurnRate * dt
            if abs(diff) < maxTurn {
                currentAngle = targetAngle
            } else {
                currentAngle += (diff > 0 ? maxTurn : -maxTurn)
            }
        }

        let prevHead = headPos
        headPos.x += cos(currentAngle) * effectiveSpeed * dt
        headPos.y += sin(currentAngle) * effectiveSpeed * dt

        // Compute travel distance before wrapping (small, correct values)
        let travelDx = headPos.x - prevHead.x
        let travelDy = headPos.y - prevHead.y
        distanceAccum += sqrt(travelDx * travelDx + travelDy * travelDy)

        // World wrapping (wrap, no bounce)
        headPos.x = wrap(headPos.x + size.width / 2, worldW) - size.width / 2
        headPos.y = wrap(headPos.y + size.height / 2, worldH) - size.height / 2

        // Distance-based sampling (after wrap so samples use wrapped coords)
        while distanceAccum >= sampleDistance {
            distanceAccum -= sampleDistance
            distanceSamples.append(headPos)
        }

        let maxNeeded = (tailSegments.count + 2) * segmentSpacingSamples + 20
        if distanceSamples.count > maxNeeded * 2 {
            distanceSamples.removeFirst(distanceSamples.count - maxNeeded)
        }

        // Food collision (wrap-aware)
        let foodDx = wrapDelta(foodPos.x + foodSize / 2, headPos.x + size.width / 2, worldW)
        let foodDy = wrapDelta(foodPos.y + foodSize / 2, headPos.y + size.height / 2, worldH)
        let foodCollisionDist = max(abs(foodDx) - (size.width + foodSize) / 2,
                                     abs(foodDy) - (size.height + foodSize) / 2)
        if foodCollisionDist < 0 {
            let eatPos = foodPos
            score += 1
            currentSpeed = min(baseSpeed + speedPerFood * CGFloat(score), maxSpeed)
            addTailSegment()
            spawnFood()
            emitFoodParticles(at: eatPos)
        }

        // Self collision (head vs tail, wrap-aware)
        let headCX = headPos.x + size.width / 2
        let headCY = headPos.y + size.height / 2
        for i in 0..<tailSegments.count {
            let historyIndex = (i + 1) * segmentSpacingSamples
            if historyIndex >= distanceSamples.count { break }
            let segIdx = distanceSamples.count - 1 - historyIndex
            let segPos = distanceSamples[segIdx]
            let segCX = segPos.x + cachedPipSize.width / 2
            let segCY = segPos.y + cachedPipSize.height / 2
            let t = segScaleForIndex(i)
            let sz = segmentSize * t
            let inset: CGFloat = 4
            let colDx = abs(wrapDelta(segCX, headCX, worldW))
            let colDy = abs(wrapDelta(segCY, headCY, worldH))
            let halfW = (size.width / 2 - 4) + (sz / 2 - inset)
            let halfH = (size.height / 2 - 4) + (sz / 2 - inset)
            if colDx < halfW && colDy < halfH {
                triggerSnakeGameOver()
                return
            }
        }

        // Update camera (wrap-aware lerp)
        let targetCamX = headPos.x + size.width / 2 - screen.width / 2
        let targetCamY = headPos.y + size.height / 2 - screen.height / 2
        cameraX += wrapDelta(targetCamX, cameraX, worldW) * cameraLerp
        cameraY += wrapDelta(targetCamY, cameraY, worldH) * cameraLerp
        cameraX = wrap(cameraX, worldW)
        cameraY = wrap(cameraY, worldH)

        // Move PiP
        let headScreen = worldToScreen(headPos.x, headPos.y)
        if !movePip(to: headScreen) { return }

        let bounds = CGRect(origin: headScreen, size: size)

        // Update visuals
        withTransaction {
            updateTailPositions()
            updateFoodWindow()
            updateScore()
            syncBorder(around: bounds)
        }
    }

    // MARK: - Game Over

    private func triggerSnakeGameOver() {
        triggerGameOver(message: "Game Over  \(score)")

        for seg in tailSegments {
            seg.contentView?.layer?.backgroundColor = NSColor(red: 0.8, green: 0.1, blue: 0.1, alpha: 0.9).cgColor
            seg.contentView?.layer?.borderColor = NSColor(red: 1.0, green: 0.2, blue: 0.2, alpha: 1.0).cgColor
        }

        // Flash border red without mutating global settings
        if let border = borderRef {
            border.show(around: lastBounds)
        }

        print("Snake game over: score=\(score)")
    }

    // MARK: - Tail

    private func segScaleForIndex(_ i: Int) -> CGFloat {
        guard tailSegments.count > 1 else { return maxSegScale }
        let t = CGFloat(i) / CGFloat(tailSegments.count - 1)
        return maxSegScale + (minSegScale - maxSegScale) * t
    }

    private func spriteForSegmentIndex(_ i: Int) -> CGImage? {
        let count = tailSegments.count
        if count <= 1 { return SnakeSprites.bodyHead }
        if i == 0 { return SnakeSprites.bodyHead }
        if i >= count - 1 { return SnakeSprites.bodyTail }
        return SnakeSprites.bodyMid
    }

    private func addTailSegment() {
        let w = NSWindow(contentRect: NSRect(x: -100, y: screenH + 100,
                                              width: segmentSize, height: segmentSize),
                         styleMask: .borderless, backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.level = .floating
        w.ignoresMouseEvents = true
        w.hasShadow = false
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .transient, .ignoresCycle]
        w.contentView!.wantsLayer = true
        let layer = w.contentView!.layer!

        // Pixel art sprite
        layer.contents = SnakeSprites.bodyMid
        layer.magnificationFilter = .nearest
        layer.minificationFilter = .nearest

        w.orderFrontRegardless()
        tailSegments.append(w)
    }

    private var lastSpriteCount = 0

    private func updateTailPositions() {
        // Only reassign sprites when segment count changes
        let needSpriteUpdate = !gameOver && tailSegments.count != lastSpriteCount
        if needSpriteUpdate { lastSpriteCount = tailSegments.count }

        for i in 0..<tailSegments.count {
            let historyIndex = (i + 1) * segmentSpacingSamples
            let scale = segScaleForIndex(i)
            let sz = segmentSize * scale
            let seg = tailSegments[i]

            if needSpriteUpdate {
                seg.contentView?.layer?.contents = spriteForSegmentIndex(i)
            }

            if historyIndex >= distanceSamples.count {
                seg.setFrameOrigin(NSPoint(x: -100, y: screenH + 100))
                continue
            }
            let segIdx = distanceSamples.count - 1 - historyIndex

            // World position of this segment (wrap-aware screen conversion)
            let worldPos = distanceSamples[segIdx]
            let worldCX = worldPos.x + cachedPipSize.width / 2
            let worldCY = worldPos.y + cachedPipSize.height / 2

            let sp = worldToScreen(worldCX - sz / 2, worldCY - sz / 2)
            let nsY = screenH - sp.y - sz
            seg.setFrame(NSRect(x: sp.x, y: nsY, width: sz, height: sz), display: false)
        }
    }

    // MARK: - Food Particles

    private func emitFoodParticles(at worldPos: CGPoint) {
        guard let pw = particleWindow else { return }
        let sp = worldToScreen(worldPos.x + foodSize / 2, worldPos.y + foodSize / 2)
        let nsY = screenH - sp.y

        let emitter = CAEmitterLayer()
        emitter.emitterPosition = CGPoint(x: sp.x, y: nsY)
        emitter.emitterShape = .point
        emitter.renderMode = .additive

        let cell = CAEmitterCell()
        cell.birthRate = 0  // we fire manually
        cell.lifetime = 0.5
        cell.velocity = 160
        cell.velocityRange = 40
        cell.emissionRange = .pi * 2
        cell.scale = 0.12
        cell.scaleRange = 0.03
        cell.alphaSpeed = -1.8
        cell.color = NSColor(red: 0.9, green: 0.2, blue: 0.2, alpha: 1.0).cgColor
        cell.contents = makeCircleImage(size: 12, color: .white)

        let cell2 = CAEmitterCell()
        cell2.birthRate = 0
        cell2.lifetime = 0.5
        cell2.velocity = 140
        cell2.velocityRange = 30
        cell2.emissionRange = .pi * 2
        cell2.scale = 0.09
        cell2.scaleRange = 0.02
        cell2.alphaSpeed = -1.8
        cell2.color = NSColor(red: 0.1, green: 0.9, blue: 0.3, alpha: 1.0).cgColor
        cell2.contents = makeCircleImage(size: 12, color: .white)

        cell.birthRate = 50
        cell2.birthRate = 50
        emitter.emitterCells = [cell, cell2]
        emitter.beginTime = CACurrentMediaTime()
        pw.contentView!.layer!.addSublayer(emitter)

        // Stop emission after short burst by setting lifetime to 0 (scales cell lifetimes to 0)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            emitter.lifetime = 0  // prevents new particles, existing ones finish naturally
        }
        // Remove layer after all particles have faded
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            emitter.removeFromSuperlayer()
        }
    }

    private func makeCircleImage(size: CGFloat, color: NSColor) -> CGImage? {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size),
                                    pixelsHigh: Int(size), bitsPerSample: 8,
                                    samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        color.setFill()
        NSBezierPath(ovalIn: NSRect(x: 0, y: 0, width: size, height: size)).fill()
        NSGraphicsContext.restoreGraphicsState()
        return rep.cgImage
    }

    // MARK: - Food

    private func spawnFood() {
        let margin: CGFloat = 40
        for _ in 0..<50 {
            let x = CGFloat.random(in: margin...(worldW - margin - foodSize))
            let y = CGFloat.random(in: margin...(worldH - margin - foodSize))
            let candidate = CGRect(x: x, y: y, width: foodSize, height: foodSize)

            let headRect = CGRect(origin: headPos, size: cachedPipSize)
            if headRect.intersects(candidate) { continue }

            var overlaps = false
            for i in 0..<tailSegments.count {
                let historyIndex = (i + 1) * segmentSpacingSamples
                if historyIndex >= distanceSamples.count { break }
                let segIdx = distanceSamples.count - 1 - historyIndex
                let segPos = distanceSamples[segIdx]
                let segCX = segPos.x + cachedPipSize.width / 2
                let segCY = segPos.y + cachedPipSize.height / 2
                let segRect = CGRect(x: segCX - segmentSize / 2, y: segCY - segmentSize / 2,
                                     width: segmentSize, height: segmentSize)
                if segRect.intersects(candidate) { overlaps = true; break }
            }
            if overlaps { continue }

            foodPos = CGPoint(x: x, y: y)
            return
        }
        foodPos = CGPoint(
            x: CGFloat.random(in: margin...(worldW - margin - foodSize)),
            y: CGFloat.random(in: margin...(worldH - margin - foodSize)))
    }

    private func updateFoodWindow() {
        guard let fw = foodWindow else { return }
        let sp = worldToScreen(foodPos.x, foodPos.y)
        let nsY = screenH - sp.y - foodSize
        fw.setFrameOrigin(NSPoint(x: sp.x, y: nsY))
    }

    // MARK: - Overlays

    private func createOverlays(screen: CGRect) {
        // Food window
        let fw = NSWindow(contentRect: NSRect(x: 0, y: 0, width: foodSize, height: foodSize),
                          styleMask: .borderless, backing: .buffered, defer: false)
        fw.isOpaque = false
        fw.backgroundColor = .clear
        fw.level = .floating
        fw.ignoresMouseEvents = true
        fw.hasShadow = false
        fw.collectionBehavior = [.canJoinAllSpaces, .stationary, .transient, .ignoresCycle]
        fw.contentView!.wantsLayer = true
        let foodLayer = fw.contentView!.layer!

        // Pixel art apple sprite
        foodLayer.contents = SnakeSprites.apple
        foodLayer.magnificationFilter = .nearest
        foodLayer.minificationFilter = .nearest

        // Shadow glow (red)
        let appleColor = NSColor(red: 0.9, green: 0.15, blue: 0.15, alpha: 1.0)
        foodLayer.shadowColor = appleColor.cgColor
        foodLayer.shadowRadius = 8
        foodLayer.shadowOpacity = 0.8
        foodLayer.shadowOffset = CGSize(width: 0, height: 0)

        let pulse = CABasicAnimation(keyPath: "transform.scale")
        pulse.fromValue = 0.95
        pulse.toValue = 1.1
        pulse.duration = 0.8
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        fw.contentView!.layer!.add(pulse, forKey: "pulse")

        fw.orderFrontRegardless()
        foodWindow = fw

        // Particle burst overlay (fullscreen, transparent)
        let (pw, _) = createFullscreenOverlay(screen: screen)
        particleWindow = pw

        // Score overlay
        createScoreOverlay(screen: screen, width: 100)
    }

    private func updateScore() {
        if !gameOver {
            scoreLabel?.attributedStringValue = Self.styledScore("\(score)")
        }
    }
}
