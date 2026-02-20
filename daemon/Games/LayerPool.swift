import QuartzCore

class LayerPool {
    private var pool: [CALayer] = []

    func dequeue() -> CALayer {
        if let layer = pool.popLast() {
            layer.isHidden = false
            return layer
        }
        return CALayer()
    }

    func enqueue(_ layer: CALayer) {
        layer.removeAllAnimations()
        layer.contents = nil
        layer.sublayers = nil
        layer.isHidden = true
        layer.opacity = 1.0
        layer.transform = CATransform3DIdentity
        layer.backgroundColor = nil
        layer.borderWidth = 0
        layer.cornerRadius = 0
        layer.removeFromSuperlayer()
        pool.append(layer)
    }

    func drain() {
        pool.removeAll()
    }
}
