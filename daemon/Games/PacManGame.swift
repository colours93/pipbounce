import Cocoa
import ApplicationServices

let pacman = PacManGame()

class PacManGame: GameBase {

    // Grid
    private let gridCols = 21
    private let gridRows = 21
    private var cellSize: CGFloat = 0

    // Maze: 0=wall, 1=dot, 2=power pellet, 3=empty path, 4=ghost house
    private var maze: [[Int]] = []

    private let mazeTemplate: [[Int]] = [
        [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
        [0,2,1,1,1,1,1,1,1,1,0,1,1,1,1,1,1,1,1,2,0],
        [0,1,0,0,1,0,0,0,0,1,0,1,0,0,0,0,1,0,0,1,0],
        [0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0],
        [0,1,0,1,0,0,1,0,0,0,0,0,0,0,1,0,0,1,0,1,0],
        [0,1,1,1,1,1,1,1,1,1,0,1,1,1,1,1,1,1,1,1,0],
        [0,0,0,1,0,0,1,0,0,3,0,3,0,0,1,0,0,1,0,0,0],
        [0,0,0,1,0,0,1,0,4,4,4,4,4,0,1,0,0,1,0,0,0],
        [3,3,3,1,1,1,1,0,4,4,4,4,4,0,1,1,1,1,3,3,3],
        [0,0,0,1,0,0,1,0,4,4,4,4,4,0,1,0,0,1,0,0,0],
        [0,0,0,1,0,0,1,0,0,0,0,0,0,0,1,0,0,1,0,0,0],
        [0,1,1,1,1,1,1,1,1,1,0,1,1,1,1,1,1,1,1,1,0],
        [0,1,0,1,0,0,1,0,0,0,0,0,0,0,1,0,0,1,0,1,0],
        [0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0],
        [0,1,0,0,1,0,0,0,0,1,0,1,0,0,0,0,1,0,0,1,0],
        [0,1,1,1,1,1,1,1,1,1,0,1,1,1,1,1,1,1,1,1,0],
        [0,0,0,1,0,0,1,0,0,0,0,0,0,0,1,0,0,1,0,0,0],
        [0,1,1,1,1,1,1,1,1,1,0,1,1,1,1,1,1,1,1,1,0],
        [0,1,0,0,1,0,0,0,0,1,0,1,0,0,0,0,1,0,0,1,0],
        [0,2,1,1,1,1,1,1,1,1,0,1,1,1,1,1,1,1,1,2,0],
        [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
    ]

    // Player
    private var playerCol: CGFloat = 10
    private var playerRow: CGFloat = 13
    private var playerDir: Int = 2
    private var nextDir: Int = 2
    private let playerSpeed: CGFloat = 3.2

    // Camera
    private var cameraX: CGFloat = 0
    private var cameraY: CGFloat = 0

    // Ghosts
    private struct Ghost {
        var col: CGFloat
        var row: CGFloat
        var dir: Int
        var layer: CALayer
        var scared: Bool
        var eaten: Bool
        var colorIndex: Int
    }
    private var ghosts: [Ghost] = []
    private let ghostSpeed: CGFloat = 2.8
    private let ghostScaredSpeed: CGFloat = 1.8

    // MARK: - Pixel Art Sprites

    private enum Sprites {
        // 14x14 Red ghost (Blinky)
        static let blinky: CGImage? = GameBase.renderPixelArt([
            [0,0,0,0,0x8B0000,0xCC0000,0xCC0000,0xCC0000,0xCC0000,0x8B0000,0,0,0,0],
            [0,0,0,0xCC0000,0xEE2020,0xFF3333,0xFF3333,0xFF3333,0xFF3333,0xEE2020,0xCC0000,0,0,0],
            [0,0,0xCC0000,0xFF3333,0xFF4444,0xFF5555,0xFF4444,0xFF4444,0xFF5555,0xFF4444,0xFF3333,0xCC0000,0,0],
            [0,0xAA0000,0xFF3333,0xFF5555,0xFF5555,0xFF4444,0xFF3333,0xFF3333,0xFF4444,0xFF5555,0xFF5555,0xFF3333,0xAA0000,0],
            [0,0xAA0000,0xFF3333,0xFFFFFF,0xFFFFFF,0xFF3333,0xFF3333,0xFF3333,0xFFFFFF,0xFFFFFF,0xFF3333,0xFF3333,0xAA0000,0],
            [0x8B0000,0xCC0000,0xFF3333,0xFFFFFF,0x2233AA,0x2233AA,0xFF3333,0xFF3333,0xFFFFFF,0x2233AA,0x2233AA,0xFF3333,0xCC0000,0x8B0000],
            [0x8B0000,0xCC0000,0xFF3333,0xFFFFFF,0x2233AA,0x2233AA,0xFF3333,0xFF3333,0xFFFFFF,0x2233AA,0x2233AA,0xFF3333,0xCC0000,0x8B0000],
            [0x8B0000,0xCC0000,0xFF3333,0xFF3333,0xFF3333,0xFF3333,0xFF3333,0xFF3333,0xFF3333,0xFF3333,0xFF3333,0xFF3333,0xCC0000,0x8B0000],
            [0x8B0000,0xCC0000,0xFF3333,0xFF3333,0xFF3333,0xFF3333,0xFF3333,0xFF3333,0xFF3333,0xFF3333,0xFF3333,0xFF3333,0xCC0000,0x8B0000],
            [0x8B0000,0xCC0000,0xFF3333,0xFF3333,0xFF3333,0xFF3333,0xFF3333,0xFF3333,0xFF3333,0xFF3333,0xFF3333,0xFF3333,0xCC0000,0x8B0000],
            [0x8B0000,0xCC0000,0xFF3333,0xFF3333,0xFF3333,0xFF3333,0xFF3333,0xFF3333,0xFF3333,0xFF3333,0xFF3333,0xFF3333,0xCC0000,0x8B0000],
            [0x8B0000,0xCC0000,0xFF3333,0xFF3333,0xCC0000,0xFF3333,0xFF3333,0xFF3333,0xFF3333,0xCC0000,0xFF3333,0xFF3333,0xCC0000,0x8B0000],
            [0x8B0000,0xCC0000,0xFF3333,0xAA0000,0,0xAA0000,0xFF3333,0xFF3333,0xAA0000,0,0xAA0000,0xFF3333,0xCC0000,0x8B0000],
            [0x8B0000,0xAA0000,0,0,0,0,0xAA0000,0xAA0000,0,0,0,0,0xAA0000,0x8B0000],
        ])

        // 14x14 Pink ghost (Pinky)
        static let pinky: CGImage? = GameBase.renderPixelArt([
            [0,0,0,0,0x8B2252,0xCC66AA,0xCC66AA,0xCC66AA,0xCC66AA,0x8B2252,0,0,0,0],
            [0,0,0,0xCC66AA,0xEE88CC,0xFF99DD,0xFF99DD,0xFF99DD,0xFF99DD,0xEE88CC,0xCC66AA,0,0,0],
            [0,0,0xCC66AA,0xFF99DD,0xFFAAEE,0xFFBBEE,0xFFAAEE,0xFFAAEE,0xFFBBEE,0xFFAAEE,0xFF99DD,0xCC66AA,0,0],
            [0,0xAA4488,0xFF99DD,0xFFBBEE,0xFFBBEE,0xFFAAEE,0xFF99DD,0xFF99DD,0xFFAAEE,0xFFBBEE,0xFFBBEE,0xFF99DD,0xAA4488,0],
            [0,0xAA4488,0xFF99DD,0xFFFFFF,0xFFFFFF,0xFF99DD,0xFF99DD,0xFF99DD,0xFFFFFF,0xFFFFFF,0xFF99DD,0xFF99DD,0xAA4488,0],
            [0x8B2252,0xCC66AA,0xFF99DD,0xFFFFFF,0x2233AA,0x2233AA,0xFF99DD,0xFF99DD,0xFFFFFF,0x2233AA,0x2233AA,0xFF99DD,0xCC66AA,0x8B2252],
            [0x8B2252,0xCC66AA,0xFF99DD,0xFFFFFF,0x2233AA,0x2233AA,0xFF99DD,0xFF99DD,0xFFFFFF,0x2233AA,0x2233AA,0xFF99DD,0xCC66AA,0x8B2252],
            [0x8B2252,0xCC66AA,0xFF99DD,0xFF99DD,0xFF99DD,0xFF99DD,0xFF99DD,0xFF99DD,0xFF99DD,0xFF99DD,0xFF99DD,0xFF99DD,0xCC66AA,0x8B2252],
            [0x8B2252,0xCC66AA,0xFF99DD,0xFF99DD,0xFF99DD,0xFF99DD,0xFF99DD,0xFF99DD,0xFF99DD,0xFF99DD,0xFF99DD,0xFF99DD,0xCC66AA,0x8B2252],
            [0x8B2252,0xCC66AA,0xFF99DD,0xFF99DD,0xFF99DD,0xFF99DD,0xFF99DD,0xFF99DD,0xFF99DD,0xFF99DD,0xFF99DD,0xFF99DD,0xCC66AA,0x8B2252],
            [0x8B2252,0xCC66AA,0xFF99DD,0xFF99DD,0xFF99DD,0xFF99DD,0xFF99DD,0xFF99DD,0xFF99DD,0xFF99DD,0xFF99DD,0xFF99DD,0xCC66AA,0x8B2252],
            [0x8B2252,0xCC66AA,0xFF99DD,0xFF99DD,0xCC66AA,0xFF99DD,0xFF99DD,0xFF99DD,0xFF99DD,0xCC66AA,0xFF99DD,0xFF99DD,0xCC66AA,0x8B2252],
            [0x8B2252,0xCC66AA,0xFF99DD,0xAA4488,0,0xAA4488,0xFF99DD,0xFF99DD,0xAA4488,0,0xAA4488,0xFF99DD,0xCC66AA,0x8B2252],
            [0x8B2252,0xAA4488,0,0,0,0,0xAA4488,0xAA4488,0,0,0,0,0xAA4488,0x8B2252],
        ])

        // 14x14 Cyan ghost (Inky)
        static let inky: CGImage? = GameBase.renderPixelArt([
            [0,0,0,0,0x006666,0x009999,0x009999,0x009999,0x009999,0x006666,0,0,0,0],
            [0,0,0,0x009999,0x00BBBB,0x00DDDD,0x00DDDD,0x00DDDD,0x00DDDD,0x00BBBB,0x009999,0,0,0],
            [0,0,0x009999,0x00DDDD,0x00EEEE,0x44FFFF,0x00EEEE,0x00EEEE,0x44FFFF,0x00EEEE,0x00DDDD,0x009999,0,0],
            [0,0x007777,0x00DDDD,0x44FFFF,0x44FFFF,0x00EEEE,0x00DDDD,0x00DDDD,0x00EEEE,0x44FFFF,0x44FFFF,0x00DDDD,0x007777,0],
            [0,0x007777,0x00DDDD,0xFFFFFF,0xFFFFFF,0x00DDDD,0x00DDDD,0x00DDDD,0xFFFFFF,0xFFFFFF,0x00DDDD,0x00DDDD,0x007777,0],
            [0x006666,0x009999,0x00DDDD,0xFFFFFF,0x2233AA,0x2233AA,0x00DDDD,0x00DDDD,0xFFFFFF,0x2233AA,0x2233AA,0x00DDDD,0x009999,0x006666],
            [0x006666,0x009999,0x00DDDD,0xFFFFFF,0x2233AA,0x2233AA,0x00DDDD,0x00DDDD,0xFFFFFF,0x2233AA,0x2233AA,0x00DDDD,0x009999,0x006666],
            [0x006666,0x009999,0x00DDDD,0x00DDDD,0x00DDDD,0x00DDDD,0x00DDDD,0x00DDDD,0x00DDDD,0x00DDDD,0x00DDDD,0x00DDDD,0x009999,0x006666],
            [0x006666,0x009999,0x00DDDD,0x00DDDD,0x00DDDD,0x00DDDD,0x00DDDD,0x00DDDD,0x00DDDD,0x00DDDD,0x00DDDD,0x00DDDD,0x009999,0x006666],
            [0x006666,0x009999,0x00DDDD,0x00DDDD,0x00DDDD,0x00DDDD,0x00DDDD,0x00DDDD,0x00DDDD,0x00DDDD,0x00DDDD,0x00DDDD,0x009999,0x006666],
            [0x006666,0x009999,0x00DDDD,0x00DDDD,0x00DDDD,0x00DDDD,0x00DDDD,0x00DDDD,0x00DDDD,0x00DDDD,0x00DDDD,0x00DDDD,0x009999,0x006666],
            [0x006666,0x009999,0x00DDDD,0x00DDDD,0x009999,0x00DDDD,0x00DDDD,0x00DDDD,0x00DDDD,0x009999,0x00DDDD,0x00DDDD,0x009999,0x006666],
            [0x006666,0x009999,0x00DDDD,0x007777,0,0x007777,0x00DDDD,0x00DDDD,0x007777,0,0x007777,0x00DDDD,0x009999,0x006666],
            [0x006666,0x007777,0,0,0,0,0x007777,0x007777,0,0,0,0,0x007777,0x006666],
        ])

        // 14x14 Orange ghost (Clyde)
        static let clyde: CGImage? = GameBase.renderPixelArt([
            [0,0,0,0,0x8B4500,0xCC7700,0xCC7700,0xCC7700,0xCC7700,0x8B4500,0,0,0,0],
            [0,0,0,0xCC7700,0xEE9922,0xFFAA33,0xFFAA33,0xFFAA33,0xFFAA33,0xEE9922,0xCC7700,0,0,0],
            [0,0,0xCC7700,0xFFAA33,0xFFBB55,0xFFCC66,0xFFBB55,0xFFBB55,0xFFCC66,0xFFBB55,0xFFAA33,0xCC7700,0,0],
            [0,0xAA5500,0xFFAA33,0xFFCC66,0xFFCC66,0xFFBB55,0xFFAA33,0xFFAA33,0xFFBB55,0xFFCC66,0xFFCC66,0xFFAA33,0xAA5500,0],
            [0,0xAA5500,0xFFAA33,0xFFFFFF,0xFFFFFF,0xFFAA33,0xFFAA33,0xFFAA33,0xFFFFFF,0xFFFFFF,0xFFAA33,0xFFAA33,0xAA5500,0],
            [0x8B4500,0xCC7700,0xFFAA33,0xFFFFFF,0x2233AA,0x2233AA,0xFFAA33,0xFFAA33,0xFFFFFF,0x2233AA,0x2233AA,0xFFAA33,0xCC7700,0x8B4500],
            [0x8B4500,0xCC7700,0xFFAA33,0xFFFFFF,0x2233AA,0x2233AA,0xFFAA33,0xFFAA33,0xFFFFFF,0x2233AA,0x2233AA,0xFFAA33,0xCC7700,0x8B4500],
            [0x8B4500,0xCC7700,0xFFAA33,0xFFAA33,0xFFAA33,0xFFAA33,0xFFAA33,0xFFAA33,0xFFAA33,0xFFAA33,0xFFAA33,0xFFAA33,0xCC7700,0x8B4500],
            [0x8B4500,0xCC7700,0xFFAA33,0xFFAA33,0xFFAA33,0xFFAA33,0xFFAA33,0xFFAA33,0xFFAA33,0xFFAA33,0xFFAA33,0xFFAA33,0xCC7700,0x8B4500],
            [0x8B4500,0xCC7700,0xFFAA33,0xFFAA33,0xFFAA33,0xFFAA33,0xFFAA33,0xFFAA33,0xFFAA33,0xFFAA33,0xFFAA33,0xFFAA33,0xCC7700,0x8B4500],
            [0x8B4500,0xCC7700,0xFFAA33,0xFFAA33,0xFFAA33,0xFFAA33,0xFFAA33,0xFFAA33,0xFFAA33,0xFFAA33,0xFFAA33,0xFFAA33,0xCC7700,0x8B4500],
            [0x8B4500,0xCC7700,0xFFAA33,0xFFAA33,0xCC7700,0xFFAA33,0xFFAA33,0xFFAA33,0xFFAA33,0xCC7700,0xFFAA33,0xFFAA33,0xCC7700,0x8B4500],
            [0x8B4500,0xCC7700,0xFFAA33,0xAA5500,0,0xAA5500,0xFFAA33,0xFFAA33,0xAA5500,0,0xAA5500,0xFFAA33,0xCC7700,0x8B4500],
            [0x8B4500,0xAA5500,0,0,0,0,0xAA5500,0xAA5500,0,0,0,0,0xAA5500,0x8B4500],
        ])

        // 14x14 Scared ghost (blue body, white zigzag mouth, dot eyes)
        static let scared: CGImage? = GameBase.renderPixelArt([
            [0,0,0,0,0x000066,0x1111AA,0x1111AA,0x1111AA,0x1111AA,0x000066,0,0,0,0],
            [0,0,0,0x1111AA,0x2222CC,0x3333DD,0x3333DD,0x3333DD,0x3333DD,0x2222CC,0x1111AA,0,0,0],
            [0,0,0x1111AA,0x3333DD,0x4444EE,0x5555FF,0x4444EE,0x4444EE,0x5555FF,0x4444EE,0x3333DD,0x1111AA,0,0],
            [0,0x000088,0x3333DD,0x5555FF,0x5555FF,0x4444EE,0x3333DD,0x3333DD,0x4444EE,0x5555FF,0x5555FF,0x3333DD,0x000088,0],
            [0,0x000088,0x3333DD,0x3333DD,0xFFDDCC,0xFFDDCC,0x3333DD,0x3333DD,0xFFDDCC,0xFFDDCC,0x3333DD,0x3333DD,0x000088,0],
            [0x000066,0x1111AA,0x3333DD,0x3333DD,0xFFDDCC,0xFFDDCC,0x3333DD,0x3333DD,0xFFDDCC,0xFFDDCC,0x3333DD,0x3333DD,0x1111AA,0x000066],
            [0x000066,0x1111AA,0x3333DD,0x3333DD,0x3333DD,0x3333DD,0x3333DD,0x3333DD,0x3333DD,0x3333DD,0x3333DD,0x3333DD,0x1111AA,0x000066],
            [0x000066,0x1111AA,0x3333DD,0x3333DD,0x3333DD,0x3333DD,0x3333DD,0x3333DD,0x3333DD,0x3333DD,0x3333DD,0x3333DD,0x1111AA,0x000066],
            [0x000066,0x1111AA,0x3333DD,0xFFDDCC,0x3333DD,0xFFDDCC,0x3333DD,0xFFDDCC,0x3333DD,0xFFDDCC,0x3333DD,0xFFDDCC,0x1111AA,0x000066],
            [0x000066,0x1111AA,0xFFDDCC,0x3333DD,0xFFDDCC,0x3333DD,0xFFDDCC,0x3333DD,0xFFDDCC,0x3333DD,0xFFDDCC,0x3333DD,0x1111AA,0x000066],
            [0x000066,0x1111AA,0x3333DD,0x3333DD,0x3333DD,0x3333DD,0x3333DD,0x3333DD,0x3333DD,0x3333DD,0x3333DD,0x3333DD,0x1111AA,0x000066],
            [0x000066,0x1111AA,0x3333DD,0x3333DD,0x1111AA,0x3333DD,0x3333DD,0x3333DD,0x3333DD,0x1111AA,0x3333DD,0x3333DD,0x1111AA,0x000066],
            [0x000066,0x1111AA,0x3333DD,0x000088,0,0x000088,0x3333DD,0x3333DD,0x000088,0,0x000088,0x3333DD,0x1111AA,0x000066],
            [0x000066,0x000088,0,0,0,0,0x000088,0x000088,0,0,0,0,0x000088,0x000066],
        ])

        // 14x14 Scared flash (white body variant)
        static let scaredFlash: CGImage? = GameBase.renderPixelArt([
            [0,0,0,0,0xAAAA99,0xDDDDCC,0xDDDDCC,0xDDDDCC,0xDDDDCC,0xAAAA99,0,0,0,0],
            [0,0,0,0xDDDDCC,0xEEEEDD,0xFFFFEE,0xFFFFEE,0xFFFFEE,0xFFFFEE,0xEEEEDD,0xDDDDCC,0,0,0],
            [0,0,0xDDDDCC,0xFFFFEE,0xFFFFFF,0xFFFFFF,0xFFFFFF,0xFFFFFF,0xFFFFFF,0xFFFFFF,0xFFFFEE,0xDDDDCC,0,0],
            [0,0xBBBBAA,0xFFFFEE,0xFFFFFF,0xFFFFFF,0xFFFFFF,0xFFFFEE,0xFFFFEE,0xFFFFFF,0xFFFFFF,0xFFFFFF,0xFFFFEE,0xBBBBAA,0],
            [0,0xBBBBAA,0xFFFFEE,0xFFFFEE,0xCC3333,0xCC3333,0xFFFFEE,0xFFFFEE,0xCC3333,0xCC3333,0xFFFFEE,0xFFFFEE,0xBBBBAA,0],
            [0xAAAA99,0xDDDDCC,0xFFFFEE,0xFFFFEE,0xCC3333,0xCC3333,0xFFFFEE,0xFFFFEE,0xCC3333,0xCC3333,0xFFFFEE,0xFFFFEE,0xDDDDCC,0xAAAA99],
            [0xAAAA99,0xDDDDCC,0xFFFFEE,0xFFFFEE,0xFFFFEE,0xFFFFEE,0xFFFFEE,0xFFFFEE,0xFFFFEE,0xFFFFEE,0xFFFFEE,0xFFFFEE,0xDDDDCC,0xAAAA99],
            [0xAAAA99,0xDDDDCC,0xFFFFEE,0xFFFFEE,0xFFFFEE,0xFFFFEE,0xFFFFEE,0xFFFFEE,0xFFFFEE,0xFFFFEE,0xFFFFEE,0xFFFFEE,0xDDDDCC,0xAAAA99],
            [0xAAAA99,0xDDDDCC,0xFFFFEE,0xCC3333,0xFFFFEE,0xCC3333,0xFFFFEE,0xCC3333,0xFFFFEE,0xCC3333,0xFFFFEE,0xCC3333,0xDDDDCC,0xAAAA99],
            [0xAAAA99,0xDDDDCC,0xCC3333,0xFFFFEE,0xCC3333,0xFFFFEE,0xCC3333,0xFFFFEE,0xCC3333,0xFFFFEE,0xCC3333,0xFFFFEE,0xDDDDCC,0xAAAA99],
            [0xAAAA99,0xDDDDCC,0xFFFFEE,0xFFFFEE,0xFFFFEE,0xFFFFEE,0xFFFFEE,0xFFFFEE,0xFFFFEE,0xFFFFEE,0xFFFFEE,0xFFFFEE,0xDDDDCC,0xAAAA99],
            [0xAAAA99,0xDDDDCC,0xFFFFEE,0xFFFFEE,0xDDDDCC,0xFFFFEE,0xFFFFEE,0xFFFFEE,0xFFFFEE,0xDDDDCC,0xFFFFEE,0xFFFFEE,0xDDDDCC,0xAAAA99],
            [0xAAAA99,0xDDDDCC,0xFFFFEE,0xBBBBAA,0,0xBBBBAA,0xFFFFEE,0xFFFFEE,0xBBBBAA,0,0xBBBBAA,0xFFFFEE,0xDDDDCC,0xAAAA99],
            [0xAAAA99,0xBBBBAA,0,0,0,0,0xBBBBAA,0xBBBBAA,0,0,0,0,0xBBBBAA,0xAAAA99],
        ])

        // 14x14 Eaten ghost (just eyes on transparent background)
        static let eaten: CGImage? = GameBase.renderPixelArt([
            [0,0,0,0,0,0,0,0,0,0,0,0,0,0],
            [0,0,0,0,0,0,0,0,0,0,0,0,0,0],
            [0,0,0,0,0,0,0,0,0,0,0,0,0,0],
            [0,0,0,0xFFFFFF,0xFFFFFF,0xFFFFFF,0,0,0xFFFFFF,0xFFFFFF,0xFFFFFF,0,0,0],
            [0,0,0xFFFFFF,0xFFFFFF,0xFFFFFF,0xFFFFFF,0,0xFFFFFF,0xFFFFFF,0xFFFFFF,0xFFFFFF,0,0,0],
            [0,0,0xFFFFFF,0xFFFFFF,0x2233AA,0x2233AA,0,0xFFFFFF,0xFFFFFF,0x2233AA,0x2233AA,0,0,0],
            [0,0,0xFFFFFF,0xFFFFFF,0x2233AA,0x2233AA,0,0xFFFFFF,0xFFFFFF,0x2233AA,0x2233AA,0,0,0],
            [0,0,0,0xFFFFFF,0xFFFFFF,0xFFFFFF,0,0,0xFFFFFF,0xFFFFFF,0xFFFFFF,0,0,0],
            [0,0,0,0,0,0,0,0,0,0,0,0,0,0],
            [0,0,0,0,0,0,0,0,0,0,0,0,0,0],
            [0,0,0,0,0,0,0,0,0,0,0,0,0,0],
            [0,0,0,0,0,0,0,0,0,0,0,0,0,0],
            [0,0,0,0,0,0,0,0,0,0,0,0,0,0],
            [0,0,0,0,0,0,0,0,0,0,0,0,0,0],
        ])

        static let allGhosts: [CGImage?] = [blinky, pinky, inky, clyde]
    }

    // Power pellet
    private var powered = false
    private var powerTimer: CGFloat = 0
    private let powerDuration: CGFloat = 6.0
    private var ghostsEatenThisPower = 0

    // Lives & dots
    private var lives = 3
    private var dotsRemaining = 0
    private var gameWon = false

    // Overlay
    private var overlayWindow: NSWindow?
    private var overlayLayer: CALayer?
    private var mazeContainer: CALayer?
    private var glassWindow: NSWindow?
    private var glassMaskLayer: CALayer?  // container that scrolls with maze
    private var wallLayers: [CALayer] = []
    private var dotLayers: [[CALayer?]] = []

    private var savedScreen = CGRect.zero
    private let tunnelRow = 8

    // Direction deltas: right, down, left, up
    private let dirDelta: [(dc: Int, dr: Int)] = [(1, 0), (0, 1), (-1, 0), (0, -1)]

    // MARK: - GameBase Hooks

    override func onStart(screen: CGRect, pip: PipWindowInfo) {
        timerIntervalMs = 8

        lives = 3
        gameWon = false
        powered = false
        powerTimer = 0
        ghostsEatenThisPower = 0
        ghosts = []
        wallLayers = []
        dotLayers = []
        savedScreen = screen

        // Cell slightly larger than PiP's biggest dimension so it fits with some breathing room
        cellSize = max(cachedPipSize.width, cachedPipSize.height) * 0.55

        maze = mazeTemplate
        dotsRemaining = 0
        for r in 0..<gridRows {
            for c in 0..<gridCols {
                if maze[r][c] == 1 || maze[r][c] == 2 { dotsRemaining += 1 }
            }
        }

        playerCol = 10.0
        playerRow = 13.0
        playerDir = 2
        nextDir = 2

        let playerWorldX = playerCol * cellSize + cellSize / 2
        let playerWorldY = playerRow * cellSize + cellSize / 2
        cameraX = playerWorldX - screen.width / 2
        cameraY = playerWorldY - screen.height / 2

        if Thread.isMainThread {
            createOverlays(screen: screen)
        } else {
            DispatchQueue.main.sync { self.createOverlays(screen: screen) }
        }

        print("Pac-Man started (cellSize=\(Int(cellSize)) pip=\(Int(cachedPipSize.width))x\(Int(cachedPipSize.height)) maze=\(Int(cellSize * CGFloat(gridCols)))x\(Int(cellSize * CGFloat(gridRows))))")
    }

    override func onStop() {
        let ow = overlayWindow
        let cleanup = { ow?.orderOut(nil) }
        if Thread.isMainThread { cleanup() }
        else { DispatchQueue.main.async { cleanup() } }
        overlayWindow = nil
        overlayLayer = nil
        mazeContainer = nil
        glassWindow?.orderOut(nil)
        glassWindow = nil
        glassMaskLayer = nil
        ghosts = []
        wallLayers = []
        dotLayers = []
        print("Pac-Man stopped")
    }

    // MARK: - Overlay Creation

    private func createOverlays(screen: CGRect) {
        // Fully transparent viewport window — only neon lines and game elements visible
        let ow = NSWindow(contentRect: NSRect(x: screen.minX, y: 0, width: screen.width, height: screenH),
                          styleMask: .borderless, backing: .buffered, defer: false)
        ow.isOpaque = false
        ow.backgroundColor = .clear
        ow.level = .floating
        ow.ignoresMouseEvents = true
        ow.hasShadow = false
        ow.collectionBehavior = [.canJoinAllSpaces, .stationary, .transient, .ignoresCycle]
        ow.contentView!.wantsLayer = true

        let rootLayer = ow.contentView!.layer!
        rootLayer.masksToBounds = true
        overlayLayer = rootLayer

        let mazeW = cellSize * CGFloat(gridCols)
        let mazeH = cellSize * CGFloat(gridRows)

        let container = CALayer()
        container.frame = CGRect(x: 0, y: 0, width: mazeW, height: mazeH)
        rootLayer.addSublayer(container)
        mazeContainer = container

        // --- Glass blur walls (NSVisualEffectView with scrolling mask) ---
        let gw = NSWindow(contentRect: NSRect(x: screen.minX, y: 0, width: screen.width, height: screenH),
                          styleMask: .borderless, backing: .buffered, defer: false)
        gw.isOpaque = false
        gw.backgroundColor = .clear
        gw.level = .floating
        gw.ignoresMouseEvents = true
        gw.hasShadow = false
        gw.collectionBehavior = [.canJoinAllSpaces, .stationary, .transient, .ignoresCycle]

        // Full-window behind-window blur — real macOS glass
        let vibrancy = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: screen.width, height: screenH))
        vibrancy.material = .hudWindow
        vibrancy.blendingMode = .behindWindow
        vibrancy.state = .active
        vibrancy.wantsLayer = true
        gw.contentView = vibrancy

        // Scrolling mask — only wall cells show the glass blur
        let maskRoot = CALayer()
        maskRoot.frame = CGRect(x: 0, y: 0, width: screen.width, height: CGFloat(screenH))
        let maskContainer = CALayer()
        maskContainer.frame = CGRect(x: 0, y: 0, width: mazeW, height: mazeH)

        // Build merged wall path with smooth rounded corners — no grid seams
        let wallPath = CGMutablePath()
        let cornerR: CGFloat = cellSize * 0.18
        for r in 0..<gridRows {
            for c in 0..<gridCols {
                guard maze[r][c] == 0 else { continue }
                let cx = CGFloat(c) * cellSize
                let nsY = mazeH - CGFloat(r + 1) * cellSize
                wallPath.addRoundedRect(in: CGRect(x: cx, y: nsY, width: cellSize, height: cellSize),
                                        cornerWidth: cornerR, cornerHeight: cornerR)
            }
        }
        let maskShape = CAShapeLayer()
        maskShape.path = wallPath
        maskShape.fillColor = NSColor.white.cgColor
        maskContainer.mask = maskShape
        maskContainer.backgroundColor = NSColor.white.cgColor

        maskRoot.addSublayer(maskContainer)
        vibrancy.layer!.mask = maskRoot
        glassMaskLayer = maskContainer

        gw.orderFrontRegardless()
        glassWindow = gw

        // Order game overlay above glass window
        ow.orderFrontRegardless()

        // Dots and power pellets
        dotLayers = Array(repeating: Array(repeating: nil, count: gridCols), count: gridRows)
        let dotColor = NSColor(red: 1.0, green: 0.85, blue: 0.5, alpha: 1.0).cgColor
        for r in 0..<gridRows {
            for c in 0..<gridCols {
                let nsY = mazeH - CGFloat(r + 1) * cellSize
                if maze[r][c] == 1 {
                    let layer = CALayer()
                    let dotS = cellSize * 0.15
                    layer.frame = CGRect(x: CGFloat(c) * cellSize + (cellSize - dotS) / 2,
                                         y: nsY + (cellSize - dotS) / 2,
                                         width: dotS, height: dotS)
                    layer.backgroundColor = dotColor
                    layer.cornerRadius = dotS / 2
                    container.addSublayer(layer)
                    dotLayers[r][c] = layer
                } else if maze[r][c] == 2 {
                    let layer = CALayer()
                    let pelletS = cellSize * 0.4
                    layer.frame = CGRect(x: CGFloat(c) * cellSize + (cellSize - pelletS) / 2,
                                         y: nsY + (cellSize - pelletS) / 2,
                                         width: pelletS, height: pelletS)
                    layer.backgroundColor = dotColor
                    layer.cornerRadius = pelletS / 2
                    // Pulsing glow on power pellets
                    layer.shadowColor = dotColor
                    layer.shadowOffset = .zero
                    layer.shadowRadius = 4
                    layer.shadowOpacity = 0.5
                    let radiusAnim = CABasicAnimation(keyPath: "shadowRadius")
                    radiusAnim.fromValue = 4
                    radiusAnim.toValue = 10
                    radiusAnim.duration = 0.8
                    radiusAnim.autoreverses = true
                    radiusAnim.repeatCount = .infinity
                    layer.add(radiusAnim, forKey: "pelletGlowRadius")
                    let opacityAnim = CABasicAnimation(keyPath: "shadowOpacity")
                    opacityAnim.fromValue = 0.5
                    opacityAnim.toValue = 1.0
                    opacityAnim.duration = 0.8
                    opacityAnim.autoreverses = true
                    opacityAnim.repeatCount = .infinity
                    layer.add(opacityAnim, forKey: "pelletGlowOpacity")
                    container.addSublayer(layer)
                    dotLayers[r][c] = layer
                }
            }
        }

        // Ghosts
        let ghostStartCols: [CGFloat] = [9, 10, 11, 10]
        let ghostStartRows: [CGFloat] = [8, 8, 8, 7]
        for i in 0..<4 {
            let gSize = cellSize * 0.8

            let layer = CALayer()
            layer.bounds = CGRect(origin: .zero, size: CGSize(width: gSize, height: gSize))
            layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            layer.contents = Sprites.allGhosts[i]
            layer.magnificationFilter = .nearest
            layer.minificationFilter = .nearest
            container.addSublayer(layer)

            ghosts.append(Ghost(col: ghostStartCols[i], row: ghostStartRows[i],
                                dir: Int.random(in: 0...3),
                                layer: layer,
                                scared: false, eaten: false,
                                colorIndex: i))
        }

        ow.orderFrontRegardless()
        overlayWindow = ow

        // Score overlay
        createScoreOverlay(screen: screen, width: 240)
        scoreLabel?.font = NSFont.monospacedSystemFont(ofSize: 20, weight: .bold)
        scoreLabel?.stringValue = "\(livesString())  0"
    }

