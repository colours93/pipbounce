import Cocoa
import ApplicationServices



class BounceGame: GameBase {

    // MARK: - Pixel Art Sprites (see BounceSprites.swift)

    // Mode
    var paddleMode = false  // false = pure physics toy, true = paddle game

    // Physics
    private var position = CGPoint.zero
    private var velocity = CGPoint.zero
    private let gravity: CGFloat = 120
    private let elasticity: CGFloat = 0.9
    private let airFriction: CGFloat = 0.9993
    private let restThreshold: CGFloat = 3

    // Drag state
    private var isDragging = false
    var wasMouseDown = false
    private var grabOffset = CGPoint.zero
    private var posHistory: [(pos: CGPoint, time: UInt64)] = []

    // Tilt
    private var tiltAngle: CGFloat = 0

    // AI Paddle (paddle mode only)
    private var paddleWindow: NSWindow?
    private var paddleLayer: CALayer?
    private var paddlePos = CGPoint.zero
    private var paddleEdge = 0
    private var paddleEdgeT: CGFloat = 0.5
    private let paddleLength: CGFloat = 80
    private let paddleThickness: CGFloat = 6
    private let paddleBaseSpeed: CGFloat = 0.15   // starting speed (slow, easy to catch)
    private let paddleMaxSpeed: CGFloat = 0.40     // cap at high scores
    private var paddleHitCooldown: UInt64 = 0

    // AI behavior
    private var reactionTarget: CGFloat = 0.125    // where the paddle "thinks" it should go (updated with delay)
    private var reactionTimer: CGFloat = 0          // countdown to next target update
    private var dodgeOffset: CGFloat = 0            // random imprecision in dodge target
    private var panicFreezeTimer: CGFloat = 0       // brief hesitation when PiP gets close

    // Score (paddle mode only)
    private var triggeredMilestones: Set<Int> = []

    // Perk system
    let perkState = PerkState()
    var perkUI: BouncePerkUI?
    var isPerkSelecting = false


    // MARK: - GameBase Hooks

    override func onStart(screen: CGRect, pip: PipWindowInfo) {
        position = pip.bounds.origin
        velocity = .zero
        isDragging = false
        wasMouseDown = false
        grabOffset = .zero
        posHistory = []
        tiltAngle = 0
        triggeredMilestones = []
        paddleEdge = 2
        paddleEdgeT = 0.5
        paddleHitCooldown = 0
        perimeterT = 0.125
        reactionTarget = 0.125
        reactionTimer = 0
        dodgeOffset = 0
        panicFreezeTimer = 0
        perkState.reset()
        isPerkSelecting = false

        borderRef?.rotationPadding = max(pip.bounds.size.width, pip.bounds.size.height) * 0.3

        if paddleMode {
            if Thread.isMainThread {
                createPaddleOverlays(screen: screen)
            } else {
                DispatchQueue.main.sync { self.createPaddleOverlays(screen: screen) }
            }
            let pui = BouncePerkUI(game: self)
            pui.createHUD(screen: screen, screenH: screenH)
            perkUI = pui
        }

        print("Bounce started (paddleMode=\(paddleMode))")
    }

    private func createPaddleOverlays(screen: CGRect) {
        // Paddle window
        let pw = NSWindow(contentRect: NSRect(x: 0, y: 0, width: paddleLength, height: paddleThickness),
                          styleMask: .borderless, backing: .buffered, defer: false)
        pw.isOpaque = false
        pw.backgroundColor = .clear
        pw.level = .floating
        pw.ignoresMouseEvents = true
        pw.hasShadow = false
        pw.collectionBehavior = [.canJoinAllSpaces, .stationary, .transient, .ignoresCycle]
        pw.contentView!.wantsLayer = true
        let rootLayer = pw.contentView!.layer!
        rootLayer.backgroundColor = NSColor.clear.cgColor

        // Pixel art paddle layer
        let pLayer = CALayer()
        pLayer.contents = BounceSprites.paddleForColor(settings.glowColor)
        pLayer.magnificationFilter = .nearest
        pLayer.minificationFilter = .nearest
        pLayer.contentsGravity = .resize
        pLayer.frame = rootLayer.bounds
        rootLayer.addSublayer(pLayer)
        paddleLayer = pLayer

        // Gentle opacity pulse
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 0.8
        pulse.toValue = 1.0
        pulse.duration = 1.8
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        pLayer.add(pulse, forKey: "pulse")

        pw.orderFrontRegardless()
        paddleWindow = pw

        // Score overlay — shared liquid glass pill
        createScoreOverlay(screen: screen)
    }

