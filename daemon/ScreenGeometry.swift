import Cocoa

func getScreenFrame() -> CGRect {
    if let main = NSScreen.main {
        return CGRect(x: 0, y: 0, width: main.frame.width, height: main.frame.height)
    }
    return CGRect(x: 0, y: 0, width: 1920, height: 1080)
}

/// Returns the screen corner farthest from the mouse, offset by margin and window size.
func getFurthestCorner(from mousePos: CGPoint, windowSize: CGSize, screen: CGRect) -> CGPoint {
    let m = settings.margin
    let corners: [CGPoint] = [
        CGPoint(x: screen.minX + m, y: screen.minY + m),
        CGPoint(x: screen.maxX - windowSize.width - m, y: screen.minY + m),
        CGPoint(x: screen.minX + m, y: screen.maxY - windowSize.height - m),
        CGPoint(x: screen.maxX - windowSize.width - m, y: screen.maxY - windowSize.height - m),
    ]

    var best = corners[3]
    var bestDist: CGFloat = 0

    for corner in corners {
        let cx = corner.x + windowSize.width / 2
        let cy = corner.y + windowSize.height / 2
        let dx = mousePos.x - cx
        let dy = mousePos.y - cy
        let dist = dx * dx + dy * dy
        if dist > bestDist {
            bestDist = dist
            best = corner
        }
    }

    return best
}