    private func livesString() -> String {
        String(repeating: "C", count: lives)
    }

    private func updateScoreDisplay() {
        scoreLabel?.stringValue = "\(livesString())  \(score)"
    }

    // MARK: - Grid helpers

    private func isWalkable(_ col: Int, _ row: Int) -> Bool {
        guard col >= 0, col < gridCols, row >= 0, row < gridRows else {
            if row == tunnelRow && (col < 0 || col >= gridCols) { return true }
            return false
        }
        return maze[row][col] != 0
    }

    private func gridToWorld(col: CGFloat, row: CGFloat) -> CGPoint {
        CGPoint(x: col * cellSize + cellSize / 2,
                y: row * cellSize + cellSize / 2)
    }

    private func worldToScreen(worldX: CGFloat, worldY: CGFloat) -> CGPoint {
        let screenX = worldX - cameraX + savedScreen.minX
        let screenY = worldY - cameraY + savedScreen.minY
        return CGPoint(x: screenX, y: screenY)
    }

    // MARK: - Game Loop

    override func gameTick() {
        guard active, let _ = cachedAXWindow else { return }

        let screen = getScreenFrame()
        savedScreen = screen
        let dt = deltaTime()

        refreshPipSize()
        let size = cachedPipSize

        if gameOver || gameWon {
            let now = mach_absolute_time()
            if machToSeconds(now - gameEndMach) > gameOverDelay { stop() }
            return
        }

        // Input
        guard let mousePos = mousePosition() else { return }

        let playerWorld = gridToWorld(col: playerCol, row: playerRow)
        let playerScreen = worldToScreen(worldX: playerWorld.x, worldY: playerWorld.y)

        let dx = mousePos.x - playerScreen.x
        let dy = mousePos.y - playerScreen.y

        if abs(dx) > abs(dy) {
            nextDir = dx > 0 ? 0 : 2
        } else {
            nextDir = dy > 0 ? 1 : 3
        }

        // Move player
        movePlayer(dt: dt)

        // Collect dots
        let pCol = Int(round(playerCol))
        let pRow = Int(round(playerRow))
        if pCol >= 0, pCol < gridCols, pRow >= 0, pRow < gridRows {
            let cell = maze[pRow][pCol]
            if cell == 1 {
                maze[pRow][pCol] = 3
                dotsRemaining -= 1
                score += 10
                dotLayers[pRow][pCol]?.removeFromSuperlayer()
                dotLayers[pRow][pCol] = nil
                emitDotParticles(atCol: pCol, row: pRow)
                updateScoreDisplay()
            } else if cell == 2 {
                maze[pRow][pCol] = 3
                dotsRemaining -= 1
                score += 50
                dotLayers[pRow][pCol]?.removeFromSuperlayer()
                dotLayers[pRow][pCol] = nil
                emitDotParticles(atCol: pCol, row: pRow)
                powered = true
                powerTimer = powerDuration
                ghostsEatenThisPower = 0
                for i in 0..<ghosts.count {
                    if !ghosts[i].eaten { ghosts[i].scared = true }
                }
                updateScoreDisplay()
            }
        }

        if dotsRemaining <= 0 {
            gameWon = true
            gameEndMach = mach_absolute_time()
            scoreLabel?.stringValue = "YOU WIN  \(score)"
        }

        // Power timer
        if powered {
            powerTimer -= dt
            if powerTimer <= 0 {
                powered = false
                for i in 0..<ghosts.count { ghosts[i].scared = false }
            }
        }

        // Move ghosts
        for i in 0..<ghosts.count { moveGhost(index: i, dt: dt) }

        // Ghost collision
        let now = mach_absolute_time()
        for i in 0..<ghosts.count {
            guard !ghosts[i].eaten else { continue }
            let dist = hypot(ghosts[i].col - playerCol, ghosts[i].row - playerRow)
            if dist < 0.7 {
                if ghosts[i].scared {
                    ghosts[i].eaten = true
                    ghostsEatenThisPower += 1
                    score += 200 * ghostsEatenThisPower
                    updateScoreDisplay()
                } else {
                    hitPlayer(now: now)
                    if gameOver { return }
                }
            }
        }

        // Smooth camera follow
        let targetCamX = playerWorld.x - screen.width / 2
        let targetCamY = playerWorld.y - screen.height / 2
        let camLerp: CGFloat = 0.15
        cameraX += (targetCamX - cameraX) * camLerp
        cameraY += (targetCamY - cameraY) * camLerp

        let mazeW = cellSize * CGFloat(gridCols)
        let mazeH = cellSize * CGFloat(gridRows)
        cameraX = max(0, min(cameraX, mazeW - screen.width))
        cameraY = max(0, min(cameraY, mazeH - screen.height))

        // Position PiP
        let pipScreenPos = worldToScreen(worldX: playerWorld.x - size.width / 2,
                                          worldY: playerWorld.y - size.height / 2)
        if !movePip(to: pipScreenPos) { return }

        let bounds = CGRect(origin: pipScreenPos, size: size)

        // Update visuals
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let containerNSX = -cameraX + screen.minX
        let containerNSY = -(mazeH - screenH - cameraY)
        let containerOrigin = CGPoint(x: containerNSX, y: containerNSY)
        mazeContainer?.frame.origin = containerOrigin
        glassMaskLayer?.frame.origin = containerOrigin

        let mazeH_f = mazeH
        for i in 0..<ghosts.count {
            let g = ghosts[i]
            let gWorld = gridToWorld(col: g.col, row: g.row)
            let nsX = gWorld.x
            let nsY = mazeH_f - gWorld.y
            g.layer.position = CGPoint(x: nsX, y: nsY)

            if g.eaten {
                g.layer.opacity = 1.0
                g.layer.contents = Sprites.eaten
            } else if g.scared {
                g.layer.opacity = 1.0
                let flash = powered && powerTimer < 2.0 && Int(powerTimer * 5) % 2 == 0
                g.layer.contents = flash ? Sprites.scaredFlash : Sprites.scared
            } else {
                g.layer.opacity = 1.0
                g.layer.contents = Sprites.allGhosts[g.colorIndex]
            }
        }

        syncBorder(around: bounds)

        CATransaction.commit()
    }