    override func onStop() {
        borderRef?.rotationPadding = 0

        paddleLayer?.removeAllAnimations()
        paddleLayer = nil
        paddleWindow?.orderOut(nil)
        paddleWindow = nil
        perkUI?.cleanup()
        perkUI = nil
        isPerkSelecting = false
        paddleMode = false  // reset to default for next launch
        print("Bounce stopped — final score: \(score)")
    }

    // MARK: - Game Loop

    override func gameTick() {
        guard active, let _ = cachedAXWindow else { return }

        if isPerkSelecting {
            perkUI?.tickSelection()
            return
        }

        refreshPipSize()
        borderRef?.rotationPadding = max(cachedPipSize.width, cachedPipSize.height) * 0.3

        let screen = getScreenFrame()
        let size = cachedPipSize
        let dt = deltaTime()
        let now = mach_absolute_time()

        guard let mousePos = mousePosition() else { return }
        let mouseDown = isMouseDown

        let pipRect = CGRect(origin: position, size: size)

        // --- Drag detection ---

        if mouseDown && !wasMouseDown && pipRect.contains(mousePos) {
            isDragging = true
            grabOffset = CGPoint(x: mousePos.x - position.x, y: mousePos.y - position.y)
            velocity = .zero
            posHistory = [(pos: mousePos, time: now)]
        } else if !mouseDown && wasMouseDown && isDragging {
            isDragging = false
            if posHistory.count >= 2, let first = posHistory.first, let last = posHistory.last {
                let elapsed = machToSeconds(last.time - first.time)
                if elapsed > 0.001 {
                    velocity.x = (last.pos.x - first.pos.x) / elapsed
                    velocity.y = (last.pos.y - first.pos.y) / elapsed
                }
            }
            posHistory = []
        }

        wasMouseDown = mouseDown

        // --- Update position ---

        if isDragging {
            position.x = mousePos.x - grabOffset.x
            position.y = mousePos.y - grabOffset.y
            posHistory.append((pos: mousePos, time: now))
            if posHistory.count > 8 { posHistory.removeFirst() }
        } else {
            velocity.y += gravity * dt
            velocity.x *= pow(airFriction, dt * 500)
            velocity.y *= pow(airFriction, dt * 500)

            // Clamp velocity so PiP can't teleport across screen in one frame
            let maxVel: CGFloat = 2000
            velocity.x = max(-maxVel, min(maxVel, velocity.x))
            velocity.y = max(-maxVel, min(maxVel, velocity.y))

            // Homing: nudge velocity toward paddle center
            if paddleMode && perkState.homingStrength > 0, let pw = paddleWindow {
                let paddleCenter = CGPoint(x: pw.frame.midX, y: screenH - pw.frame.midY)
                let pipCenter = CGPoint(x: position.x + cachedPipSize.width / 2,
                                         y: position.y + cachedPipSize.height / 2)
                let toP = CGPoint(x: paddleCenter.x - pipCenter.x, y: paddleCenter.y - pipCenter.y)
                let dist = Self.distance(paddleCenter, pipCenter)
                if dist > 1 {
                    let spd = sqrt(velocity.x * velocity.x + velocity.y * velocity.y)
                    let nudge = perkState.homingStrength * spd
                    velocity.x += toP.x / dist * nudge
                    velocity.y += toP.y / dist * nudge
                }
            }

            // Gravity well: pull toward paddle when close
            if paddleMode && perkState.gravityWellStrength > 0, let pw = paddleWindow {
                let paddleCenter = CGPoint(x: pw.frame.midX, y: screenH - pw.frame.midY)
                let pipCenter = CGPoint(x: position.x + cachedPipSize.width / 2,
                                         y: position.y + cachedPipSize.height / 2)
                let dx = paddleCenter.x - pipCenter.x
                let dy = paddleCenter.y - pipCenter.y
                let dist = Self.distance(paddleCenter, pipCenter)
                if dist < 120 && dist > 1 {
                    velocity.x += dx / dist * perkState.gravityWellStrength * dt
                    velocity.y += dy / dist * perkState.gravityWellStrength * dt
                }
            }

            position.x += velocity.x * dt
            position.y += velocity.y * dt

            // Bounce off screen edges (slide along edge, don't glitch through)
            var wallBounced = false
            if position.x < screen.minX {
                position.x = screen.minX
                velocity.x = abs(velocity.x) * elasticity
                wallBounced = true
            }
            if position.x + size.width > screen.maxX {
                position.x = screen.maxX - size.width
                velocity.x = -abs(velocity.x) * elasticity
                wallBounced = true
            }
            if position.y < screen.minY {
                position.y = screen.minY
                velocity.y = abs(velocity.y) * elasticity
                wallBounced = true
            }
            if position.y + size.height > screen.maxY {
                position.y = screen.maxY - size.height
                velocity.y = -abs(velocity.y) * elasticity
                wallBounced = true
            }

            // Ricochet: add random angle deviation on wall bounce
            if wallBounced && paddleMode && perkState.ricochetAngle > 0 {
                let speed = sqrt(velocity.x * velocity.x + velocity.y * velocity.y)
                if speed > 1 {
                    let angle = atan2(velocity.y, velocity.x)
                    let deviation = CGFloat.random(in: -perkState.ricochetAngle...perkState.ricochetAngle)
                    velocity.x = cos(angle + deviation) * speed
                    velocity.y = sin(angle + deviation) * speed
                }
            }

            // Hard clamp
            position.x = max(screen.minX, min(position.x, screen.maxX - size.width))
            position.y = max(screen.minY, min(position.y, screen.maxY - size.height))

            // Rest detection
            let speed = sqrt(velocity.x * velocity.x + velocity.y * velocity.y)
            if speed < restThreshold {
                velocity = .zero
            }
        }

        // --- Move PiP ---
        if !movePip(to: position) { return }

        // --- AI Paddle (paddle mode only) ---
        if paddleMode {
            perkState.tickTimers(dt: dt)
            tickPaddle(screen: screen, size: size, now: now, dt: dt)
            perkUI?.updateHUD(perkState: perkState)
        }

        // --- Update border ---
        let bounds = CGRect(origin: position, size: size)
        lastBounds = bounds

        withTransaction {
            if settings.glow, let border = borderRef {
                border.show(around: bounds)
                if !isDragging {
                    let speed = sqrt(velocity.x * velocity.x + velocity.y * velocity.y)
                    if speed > 20 {
                        let targetTilt = atan2(velocity.y, velocity.x) * 0.15
                        tiltAngle += (targetTilt - tiltAngle) * (1.0 - pow(1.0 - 0.08, dt * 500))
                    } else {
                        tiltAngle *= pow(0.9, dt * 500)
                    }
                } else {
                    tiltAngle *= pow(0.9, dt * 500)
                }
                border.tilt(tiltAngle)
            }
        }
    }

