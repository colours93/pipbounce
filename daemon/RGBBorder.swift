import Cocoa
import QuartzCore

class RGBBorder {
    private var window: NSWindow?
    private let borderWidth: CGFloat = 1.0
    private let containerLayer = CALayer()
    private let gradientLayer = CAGradientLayer()
    private let maskLayer = CAShapeLayer()
    private var currentColor = ""

    /// Extra padding for rotation headroom. Set > 0 in game modes that tilt.
    var rotationPadding: CGFloat = 0

    private static let colorSets: [String: [CGColor]] = [
        "rainbow": [
            NSColor.red.cgColor, NSColor.yellow.cgColor, NSColor.green.cgColor,
            NSColor.cyan.cgColor, NSColor.blue.cgColor, NSColor.magenta.cgColor,
            NSColor.red.cgColor,
        ],
        "blue": [
            NSColor(red: 0.2, green: 0.5, blue: 1.0, alpha: 1).cgColor,
            NSColor(red: 0.1, green: 0.8, blue: 1.0, alpha: 1).cgColor,
            NSColor(red: 0.4, green: 0.6, blue: 1.0, alpha: 1).cgColor,
            NSColor(red: 0.0, green: 0.3, blue: 0.9, alpha: 1).cgColor,
            NSColor(red: 0.2, green: 0.5, blue: 1.0, alpha: 1).cgColor,
        ],
        "red": [
            NSColor(red: 1.0, green: 0.2, blue: 0.2, alpha: 1).cgColor,
            NSColor(red: 1.0, green: 0.5, blue: 0.3, alpha: 1).cgColor,
            NSColor(red: 1.0, green: 0.1, blue: 0.4, alpha: 1).cgColor,
            NSColor(red: 0.8, green: 0.0, blue: 0.1, alpha: 1).cgColor,
            NSColor(red: 1.0, green: 0.2, blue: 0.2, alpha: 1).cgColor,
        ],
        "purple": [
            NSColor(red: 0.7, green: 0.3, blue: 1.0, alpha: 1).cgColor,
            NSColor(red: 1.0, green: 0.4, blue: 0.8, alpha: 1).cgColor,
            NSColor(red: 0.5, green: 0.2, blue: 0.9, alpha: 1).cgColor,
            NSColor(red: 0.8, green: 0.5, blue: 1.0, alpha: 1).cgColor,
            NSColor(red: 0.7, green: 0.3, blue: 1.0, alpha: 1).cgColor,
        ],
        "green": [
            NSColor(red: 0.1, green: 0.9, blue: 0.4, alpha: 1).cgColor,
            NSColor(red: 0.3, green: 1.0, blue: 0.7, alpha: 1).cgColor,
            NSColor(red: 0.0, green: 0.7, blue: 0.3, alpha: 1).cgColor,
            NSColor(red: 0.2, green: 1.0, blue: 0.5, alpha: 1).cgColor,
            NSColor(red: 0.1, green: 0.9, blue: 0.4, alpha: 1).cgColor,
        ],
    ]

    /// rect is in AX coordinates (origin top-left, Y down).
    func show(around rect: CGRect) {
        let screenH = (NSScreen.main ?? NSScreen.screens[0]).frame.height
        let pad = rotationPadding

        // Convert AX coords -> NSWindow frame (origin bottom-left, Y up)
        // When pad > 0, the window is enlarged for rotation headroom
        let nsFrame = NSRect(
            x: rect.origin.x - borderWidth - pad,
            y: screenH - (rect.origin.y + rect.height) - borderWidth - pad,
            width: rect.width + borderWidth * 2 + pad * 2,
            height: rect.height + borderWidth * 2 + pad * 2)

        if window == nil {
            let w = NSWindow(contentRect: nsFrame, styleMask: .borderless,
                             backing: .buffered, defer: false)
            w.isOpaque = false
            w.backgroundColor = .clear
            w.level = .floating
            w.ignoresMouseEvents = true
            w.hasShadow = false
            w.collectionBehavior = [.canJoinAllSpaces, .stationary, .transient, .ignoresCycle]

            let view = NSView(frame: w.contentView!.bounds)
            view.wantsLayer = true
            w.contentView!.addSubview(view)

            view.layer!.addSublayer(containerLayer)

            gradientLayer.type = .conic
            gradientLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
            gradientLayer.endPoint = CGPoint(x: 0.5, y: 0)
            containerLayer.addSublayer(gradientLayer)

            maskLayer.fillRule = .evenOdd
            containerLayer.mask = maskLayer

            let spin = CABasicAnimation(keyPath: "transform.rotation.z")
            spin.fromValue = 0
            spin.toValue = 2 * Double.pi
            spin.duration = 3
            spin.repeatCount = .infinity
            gradientLayer.add(spin, forKey: "spin")

            w.orderFrontRegardless()
            window = w
        }

        // Update gradient colors if changed
        let color = settings.glowColor
        if color != currentColor {
            currentColor = color
            gradientLayer.colors = Self.colorSets[color] ?? Self.colorSets["rainbow"]!
        }

        window?.setFrame(nsFrame, display: true)

        // Disable implicit CoreAnimation transitions -- all updates must be instant
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let viewSize = nsFrame.size
        window?.contentView?.subviews.first?.frame = NSRect(origin: .zero, size: viewSize)

        // Use bounds + position (NOT frame) because containerLayer may have
        // a rotation transform from tilt(). Setting frame while a transform
        // is active produces undefined positioning per Apple docs.
        containerLayer.bounds = CGRect(origin: .zero, size: viewSize)
        containerLayer.position = CGPoint(x: viewSize.width / 2, y: viewSize.height / 2)

        // The border ring rect, centered within the (possibly padded) window
        let borderRect = NSRect(x: pad, y: pad,
                                width: rect.width + borderWidth * 2,
                                height: rect.height + borderWidth * 2)

        let diag = sqrt(borderRect.width * borderRect.width + borderRect.height * borderRect.height)
        let gradSize = diag + 20
        // Use bounds + position for gradient too (spin animation has active transform)
        gradientLayer.bounds = CGRect(origin: .zero, size: CGSize(width: gradSize, height: gradSize))
        gradientLayer.position = CGPoint(x: borderRect.midX, y: borderRect.midY)

        let outer = NSBezierPath(roundedRect: borderRect, xRadius: 3, yRadius: 3)
        let inner = NSBezierPath(roundedRect: borderRect.insetBy(dx: borderWidth, dy: borderWidth),
                                 xRadius: 2, yRadius: 2)
        let path = CGMutablePath()
        path.addPath(outer.cgPath)
        path.addPath(inner.cgPath)
        maskLayer.path = path

        CATransaction.commit()
    }

    /// Tilt the border by angle (radians). Used by Flappy Bird for wobble.
    func tilt(_ angle: CGFloat) {
        if angle == 0 {
            containerLayer.transform = CATransform3DIdentity
        } else {
            containerLayer.transform = CATransform3DMakeRotation(angle, 0, 0, 1)
        }
    }

    func hide() {
        window?.orderOut(nil)
        window = nil
    }
}

extension NSBezierPath {
    var cgPath: CGPath {
        let path = CGMutablePath()
        var points = [CGPoint](repeating: .zero, count: 3)
        for i in 0..<elementCount {
            switch element(at: i, associatedPoints: &points) {
            case .moveTo: path.move(to: points[0])
            case .lineTo: path.addLine(to: points[0])
            case .curveTo, .cubicCurveTo: path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .closePath: path.closeSubpath()
            default: break
            }
        }
        return path
    }
}
