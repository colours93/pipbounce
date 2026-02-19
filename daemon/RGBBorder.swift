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
        // AX coords use the primary screen's height for conversion.
        // NSScreen.screens[0] is always the primary display; NSScreen.main
        // follows keyboard focus and would break on multi-monitor setups.
        let screenH = NSScreen.screens[0].frame.height
        let pad = rotationPadding

        // Convert AX coords -> NSWindow frame (origin bottom-left, Y up)
        // When pad > 0, the window is enlarged for rotation headroom
        let nsFrame = NSRect(
            x: rect.origin.x - borderWidth - pad,
            y: screenH - (rect.origin.y + rect.height) - borderWidth - pad,
            width: rect.width + borderWidth * 2 + pad * 2,
            height: rect.height + borderWidth * 2 + pad * 2)

        if window == nil {
            CATransaction.begin()
            CATransaction.setDisableActions(true)

            let w = NSWindow(contentRect: nsFrame, styleMask: .borderless,
                             backing: .buffered, defer: false)
            w.isOpaque = false
            w.backgroundColor = .clear
            w.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
            w.ignoresMouseEvents = true
            w.hasShadow = false
            w.collectionBehavior = [.canJoinAllSpaces, .stationary, .transient, .ignoresCycle]

            let cv = w.contentView!
            cv.wantsLayer = true
            cv.layerContentsRedrawPolicy = .onSetNeedsDisplay
            cv.layer!.addSublayer(containerLayer)

            gradientLayer.type = .conic
            gradientLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
            gradientLayer.endPoint = CGPoint(x: 0.5, y: 0)
            containerLayer.addSublayer(gradientLayer)

            maskLayer.fillRule = .evenOdd
            containerLayer.mask = maskLayer

            CATransaction.commit()

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

        // Batch setFrame + layer updates inside one CATransaction to prevent
        // implicit animations and ensure the window and layers move together.
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        window?.setFrame(nsFrame, display: true)

        let viewSize = nsFrame.size

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

    // MARK: - Occult Sigil Burst Animation

    private var burstLayers: [CALayer] = []
    private var burstTimer: DispatchSourceTimer?

    /// Trigger an occult sigil burst around the current border.
    /// tier 1 = Sigil of Lucifer (inverted V, diamond, cross, binding circle)
    /// tier 2 = Metatron's Cube (13 circles + connecting lines + hexagram)
    /// tier 3 = Full summoning circle (triple ring, pentagram, Leviathan cross, rune marks, all-seeing eye)
    func burstGeometry(tier: Int, around rect: CGRect) {
        for l in burstLayers { l.removeFromSuperlayer() }
        burstLayers.removeAll()
        burstTimer?.cancel()

        guard let w = window, let rootView = w.contentView else { return }

        let pad = rotationPadding
        let center = CGPoint(x: pad + rect.width / 2 + borderWidth,
                             y: pad + rect.height / 2 + borderWidth)
        let radius = max(rect.width, rect.height) * 0.7
        let duration: CFTimeInterval = 3.2
        let colorSet = Self.colorSets[settings.glowColor] ?? Self.colorSets["purple"]!
        let mainColor = colorSet[0]
        let altColor = colorSet.count > 2 ? colorSet[2] : colorSet[0]
        let dimColor = colorSet.count > 1 ? colorSet[1] : colorSet[0]
        let faintColor = NSColor(cgColor: mainColor)!.withAlphaComponent(0.25).cgColor
        let bounds = CGRect(x: -radius * 1.8, y: -radius * 1.8,
                            width: radius * 3.6, height: radius * 3.6)

        func makeShape(color: CGColor, width: CGFloat = 1.5) -> CAShapeLayer {
            let s = CAShapeLayer()
            s.fillColor = nil
            s.strokeColor = color
            s.lineWidth = width
            s.lineCap = .round
            s.lineJoin = .round
            s.position = center
            s.bounds = bounds
            return s
        }

        func strokeDraw(delay: CFTimeInterval = 0, dur: CFTimeInterval = 0.8) -> CABasicAnimation {
            let a = CABasicAnimation(keyPath: "strokeEnd")
            a.fromValue = 0; a.toValue = 1; a.duration = dur; a.beginTime = delay
            a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            a.fillMode = .backwards
            return a
        }

        func fadeAnim(_ fromVal: Float, delay: CFTimeInterval, dur: CFTimeInterval) -> CABasicAnimation {
            let a = CABasicAnimation(keyPath: "opacity")
            a.fromValue = fromVal; a.toValue = 0; a.beginTime = delay; a.duration = dur
            a.fillMode = .forwards
            return a
        }

        func addDots(points: [CGPoint], color: CGColor, dotR: CGFloat = 3, stagger: Double = 0.08) {
            for (i, pt) in points.enumerated() {
                let dot = CAShapeLayer()
                dot.path = CGPath(ellipseIn: CGRect(x: -dotR, y: -dotR, width: dotR * 2, height: dotR * 2), transform: nil)
                dot.fillColor = color; dot.strokeColor = nil
                dot.position = center; dot.bounds = bounds
                dot.transform = CATransform3DMakeTranslation(pt.x, pt.y, 0)
                dot.opacity = 0
                rootView.layer!.addSublayer(dot); burstLayers.append(dot)
                let show = CABasicAnimation(keyPath: "opacity")
                show.fromValue = 0; show.toValue = 1; show.duration = 0.2
                show.beginTime = Double(i) * stagger; show.fillMode = .backwards
                let hide = fadeAnim(1.0, delay: duration * 0.72, dur: duration * 0.28)
                let g = CAAnimationGroup(); g.animations = [show, hide]; g.duration = duration
                g.isRemovedOnCompletion = false; g.fillMode = .forwards
                dot.add(g, forKey: "dot")
            }
        }

        func applyBurst(to layer: CAShapeLayer, drawDelay: CFTimeInterval = 0, drawDur: CFTimeInterval = 0.8,
                         spinRevs: Double = 1, fadeStart: Double = 0.72, opacity: Float = 1.0) {
            let draw = strokeDraw(delay: drawDelay, dur: drawDur)
            let spin = CABasicAnimation(keyPath: "transform.rotation.z")
            spin.fromValue = 0; spin.toValue = Double.pi * 2 * spinRevs; spin.duration = duration
            let fade = fadeAnim(opacity, delay: duration * fadeStart, dur: duration * (1 - fadeStart))
            let g = CAAnimationGroup(); g.animations = [draw, spin, fade]; g.duration = duration
            g.isRemovedOnCompletion = false; g.fillMode = .forwards
            layer.add(g, forKey: "burst")
        }

        func applyFade(to layer: CALayer, opacity: Float, delay: Double = 0.72) {
            let fade = fadeAnim(opacity, delay: duration * delay, dur: duration * (1 - delay))
            let g = CAAnimationGroup(); g.animations = [fade]; g.duration = duration
            g.isRemovedOnCompletion = false; g.fillMode = .forwards
            layer.add(g, forKey: "fade")
        }

        func addLayer(_ layer: CAShapeLayer) {
            rootView.layer!.addSublayer(layer); burstLayers.append(layer)
        }

        switch tier {
        case 1:
            // ═══════════════════════════════════════════
            //  TIER 1: SIGIL OF LUCIFER
            //  Inverted triangle/V at top, diamond in center,
            //  vertical line with cross at bottom, binding circle
            // ═══════════════════════════════════════════

            let r = radius

            // Binding circle
            let circle = makeShape(color: dimColor, width: 1.0)
            let cp = CGMutablePath()
            cp.addEllipse(in: CGRect(x: -r, y: -r, width: r * 2, height: r * 2))
            circle.path = cp; circle.opacity = 0.4
            addLayer(circle)
            applyBurst(to: circle, drawDur: 0.6, spinRevs: 0, fadeStart: 0.7, opacity: 0.4)

            // The sigil body (one continuous path)
            let sigil = makeShape(color: mainColor, width: 2.0)
            let sp = CGMutablePath()

            // Inverted V at top (the horns)
            let hornW = r * 0.55
            let hornTop = -r * 0.85
            let hornMid = -r * 0.35
            let hornBottom = -r * 0.15
            sp.move(to: CGPoint(x: -hornW, y: hornTop))
            sp.addLine(to: CGPoint(x: 0, y: hornMid))
            sp.addLine(to: CGPoint(x: hornW, y: hornTop))

            // Small horizontal bar across the V
            sp.move(to: CGPoint(x: -hornW * 0.6, y: hornTop + r * 0.2))
            sp.addLine(to: CGPoint(x: hornW * 0.6, y: hornTop + r * 0.2))

            // Diamond in center
            let dw = r * 0.3
            let dh = r * 0.35
            sp.move(to: CGPoint(x: 0, y: hornBottom))
            sp.addLine(to: CGPoint(x: -dw, y: hornBottom + dh * 0.5))
            sp.addLine(to: CGPoint(x: 0, y: hornBottom + dh))
            sp.addLine(to: CGPoint(x: dw, y: hornBottom + dh * 0.5))
            sp.addLine(to: CGPoint(x: 0, y: hornBottom))

            // Vertical line down from diamond
            let lineTop = hornBottom + dh
            let lineBottom = r * 0.75
            sp.move(to: CGPoint(x: 0, y: lineTop))
            sp.addLine(to: CGPoint(x: 0, y: lineBottom))

            // Cross at bottom of line
            let crossW = r * 0.2
            let crossY = r * 0.55
            sp.move(to: CGPoint(x: -crossW, y: crossY))
            sp.addLine(to: CGPoint(x: crossW, y: crossY))

            // Bottom horizontal bar (wider)
            let barY = lineBottom
            sp.move(to: CGPoint(x: -crossW * 1.5, y: barY))
            sp.addLine(to: CGPoint(x: crossW * 1.5, y: barY))

            sigil.path = sp
            addLayer(sigil)

            // Inner inverted triangle connecting to the V
            let innerTri = makeShape(color: altColor, width: 1.2)
            let tp = CGMutablePath()
            addPolygon(to: tp, sides: 3, radius: r * 0.45, center: .zero, rotation: .pi / 2)
            innerTri.path = tp; innerTri.opacity = 0.5
            addLayer(innerTri)

            // Small circles at key vertices
            let keyPts: [CGPoint] = [
                CGPoint(x: -hornW, y: hornTop), CGPoint(x: hornW, y: hornTop),
                CGPoint(x: 0, y: hornMid), CGPoint(x: 0, y: hornBottom),
                CGPoint(x: 0, y: lineBottom), CGPoint(x: -dw, y: hornBottom + dh * 0.5),
                CGPoint(x: dw, y: hornBottom + dh * 0.5),
            ]
            addDots(points: keyPts, color: mainColor, dotR: 3.5)

            // Animations
            applyBurst(to: sigil, drawDur: 1.2, spinRevs: 0, fadeStart: 0.75)
            applyBurst(to: innerTri, drawDelay: 0.4, drawDur: 0.6, spinRevs: -0.5, fadeStart: 0.72, opacity: 0.5)

        case 2:
            // ═══════════════════════════════════════════
            //  TIER 2: METATRON'S CUBE
            //  13 circles (1 center + 6 inner ring + 6 outer ring)
            //  connected by lines forming the cube structure,
            //  with a unicursal hexagram overlay
            // ═══════════════════════════════════════════

            let r = radius

            // The 13 circle centers
            let innerR = r * 0.45
            let outerR = r * 0.9
            var circCenters: [CGPoint] = [.zero] // center circle
            for i in 0..<6 {
                let angle = -.pi / 2 + CGFloat(i) * (.pi / 3)
                circCenters.append(CGPoint(x: innerR * cos(angle), y: innerR * sin(angle)))
            }
            for i in 0..<6 {
                let angle = -.pi / 2 + CGFloat(i) * (.pi / 3)
                circCenters.append(CGPoint(x: outerR * cos(angle), y: outerR * sin(angle)))
            }

            // Draw the 13 circles
            let circleR = r * 0.12
            let circles = makeShape(color: dimColor, width: 0.8)
            let circlesPath = CGMutablePath()
            for c in circCenters {
                circlesPath.addEllipse(in: CGRect(x: c.x - circleR, y: c.y - circleR,
                                                   width: circleR * 2, height: circleR * 2))
            }
            circles.path = circlesPath; circles.opacity = 0.5
            addLayer(circles)

            // Connecting lines (every center to every other center)
            let lines = makeShape(color: faintColor, width: 0.5)
            let linesPath = CGMutablePath()
            for i in 0..<circCenters.count {
                for j in (i + 1)..<circCenters.count {
                    linesPath.move(to: circCenters[i])
                    linesPath.addLine(to: circCenters[j])
                }
            }
            lines.path = linesPath; lines.opacity = 0.3
            addLayer(lines)

            // Outer binding circle
            let outerCirc = makeShape(color: dimColor, width: 1.0)
            let ocp = CGMutablePath()
            ocp.addEllipse(in: CGRect(x: -r, y: -r, width: r * 2, height: r * 2))
            outerCirc.path = ocp; outerCirc.opacity = 0.4
            addLayer(outerCirc)

            // Unicursal hexagram overlay
            let hex = makeShape(color: mainColor, width: 2.0)
            let hexPath = CGMutablePath()
            addUnicursalHexagram(to: hexPath, radius: r * 0.85, center: .zero)
            hex.path = hexPath
            addLayer(hex)

            // Inner Star of David (two triangles)
            let starInner = makeShape(color: altColor, width: 1.2)
            let sip = CGMutablePath()
            addPolygon(to: sip, sides: 3, radius: innerR, center: .zero)
            addPolygon(to: sip, sides: 3, radius: innerR, center: .zero, rotation: .pi / 2)
            starInner.path = sip; starInner.opacity = 0.6
            addLayer(starInner)

            // Center dot (larger, filled)
            addDots(points: [.zero], color: mainColor, dotR: 5, stagger: 0)

            // Vertex dots on outer ring
            let outerPts = (0..<6).map { i -> CGPoint in
                let angle = -.pi / 2 + CGFloat(i) * (.pi / 3)
                return CGPoint(x: outerR * cos(angle), y: outerR * sin(angle))
            }
            addDots(points: outerPts, color: mainColor, dotR: 3)

            // Animations
            applyBurst(to: circles, drawDur: 0.8, spinRevs: 0, fadeStart: 0.72, opacity: 0.5)
            applyBurst(to: lines, drawDelay: 0.2, drawDur: 1.0, spinRevs: 0, fadeStart: 0.68, opacity: 0.3)
            applyBurst(to: outerCirc, drawDelay: 0.1, drawDur: 0.5, spinRevs: 0, fadeStart: 0.72, opacity: 0.4)
            applyBurst(to: hex, drawDelay: 0.3, drawDur: 1.2, spinRevs: 1, fadeStart: 0.72)
            applyBurst(to: starInner, drawDelay: 0.5, drawDur: 0.6, spinRevs: -1, fadeStart: 0.72, opacity: 0.6)

        default:
            // ═══════════════════════════════════════════
            //  TIER 3: FULL SUMMONING CIRCLE
            //  Triple binding ring with rune tick marks,
            //  inverted pentagram, Leviathan cross at center,
            //  Sigil of Lucifer fragments in cardinal positions,
            //  all-seeing eye, 8-pointed chaos star inner layer
            // ═══════════════════════════════════════════

            let r = radius

            // Triple binding circles
            for (ri, op) in [(r, Float(0.5)), (r * 0.88, Float(0.35)), (r * 0.76, Float(0.25))] {
                let ring = makeShape(color: dimColor, width: ri == r ? 1.5 : 0.8)
                let rp = CGMutablePath()
                rp.addEllipse(in: CGRect(x: -ri, y: -ri, width: ri * 2, height: ri * 2))
                ring.path = rp; ring.opacity = op
                addLayer(ring)
                applyFade(to: ring, opacity: op, delay: 0.72)
            }

            // Rune tick marks between outer two rings
            let runes = makeShape(color: dimColor, width: 0.6)
            let runePath = CGMutablePath()
            for i in 0..<36 {
                let angle = CGFloat(i) * (.pi / 18)
                let isLong = i % 9 == 0  // cardinal directions get longer ticks
                let r1 = r * (isLong ? 0.77 : 0.82)
                let r2 = r * 0.87
                runePath.move(to: CGPoint(x: r1 * cos(angle), y: r1 * sin(angle)))
                runePath.addLine(to: CGPoint(x: r2 * cos(angle), y: r2 * sin(angle)))
            }
            runes.path = runePath; runes.opacity = 0.3
            addLayer(runes)
            applyFade(to: runes, opacity: 0.3, delay: 0.7)

            // Inverted pentagram (point-down)
            let penta = makeShape(color: mainColor, width: 2.5)
            let pp = CGMutablePath()
            // Rotate pentagram so point faces down (+ pi to invert)
            let pentaPts: [CGPoint] = (0..<5).map { i in
                let angle = .pi / 2 + CGFloat(i) * (2 * .pi / 5)  // +pi/2 = point down
                return CGPoint(x: r * 0.72 * cos(angle), y: r * 0.72 * sin(angle))
            }
            pp.move(to: pentaPts[0])
            pp.addLine(to: pentaPts[2])
            pp.addLine(to: pentaPts[4])
            pp.addLine(to: pentaPts[1])
            pp.addLine(to: pentaPts[3])
            pp.addLine(to: pentaPts[0])
            penta.path = pp
            addLayer(penta)

            // 8-pointed chaos star (inner, overlapping two squares rotated 45°)
            let chaos = makeShape(color: altColor, width: 1.2)
            let chaosPath = CGMutablePath()
            let chaosR = r * 0.38
            // First square
            addPolygon(to: chaosPath, sides: 4, radius: chaosR, center: .zero, rotation: -.pi / 4)
            // Second square rotated 45°
            addPolygon(to: chaosPath, sides: 4, radius: chaosR, center: .zero, rotation: 0)
            chaos.path = chaosPath; chaos.opacity = 0.6
            addLayer(chaos)

            // Leviathan cross at center (double cross + infinity at bottom)
            let levi = makeShape(color: mainColor, width: 1.8)
            let lp = CGMutablePath()
            let lh = r * 0.3  // half-height of cross
            let lw = r * 0.12 // half-width of arms
            // Vertical line
            lp.move(to: CGPoint(x: 0, y: -lh))
            lp.addLine(to: CGPoint(x: 0, y: lh))
            // Upper crossbar
            lp.move(to: CGPoint(x: -lw, y: -lh * 0.5))
            lp.addLine(to: CGPoint(x: lw, y: -lh * 0.5))
            // Lower crossbar
            lp.move(to: CGPoint(x: -lw * 0.7, y: -lh * 0.1))
            lp.addLine(to: CGPoint(x: lw * 0.7, y: -lh * 0.1))
            // Infinity symbol at bottom (two small arcs)
            let infR = r * 0.08
            let infY = lh + infR
            lp.addArc(center: CGPoint(x: -infR, y: infY), radius: infR,
                       startAngle: 0, endAngle: 2 * .pi, clockwise: false)
            lp.addArc(center: CGPoint(x: infR, y: infY), radius: infR,
                       startAngle: .pi, endAngle: 3 * .pi, clockwise: false)
            levi.path = lp
            addLayer(levi)

            // Sigil fragments at 4 cardinal positions (small V-shapes like Lucifer's horns)
            let frags = makeShape(color: dimColor, width: 1.0)
            let fragPath = CGMutablePath()
            for i in 0..<4 {
                let angle = CGFloat(i) * (.pi / 2)
                let dist = r * 0.58
                let cx = dist * cos(angle)
                let cy = dist * sin(angle)
                let fw: CGFloat = r * 0.06
                let fh: CGFloat = r * 0.08
                // Small inverted V
                fragPath.move(to: CGPoint(x: cx - fw, y: cy - fh))
                fragPath.addLine(to: CGPoint(x: cx, y: cy))
                fragPath.addLine(to: CGPoint(x: cx + fw, y: cy - fh))
                // Small dot below
                fragPath.addEllipse(in: CGRect(x: cx - 1.5, y: cy + fh * 0.3, width: 3, height: 3))
            }
            frags.path = fragPath; frags.opacity = 0.5
            addLayer(frags)

            // All-seeing eye at very center (inside the Leviathan cross area)
            let eye = makeShape(color: mainColor, width: 1.2)
            let ep = CGMutablePath()
            let eyeR = r * 0.06
            // Triangle around the eye
            let triR = r * 0.14
            addPolygon(to: ep, sides: 3, radius: triR, center: CGPoint(x: 0, y: -lh * 0.82))
            // Eye inside triangle
            let eyeY = -lh * 0.82
            ep.addArc(center: CGPoint(x: 0, y: eyeY), radius: eyeR,
                       startAngle: .pi, endAngle: 0, clockwise: false)
            ep.addArc(center: CGPoint(x: 0, y: eyeY), radius: eyeR,
                       startAngle: 0, endAngle: .pi, clockwise: false)
            ep.addEllipse(in: CGRect(x: -eyeR * 0.35, y: eyeY - eyeR * 0.35,
                                      width: eyeR * 0.7, height: eyeR * 0.7))
            eye.path = ep; eye.opacity = 0.8
            addLayer(eye)

            // Vertex dots on pentagram points + chaos star points
            addDots(points: pentaPts, color: mainColor, dotR: 4)
            let chaosPts = (0..<8).map { i -> CGPoint in
                let angle = CGFloat(i) * (.pi / 4) - .pi / 8
                return CGPoint(x: chaosR * cos(angle), y: chaosR * sin(angle))
            }
            addDots(points: chaosPts, color: altColor, dotR: 2.5, stagger: 0.06)

            // Animations
            applyBurst(to: penta, drawDur: 1.2, spinRevs: 1.5, fadeStart: 0.75)
            applyBurst(to: chaos, drawDelay: 0.3, drawDur: 0.7, spinRevs: -2, fadeStart: 0.72, opacity: 0.6)

            // Leviathan cross scales in from center
            let leviScale = CABasicAnimation(keyPath: "transform.scale")
            leviScale.fromValue = 0; leviScale.toValue = 1; leviScale.duration = 0.6
            leviScale.beginTime = 0.5; leviScale.fillMode = .backwards
            let leviFade = fadeAnim(1.0, delay: duration * 0.75, dur: duration * 0.25)
            let lg = CAAnimationGroup(); lg.animations = [leviScale, leviFade]; lg.duration = duration
            lg.isRemovedOnCompletion = false; lg.fillMode = .forwards
            levi.add(lg, forKey: "burst")

            // Eye blinks in
            let eyeScale = CABasicAnimation(keyPath: "transform.scale")
            eyeScale.fromValue = 0; eyeScale.toValue = 1; eyeScale.duration = 0.4
            eyeScale.beginTime = 0.8; eyeScale.fillMode = .backwards
            let eyeFade = fadeAnim(0.8, delay: duration * 0.75, dur: duration * 0.25)
            let eg = CAAnimationGroup(); eg.animations = [eyeScale, eyeFade]; eg.duration = duration
            eg.isRemovedOnCompletion = false; eg.fillMode = .forwards
            eye.add(eg, forKey: "burst")

            applyFade(to: frags, opacity: 0.5, delay: 0.72)
        }

        // Clean up after animation
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + duration + 0.3)
        t.setEventHandler { [weak self] in
            guard let self else { return }
            for l in self.burstLayers { l.removeFromSuperlayer() }
            self.burstLayers.removeAll()
            self.burstTimer = nil
        }
        burstTimer = t
        t.resume()
    }

    // MARK: - Occult Path Helpers

    private func addPolygon(to path: CGMutablePath, sides: Int, radius: CGFloat, center: CGPoint, rotation: CGFloat = -.pi / 2) {
        for i in 0...sides {
            let angle = rotation + CGFloat(i) * (2 * .pi / CGFloat(sides))
            let pt = CGPoint(x: center.x + radius * cos(angle),
                             y: center.y + radius * sin(angle))
            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }
    }

    /// Unicursal hexagram — single continuous stroke (Thelema symbol)
    private func addUnicursalHexagram(to path: CGMutablePath, radius: CGFloat, center: CGPoint) {
        let pts: [CGPoint] = (0..<6).map { i in
            let angle = -.pi / 2 + CGFloat(i) * (.pi / 3)
            return CGPoint(x: center.x + radius * cos(angle),
                           y: center.y + radius * sin(angle))
        }
        let order = [0, 2, 4, 0, 3, 5, 1, 4, 2, 5, 3, 1, 0]
        path.move(to: pts[order[0]])
        for i in 1..<order.count { path.addLine(to: pts[order[i]]) }
    }

    func hide() {
        for l in burstLayers { l.removeFromSuperlayer() }
        burstLayers.removeAll()
        burstTimer?.cancel()
        burstTimer = nil
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