    // MARK: - Paddle Logic

    /// Perimeter position: 0..1 maps continuously around the screen edges.
    /// 0.00–0.25 = bottom (left to right)
    /// 0.25–0.50 = right  (bottom to top)
    /// 0.50–0.75 = top    (right to left)
    /// 0.75–1.00 = left   (top to bottom)
    private var perimeterT: CGFloat = 0.125  // start at bottom center

    private func perimeterToEdge(_ t: CGFloat) -> (edge: Int, edgeT: CGFloat) {
        // Counter-clockwise in screen coords (y-down):
        //   bottom (left→right) → right (bottom→top) → top (right→left) → left (top→bottom)
        // edgeT always 0→1 in the direction of travel.
        // Rect code maps: bottom/top edgeT→x (0=left,1=right), right/left edgeT→y (0=top,1=bottom)
        let t = t - floor(t)
        if t < 0.25      { return (2, t / 0.25) }                       // bottom: edgeT 0→1 = left→right
        else if t < 0.50  { return (1, 1.0 - (t - 0.25) / 0.25) }       // right:  edgeT 1→0 = bottom→top (reversed for rect)
        else if t < 0.75  { return (0, 1.0 - (t - 0.50) / 0.25) }       // top:    edgeT 1→0 = right→left (reversed for rect)
        else              { return (3, (t - 0.75) / 0.25) }              // left:   edgeT 0→1 = top→bottom
    }

