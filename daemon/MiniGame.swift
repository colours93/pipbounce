import Cocoa

/// Protocol for PiP mini-games. The daemon discovers a PiP window and hands it
/// to the active game. The game owns the PiP position, border, and overlays
/// until stopped. Implement this to add new games (Breakout, Snake, etc.)
protocol MiniGame: AnyObject {
    /// Whether the game is currently running.
    var active: Bool { get }

    /// The last known bounds of the PiP window (AX coordinates).
    /// The daemon uses this to keep the border synced when glow is on.
    var lastBounds: CGRect { get }

    /// Start the game. The game takes ownership of the PiP window and border.
    func start(screen: CGRect, pip: PipWindowInfo, border: RGBBorder)

    /// Stop the game and release all overlays.
    func stop()
}
