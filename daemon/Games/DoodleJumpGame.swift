import Cocoa
import ApplicationServices

let doodlejump = DoodleJumpGame()

class DoodleJumpGame: GameBase {

    // Physics
    private var position = CGPoint.zero   // AX coords (y-down)
    private var velocityY: CGFloat = 0    // positive = downward in AX
    private let gravity: CGFloat = 750
    private let bounceImpulse: CGFloat = -500
    private let strongBounce: CGFloat = -600

    // Camera
    private var cameraY: CGFloat = 0      // AX y of the top of visible area

    // Platforms
    private struct Platform {
        let layer: CALayer
        var x: CGFloat
        var worldY: CGFloat
        let width: CGFloat
        var moving: Bool
        var moveDir: CGFloat
    }
    private var platforms: [Platform] = []
    private let platformHeight: CGFloat = 14
    private var platformWidth: CGFloat = 70
    private var nextPlatformY: CGFloat = 0
    private var platformSpacing: CGFloat = 100

    // Scoring
    private var highestY: CGFloat = 0

    // Overlay
    private var overlayWindow: NSWindow?
    private var overlayLayer: CALayer?

    // Colors (kept for fallback reference)
    private let platformColor = NSColor(red: 0.2, green: 0.7, blue: 0.3, alpha: 1.0).cgColor
    private let movingPlatformColor = NSColor(red: 0.6, green: 0.4, blue: 0.2, alpha: 1.0).cgColor

    // Pixel-art sprites
    private enum Sprites {
        // Palette
        private static let G: UInt32 = 0x3ACC50  // bright grass green
        private static let Y: UInt32 = 0x7ACC3A  // yellow-green grass
        private static let E: UInt32 = 0x8B6930  // earthy brown
        private static let S: UInt32 = 0x6B4F20  // darker brown base
        private static let T: UInt32 = 0x5A4318  // stone texture dark
        private static let O: UInt32 = 0          // transparent

        // Moving platform palette
        private static let N: UInt32 = 0x9B7B4A  // tan base
        private static let W: UInt32 = 0xCCB030  // warning yellow
        private static let R: UInt32 = 0x6B4F20  // brown stripe

        // Normal platform 24x5: grassy top, earthy body, stone base
        static let normal: [[UInt32]] = [
            [O,G,Y,G,O,G,G,Y,G,O,O,G,Y,G,O,G,G,Y,O,G,Y,G,G,O],
            [E,E,E,E,E,E,E,E,E,E,E,E,E,E,E,E,E,E,E,E,E,E,E,E],
            [E,E,E,E,E,E,E,E,E,E,E,E,E,E,E,E,E,E,E,E,E,E,E,E],
            [S,S,S,S,T,S,S,S,T,S,S,S,S,S,T,S,S,S,S,T,S,S,S,S],
            [T,S,S,T,T,S,S,T,T,T,S,S,T,T,T,S,S,T,T,T,S,S,T,T],
        ]

        // Moving platform 24x5: diagonal warning stripes
        static let moving: [[UInt32]] = [
            [N,N,W,W,N,N,W,W,N,N,W,W,N,N,W,W,N,N,W,W,N,N,W,W],
            [W,N,N,W,W,N,N,W,W,N,N,W,W,N,N,W,W,N,N,W,W,N,N,W],
            [W,W,N,N,W,W,N,N,W,W,N,N,W,W,N,N,W,W,N,N,W,W,N,N],
            [R,W,W,N,R,W,W,N,R,W,W,N,R,W,W,N,R,W,W,N,R,W,W,N],
            [R,R,W,W,R,R,W,W,R,R,W,W,R,R,W,W,R,R,W,W,R,R,W,W],
        ]

        static let normalImage: CGImage? = renderPixelArt(normal, scale: 3)
        static let movingImage: CGImage? = renderPixelArt(moving, scale: 3)

        private static func renderPixelArt(_ pixels: [[UInt32]], scale: Int) -> CGImage? {
            GameBase.renderPixelArt(pixels, scale: scale)
        }
    }

    // MARK: - GameBase Hooks

    override func onStart(screen: CGRect, pip: PipWindowInfo) {
        platforms = []
        velocityY = bounceImpulse

        platformWidth = cachedPipSize.width * 1.4

        position = CGPoint(x: screen.midX - cachedPipSize.width / 2,
                           y: screen.maxY - cachedPipSize.height - 80)
        cameraY = screen.minY
        highestY = position.y

        nextPlatformY = position.y + cachedPipSize.height + 10
        platformSpacing = 100

        if Thread.isMainThread {
            createOverlays(screen: screen)
        } else {
            DispatchQueue.main.sync { self.createOverlays(screen: screen) }
        }

        // Create initial platforms filling the screen
        let startY = position.y + cachedPipSize.height + 10
        nextPlatformY = startY
        while nextPlatformY > cameraY - 100 {
            spawnPlatform(screen: screen)
        }

        // Guaranteed platform under starting position
        if let rootLayer = overlayLayer {
            let layer = CALayer()
            layer.contents = Sprites.normalImage
            layer.magnificationFilter = .nearest
            layer.minificationFilter = .nearest
            layer.contentsGravity = .resize
            rootLayer.addSublayer(layer)
            let platX = position.x + cachedPipSize.width / 2 - platformWidth / 2
            let platWorldY = position.y + cachedPipSize.height + 5
            platforms.append(Platform(layer: layer, x: platX, worldY: platWorldY,
                                      width: platformWidth, moving: false, moveDir: 0))
        }

        print("Doodle Jump started")
    }