    private func pointToPerimeterT(point: CGPoint, screen: CGRect) -> CGFloat {
        // Find closest perimeter position for a point (used to compute dodge target)
        // Must match perimeterToEdge so corners are physically continuous
        let w = screen.width
        let h = screen.height
        let px = (point.x - screen.minX) / w   // 0=left, 1=right
        let py = (point.y - screen.minY) / h   // 0=top, 1=bottom

        let dTop = py
        let dBot = 1.0 - py
        let dLeft = px
        let dRight = 1.0 - px

        let minD = min(dTop, dBot, dLeft, dRight)
        if minD == dBot  { return px * 0.25 }                    // bottom: left→right = 0→0.25
        if minD == dRight { return 0.25 + (1.0 - py) * 0.25 }    // right:  bottom→top = 0.25→0.50
        if minD == dTop  { return 0.50 + (1.0 - px) * 0.25 }     // top:    right→left = 0.50→0.75
        return 0.75 + py * 0.25                                   // left:   top→bottom = 0.75→1.0
    }

    private func currentPaddleSpeed() -> CGFloat {
        // Ramps from base to max over score 0..50, plus perk level bonus
        let t = min(CGFloat(score) / 50.0, 1.0)
        let base = paddleBaseSpeed + (paddleMaxSpeed - paddleBaseSpeed) * t
        return min(base + perkState.paddleSpeedBonus, 0.50)
    }

    private func currentReactionInterval() -> CGFloat {
        let t = min(CGFloat(score) / 40.0, 1.0)
        let base = 0.35 - 0.25 * t
        return max(base - perkState.reactionDelayReduction, 0.05)
    }

    private func currentDodgeInaccuracy() -> CGFloat {
        let t = min(CGFloat(score) / 60.0, 1.0)
        let base = 0.15 - 0.10 * t
        return max(base - perkState.dodgeInaccuracyReduction, 0.015)
    }