    // MARK: - Movement

    private func movePlayer(dt: CGFloat) {
        let speed = playerSpeed * dt
        let nCol = Int(round(playerCol))
        let nRow = Int(round(playerRow))

        let nd = dirDelta[nextDir]
        if isWalkable(nCol + nd.dc, nRow + nd.dr) {
            let snapThresh: CGFloat = 0.38
            if abs(playerCol - CGFloat(nCol)) < snapThresh && abs(playerRow - CGFloat(nRow)) < snapThresh {
                playerDir = nextDir
            }
        }

        // Tunnel wrap
        if Int(round(playerRow)) == tunnelRow {
            if playerCol < -1 { playerCol = CGFloat(gridCols); return }
            if playerCol > CGFloat(gridCols) { playerCol = -1; return }
        }

        let d = dirDelta[playerDir]
        let targetCol = Int(round(playerCol)) + d.dc
        let targetRow = Int(round(playerRow)) + d.dr

        if isWalkable(targetCol, targetRow) {
            playerCol += CGFloat(d.dc) * speed
            playerRow += CGFloat(d.dr) * speed
        } else {
            playerCol = round(playerCol)
            playerRow = round(playerRow)
        }
    }

    private func moveGhost(index: Int, dt: CGFloat) {
        let speed = (ghosts[index].scared ? ghostScaredSpeed : ghostSpeed) * dt

        if ghosts[index].eaten {
            let targetCol: CGFloat = 10
            let targetRow: CGFloat = 8
            let dist = hypot(ghosts[index].col - targetCol, ghosts[index].row - targetRow)
            if dist < 0.5 {
                ghosts[index].eaten = false
                ghosts[index].scared = false
                ghosts[index].col = targetCol
                ghosts[index].row = targetRow
                return
            }
            let ddx = targetCol - ghosts[index].col
            let ddy = targetRow - ghosts[index].row
            let mag = hypot(ddx, ddy)
            if mag > 0 {
                ghosts[index].col += (ddx / mag) * ghostSpeed * dt * 2.0
                ghosts[index].row += (ddy / mag) * ghostSpeed * dt * 2.0
            }
            return
        }

        let gCol = Int(round(ghosts[index].col))
        let gRow = Int(round(ghosts[index].row))
        let snapThresh: CGFloat = 0.15
        let atCenter = abs(ghosts[index].col - CGFloat(gCol)) < snapThresh
            && abs(ghosts[index].row - CGFloat(gRow)) < snapThresh

        if atCenter {
            ghosts[index].col = CGFloat(gCol)
            ghosts[index].row = CGFloat(gRow)

            let reverse = (ghosts[index].dir + 2) % 4
            var options: [Int] = []
            for dir in 0..<4 {
                if dir == reverse { continue }
                let nd = dirDelta[dir]
                if isWalkable(gCol + nd.dc, gRow + nd.dr) {
                    options.append(dir)
                }
            }

            if options.isEmpty {
                let nd = dirDelta[reverse]
                if isWalkable(gCol + nd.dc, gRow + nd.dr) { options.append(reverse) }
            }

            if !options.isEmpty {
                if ghosts[index].scared {
                    ghosts[index].dir = options.randomElement()!
                } else {
                    var bestDir = options[0]
                    var bestDist: CGFloat = .greatestFiniteMagnitude
                    for dir in options {
                        let nd = dirDelta[dir]
                        let nc = CGFloat(gCol + nd.dc)
                        let nr = CGFloat(gRow + nd.dr)
                        let d = hypot(nc - playerCol, nr - playerRow)
                        if d < bestDist { bestDist = d; bestDir = dir }
                    }
                    ghosts[index].dir = bestDir
                }
            }
        }

        let d = dirDelta[ghosts[index].dir]
        let newCol = ghosts[index].col + CGFloat(d.dc) * speed
        let newRow = ghosts[index].row + CGFloat(d.dr) * speed

        if gRow == tunnelRow {
            if newCol < -1 { ghosts[index].col = CGFloat(gridCols); return }
            if newCol > CGFloat(gridCols) { ghosts[index].col = -1; return }
        }

        let checkCol = Int(round(newCol))
        let checkRow = Int(round(newRow))
        if isWalkable(checkCol, checkRow) {
            ghosts[index].col = newCol
            ghosts[index].row = newRow
        } else {
            ghosts[index].col = CGFloat(gCol)
            ghosts[index].row = CGFloat(gRow)
        }
    }