    override func onStop() {
        let ow = overlayWindow
        let cleanup = { ow?.orderOut(nil) }
        if Thread.isMainThread { cleanup() }
        else { DispatchQueue.main.async { cleanup() } }
        overlayWindow = nil
        overlayLayer = nil
        platforms = []
        print("Doodle Jump stopped")
    }

    // MARK: - Overlays

    private func createOverlays(screen: CGRect) {
        let (ow, rootLayer) = createFullscreenOverlay(screen: screen)
        overlayWindow = ow
        overlayLayer = rootLayer

        createScoreOverlay(screen: screen)
    }

    // MARK: - Game Loop

    override func gameTick() {
        guard active, let _ = cachedAXWindow else { return }

        let screen = getScreenFrame()
        let size = cachedPipSize
        let dt = deltaTime()

        if checkGameOverTimeout() { return }

        // Mouse X controls horizontal
        guard let mousePos = mousePosition() else { return }
        position.x = mousePos.x - size.width / 2
        position.x = max(screen.minX, min(position.x, screen.maxX - size.width))

        // Gravity
        velocityY += gravity * dt
        position.y += velocityY * dt

        // Platform collision (only when falling)
        if velocityY > 0 {
            let pipBottom = position.y + size.height
            let pipLeft = position.x
            let pipRight = position.x + size.width

            for plat in platforms {
                let platTop = plat.worldY
                let platLeft = plat.x
                let platRight = plat.x + plat.width

                if pipRight > platLeft + 5 && pipLeft < platRight - 5 {
                    let prevBottom = pipBottom - velocityY * dt
                    if prevBottom <= platTop + 5 && pipBottom >= platTop {
                        position.y = platTop - size.height
                        velocityY = score > 30 ? strongBounce : bounceImpulse
                        borderRef?.tilt(0.15)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                            self?.borderRef?.tilt(0)
                        }
                        break
                    }
                }
            }
        }

        // Track highest point
        if position.y < highestY {
            let gained = Int((highestY - position.y) / 10)
            score += gained
            highestY = position.y
            scoreLabel?.stringValue = "\(score)"
        }

        // Camera follows PiP upward
        let targetCameraY = position.y - screen.height * 0.35
        if targetCameraY < cameraY {
            cameraY = targetCameraY
        }

        // Spawn platforms above camera
        while nextPlatformY > cameraY - 200 {
            spawnPlatform(screen: screen)
        }

        // Remove platforms far below camera
        let cullY = cameraY + screen.height + 200
        platforms.removeAll { plat in
            if plat.worldY > cullY {
                plat.layer.removeFromSuperlayer()
                return true
            }
            return false
        }

        // Move moving platforms
        for i in 0..<platforms.count where platforms[i].moving {
            platforms[i].x += platforms[i].moveDir * dt
            if platforms[i].x < screen.minX {
                platforms[i].x = screen.minX
                platforms[i].moveDir = abs(platforms[i].moveDir)
            }
            if platforms[i].x + platforms[i].width > screen.maxX {
                platforms[i].x = screen.maxX - platforms[i].width
                platforms[i].moveDir = -abs(platforms[i].moveDir)
            }
        }

        // Game over: fell below screen
        let screenBottom = cameraY + screen.height
        if position.y > screenBottom + 50 {
            triggerGameOver(message: "GAME OVER \(score)")
            print("Doodle Jump game over: score=\(score)")
            return
        }

        // Move PiP
        let screenPosY = position.y - cameraY + screen.minY
        let newPos = CGPoint(x: position.x, y: screenPosY)
        if !movePip(to: newPos) { return }

        let bounds = CGRect(origin: newPos, size: size)

        // Update visuals
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        for plat in platforms {
            let platScreenY = plat.worldY - cameraY + screen.minY
            let nsY = screenH - platScreenY - platformHeight
            plat.layer.frame = CGRect(x: plat.x, y: nsY, width: plat.width, height: platformHeight)
            plat.layer.isHidden = platScreenY < screen.minY - 20 || platScreenY > screen.minY + screen.height + 20
        }

        syncBorder(around: bounds)

        CATransaction.commit()
    }

    // MARK: - Helpers

    private func spawnPlatform(screen: CGRect) {
        guard let rootLayer = overlayLayer else { return }

        let baseSpacing = cachedPipSize.height * 0.8
        let spacing = min(baseSpacing + CGFloat(score) * 0.25, baseSpacing * 1.6)
        nextPlatformY -= spacing

        let isMoving = score > 15 && CGFloat.random(in: 0...1) < 0.3
        let x = CGFloat.random(in: screen.minX...(screen.maxX - platformWidth))

        let layer = CALayer()
        layer.contents = isMoving ? Sprites.movingImage : Sprites.normalImage
        layer.magnificationFilter = .nearest
        layer.minificationFilter = .nearest
        layer.contentsGravity = .resize

        rootLayer.addSublayer(layer)

        platforms.append(Platform(
            layer: layer,
            x: x,
            worldY: nextPlatformY,
            width: platformWidth,
            moving: isMoving,
            moveDir: isMoving ? CGFloat.random(in: 40...100) * (Bool.random() ? 1 : -1) : 0
        ))
    }
}