    private func tickPaddle(screen: CGRect, size: CGSize, now: UInt64, dt: CGFloat) {
        let pipCenter = CGPoint(x: position.x + size.width / 2, y: position.y + size.height / 2)
        let pipPerimT = pointToPerimeterT(point: pipCenter, screen: screen)

        // --- Reaction delay: only update dodge target periodically ---
        reactionTimer -= dt
        if reactionTimer <= 0 {
            reactionTimer = currentReactionInterval()

            // Target: opposite side, but with inaccuracy
            var idealTarget = pipPerimT + 0.5
            if idealTarget >= 1.0 { idealTarget -= 1.0 }

            // Add random offset (the paddle isn't a perfect dodger)
            let inaccuracy = currentDodgeInaccuracy()
            dodgeOffset = CGFloat.random(in: -inaccuracy...inaccuracy)

            reactionTarget = idealTarget + dodgeOffset
            if reactionTarget < 0 { reactionTarget += 1.0 }
            if reactionTarget >= 1.0 { reactionTarget -= 1.0 }
        }

        // Drunk: wobble the reaction target each frame
        if perkState.isActive(.drunk) {
            reactionTarget += CGFloat.random(in: -0.10...0.10)
            if reactionTarget < 0 { reactionTarget += 1.0 }
            if reactionTarget >= 1.0 { reactionTarget -= 1.0 }
        }

        // Ghost: paddle dodges blind (random target)
        if perkState.isActive(.ghost) {
            reactionTarget = CGFloat.random(in: 0..<1.0)
        }

        // --- Panic: when PiP is heading straight at the paddle, brief freeze ---
        let paddlePos = CGPoint(x: screen.minX + perimeterT * screen.width,
                                y: screen.minY + perimeterT * screen.height)
        let distToPaddle = Self.distance(pipCenter, paddlePos)
        let screenDiag = sqrt(screen.width * screen.width + screen.height * screen.height)

        if panicFreezeTimer > 0 {
            panicFreezeTimer -= dt
        } else if distToPaddle < screenDiag * 0.15 {
            // PiP got close — paddle panics and freezes briefly
            // Less panic at higher scores (paddle gets braver)
            let panicChance = max(0.03, 0.5 - CGFloat(score) * 0.008 - perkState.panicChanceReduction)
            if CGFloat.random(in: 0...1) < panicChance {
                panicFreezeTimer = CGFloat.random(in: 0.08...0.25)
            }
        }

        // --- Move along perimeter toward reaction target ---
        var effectiveSpeed: CGFloat
        if perkState.isActive(.freeze) {
            effectiveSpeed = 0
        } else if panicFreezeTimer > 0 {
            effectiveSpeed = currentPaddleSpeed() * 0.15
        } else {
            effectiveSpeed = currentPaddleSpeed()
        }
        if perkState.isActive(.slowmo) {
            effectiveSpeed *= 0.4
        }

        var diff = reactionTarget - perimeterT
        if diff > 0.5 { diff -= 1.0 }
        if diff < -0.5 { diff += 1.0 }

        // Cap dt to prevent teleportation on frame drops
        let clampedDt = min(dt, 0.033)  // never move more than ~2 frames worth
        let moveAmount = effectiveSpeed * clampedDt
        if abs(diff) < moveAmount {
            perimeterT = reactionTarget
        } else {
            perimeterT += (diff > 0 ? 1 : -1) * moveAmount
        }
        perimeterT = perimeterT - floor(perimeterT)

        let (edge, edgeT) = perimeterToEdge(perimeterT)
        paddleEdge = edge
        paddleEdgeT = max(0.02, min(0.98, edgeT))

        // Compute paddle rect (with shrink ray)
        let effectivePaddleLen = paddleLength * perkState.paddleLengthMultiplier
        var paddleRect: CGRect
        switch paddleEdge {
        case 0:
            let x = screen.minX + paddleEdgeT * (screen.width - effectivePaddleLen)
            paddleRect = CGRect(x: x, y: screen.minY, width: effectivePaddleLen, height: paddleThickness)
        case 1:
            let y = screen.minY + paddleEdgeT * (screen.height - effectivePaddleLen)
            paddleRect = CGRect(x: screen.maxX - paddleThickness, y: y, width: paddleThickness, height: effectivePaddleLen)
        case 2:
            let x = screen.minX + paddleEdgeT * (screen.width - effectivePaddleLen)
            paddleRect = CGRect(x: x, y: screen.maxY - paddleThickness, width: effectivePaddleLen, height: paddleThickness)
        default:
            let y = screen.minY + paddleEdgeT * (screen.height - effectivePaddleLen)
            paddleRect = CGRect(x: screen.minX, y: y, width: paddleThickness, height: effectivePaddleLen)
        }

        // Earthquake: jitter paddle position
        if perkState.isActive(.earthquake) {
            paddleRect.origin.x += CGFloat.random(in: -8...8)
            paddleRect.origin.y += CGFloat.random(in: -8...8)
        }

        // Update paddle window
        if let pw = paddleWindow {
            let nsFrame = NSRect(x: paddleRect.origin.x,
                                 y: screenH - paddleRect.origin.y - paddleRect.height,
                                 width: paddleRect.width, height: paddleRect.height)
            pw.setFrame(nsFrame, display: true)
            if let pLayer = paddleLayer {
                pLayer.frame = CGRect(origin: .zero, size: nsFrame.size)
                // Ghost: flicker opacity (reset when expired)
                if perkState.isActive(.ghost) {
                    pLayer.opacity = Float.random(in: 0.05...0.3)
                } else if pLayer.opacity < 0.5 {
                    pLayer.opacity = 1.0
                }
            }
        }

        // --- Collision (thicc inflates PiP hitbox) ---
        let collisionSize = perkState.isActive(.thicc)
            ? CGSize(width: size.width * 1.8, height: size.height * 1.8)
            : size
        let pipRect = CGRect(origin: position, size: collisionSize)
        if Self.rectsCollide(pipRect, paddleRect) && now > paddleHitCooldown {
            perkState.registerHit()
            score += perkState.scorePerHit
            scoreLabel?.attributedStringValue = Self.styledScore("\(score)")
            pulseScoreOverlay()
            paddleHitCooldown = now + secondsToMach(perkState.hitCooldownSeconds)

            // On hit: nudge the paddle slightly (it got caught, needs to recover)
            perimeterT += CGFloat.random(in: -0.03...0.03)
            perimeterT = perimeterT - floor(perimeterT)
            // Force a delayed reaction to the new state
            reactionTimer = currentReactionInterval() * 1.5

            // Hit flash on paddle
            if let pLayer = paddleLayer {
                let flash = CABasicAnimation(keyPath: "opacity")
                flash.fromValue = 0.4
                flash.toValue = 1.0
                flash.duration = 0.3
                flash.isRemovedOnCompletion = true
                pLayer.add(flash, forKey: "hitFlash")
            }

            let milestones = [20, 50, 100]
            for m in milestones {
                if score == m && !triggeredMilestones.contains(m) {
                    triggeredMilestones.insert(m)
                    let tier = milestones.firstIndex(of: m)! + 1
                    borderRef?.burstGeometry(tier: tier, around: pipRect)
                }
            }

            // Check perk offering
            if perkState.shouldOfferPerk() {
                isPerkSelecting = true
                perkUI?.showSelection(perks: perkState.randomOffering(),
                                       screen: screen, screenH: screenH)
            }
        }
    }
}