    // MARK: - Particle Effects

    private func emitDotParticles(atCol col: Int, row: Int) {
        guard let container = mazeContainer else { return }
        let mazeH = cellSize * CGFloat(gridRows)
        let worldX = CGFloat(col) * cellSize + cellSize / 2
        let worldY = mazeH - CGFloat(row) * cellSize - cellSize / 2

        let emitter = CAEmitterLayer()
        emitter.emitterPosition = CGPoint(x: worldX, y: worldY)
        emitter.emitterSize = CGSize(width: 2, height: 2)
        emitter.emitterShape = .point
        emitter.renderMode = .additive

        let cell = CAEmitterCell()
        cell.birthRate = 0 // we fire manually
        cell.lifetime = 0.4
        cell.velocity = 40
        cell.velocityRange = 20
        cell.emissionRange = .pi * 2
        cell.scale = 0.04
        cell.scaleSpeed = -0.06
        cell.color = NSColor(red: 1.0, green: 0.85, blue: 0.5, alpha: 1.0).cgColor
        cell.contents = {
            let s: CGFloat = 8
            let img = NSImage(size: NSSize(width: s, height: s))
            img.lockFocus()
            NSColor.white.setFill()
            NSBezierPath(ovalIn: NSRect(x: 0, y: 0, width: s, height: s)).fill()
            img.unlockFocus()
            return img.cgImage(forProposedRect: nil, context: nil, hints: nil)
        }()

        emitter.emitterCells = [cell]
        container.addSublayer(emitter)

        // Fire a short burst then remove
        DispatchQueue.main.async {
            cell.birthRate = 15
            emitter.emitterCells = [cell]
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                cell.birthRate = 0
                emitter.emitterCells = [cell]
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    emitter.removeFromSuperlayer()
                }
            }
        }
    }

    // MARK: - Helpers

    private func hitPlayer(now: UInt64) {
        lives -= 1
        if lives <= 0 {
            gameOver = true
            gameEndMach = now
            scoreLabel?.stringValue = "GAME OVER  \(score)"
        } else {
            playerCol = 10.0
            playerRow = 13.0
            playerDir = 2
            nextDir = 2
            powered = false
            powerTimer = 0
            let ghostStartCols: [CGFloat] = [9, 10, 11, 10]
            let ghostStartRows: [CGFloat] = [8, 8, 8, 7]
            for i in 0..<ghosts.count {
                ghosts[i].col = ghostStartCols[i]
                ghosts[i].row = ghostStartRows[i]
                ghosts[i].scared = false
                ghosts[i].eaten = false
            }
            updateScoreDisplay()
        }
    }
}
