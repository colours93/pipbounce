import Foundation

/// Central registry of all game instances.
enum Games {
    static let pipong = PiPongGame()
    static let pipong2 = PiPong2Game()
    static let flappy = FlappyGame()
    static let bounce = BounceGame()
    static let invaders = InvadersGame()
    static let frogger = FroggerGame()
    static let runner = RunnerGame()
    static let snake = SnakeGame()
    static let breakout = BreakoutGame()
    static let asteroids = AsteroidsGame()
    static let cursorhunt = CursorHuntGame()
    static let doodlejump = DoodleJumpGame()
    static let pacman = PacManGame()

    static let all: [String: MiniGame] = [
        "pipong": pipong,
        "pipong2": pipong2,
        "flappy": flappy,
        "bounce": bounce,
        "invaders": invaders,
        "frogger": frogger,
        "runner": runner,
        "snake": snake,
        "breakout": breakout,
        "asteroids": asteroids,
        "cursorhunt": cursorhunt,
        "doodlejump": doodlejump,
        "pacman": pacman,
    ]

    /// True if any game is currently active.
    static var anyActive: Bool {
        all.values.contains { $0.active }
    }
}
