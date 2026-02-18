# pipbounce

**A macOS daemon + Chrome extension that makes Picture-in-Picture windows dodge your mouse cursor — and turns them into retro arcade machines.**

pipbounce watches your cursor at 60fps and flings PiP windows away when you approach from the side. Sneak in from a corner to interact with playback controls. Toggle an animated RGB glow border. Or launch one of 12 built-in mini-games (with 13 modes) that use the PiP window as a game object bouncing around your screen.

---

## Features

- **Smart dodge** — PiP jumps to the farthest screen corner on side-edge entry, but allows corner-zone interaction for playback controls
- **Animated conic gradient glow** — 1px rotating border around PiP in purple, blue, red, green, or rainbow (3s rotation cycle)
- **Sacred geometry bursts** — Triangle, hexagram, and pentagram animations triggered on game events
- **12 mini-games (13 modes)** — Pong, Flappy Bird, Snake, Bounce (physics toy + paddle mode), Breakout, Space Invaders, Frogger, Runner, Asteroids, Cursor Hunt, Doodle Jump, Pac-Man
- **Auto-PiP** — Automatically enters PiP when switching tabs via Media Session API
- **Global hotkey** — Configurable keyboard shortcut (default: Cmd+Shift+D) to toggle dodge on/off
- **Launchd integration** — Auto-starts on login with `KeepAlive: true`, logs to `~/.pipbounce/pipbounce.log`
- **Zero dependencies** — Pure Swift, compiled with `swiftc`, only system frameworks (Cocoa, ApplicationServices, QuartzCore)

---

## System Architecture

```mermaid
graph TB
    subgraph Chrome["Chrome Browser"]
        BG["background.js\nAlt+P hotkey handler"]
        CS_EXT["content.js\nFinds largest video\nvideo.requestPiP()"]
        AP["autopip.js\nmediaSession handler\nauto-PiP on tab switch"]
        POPUP["popup.html + popup.js\nSettings UI + Game launcher"]
        PIP["PiP Window\n(Chrome-managed)"]
        BG -->|"executeScript"| CS_EXT
        CS_EXT -->|"requestPictureInPicture()"| PIP
        AP -->|"requestPictureInPicture()"| PIP
    end

    subgraph Daemon["Swift Daemon Process"]
        MAIN["main.swift\nPID lock + signals\nNSApplication.shared\nRunLoop.main.run()"]
        SRV["ControlServer\nRaw BSD sockets\nlocalhost:51789\nCORS + JSON"]
        DD["PipBounceDaemon\n1/60s Timer.scheduledTimer\nCGEvent mouse polling"]
        DISC["PipDiscovery\nAXUIElement enumeration\nTitle + heuristic matching"]
        GEOM["ScreenGeometry\ngetScreenFrame()\ngetFurthestCorner()"]
        HK["Hotkey\nCGEvent.tapCreate\nSession event tap"]
        RGB["RGBBorder\nNSWindow overlay\nCAGradientLayer (conic)\nCABasicAnimation spin\nBurst geometry shapes"]
        SET["Settings singleton\nenabled, cooldown, margin\ncornerSize, glow, glowColor\nhotkeyCode, hotkeyFlags"]
        GAMES["13 Game Engines\nGameBase subclasses\nDispatchSourceTimer"]

        MAIN --> SRV
        MAIN --> DD
        DD --> DISC
        DD --> GEOM
        DD --> RGB
        DD --> HK
        SRV --> SET
        SRV --> GAMES
    end

    subgraph macOS["macOS System APIs"]
        AX["Accessibility API\nAXUIElementCreateApplication\nAXUIElementCopyAttributeValue\nAXUIElementSetAttributeValue"]
        CGE["CGEvent API\nCGEvent(source: nil).location\nCGEvent.tapCreate (hotkey)"]
        WS["WindowServer\nCGWindowListCopyWindowInfo\nNSWindow overlays"]
    end

    POPUP <-->|"HTTP GET/POST\nlocalhost:51789"| SRV
    DISC -->|"kAXWindowsAttribute\nkAXPositionAttribute\nkAXSizeAttribute"| AX
    DD -->|"CGEvent.location"| CGE
    HK -->|"CGEvent.tapCreate\nsession event tap"| CGE
    DISC -->|"floatingWindowRects()"| WS
    RGB -->|"NSWindow\n.floating level\nignoresMouseEvents"| WS
    AX --> PIP
```

---

## Dodge Behavior

```mermaid
stateDiagram-v2
    [*] --> Idle: Daemon starts (main.swift)

    Idle --> Scanning: Timer fires (1/60s)

    Scanning --> NoPiP: PiP not found
    Scanning --> PiPFound: quickCheck() or findPipWindow()

    NoPiP --> HideBorder: rgbBorder.hide()
    HideBorder --> Idle: Reset interacting + wasOnPip

    PiPFound --> ShowBorder: settings.glow == true
    PiPFound --> CheckDodge: settings.enabled == true

    CheckDodge --> NotOnPip: !pip.bounds.contains(mousePos)
    CheckDodge --> JustEntered: onPip && !wasOnPip

    NotOnPip --> ResetState: interacting = false
    ResetState --> Idle

    JustEntered --> CornerEntry: isInPipCorner() == true
    JustEntered --> SideEntry: isInPipCorner() == false

    CornerEntry --> Interacting: interacting = true\n(suppress dodge)
    Interacting --> Idle: Mouse leaves PiP

    SideEntry --> CooldownCheck: dodgeIfReady()
    CooldownCheck --> Idle: Within cooldown period
    CooldownCheck --> AnimateDodge: Cooldown expired

    AnimateDodge --> AnimTimer: DispatchSource 16ms\ncubic ease-out (180ms)
    AnimTimer --> Idle: Animation complete
```

### Corner Detection Algorithm

The PiP window is divided into zones. The `isInPipCorner()` function checks if the mouse entry point falls within `cornerSize` pixels of **both** a horizontal and vertical edge simultaneously:

```
┌──────────────────────────────┐
│ CORNER │     SIDE EDGE      │ CORNER │
│  ZONE  │   (triggers dodge) │  ZONE  │
│────────│                    │────────│
│        │                    │        │
│  SIDE  │    PiP Content     │  SIDE  │
│  EDGE  │                    │  EDGE  │
│        │                    │        │
│────────│                    │────────│
│ CORNER │     SIDE EDGE      │ CORNER │
│  ZONE  │   (triggers dodge) │  ZONE  │
└──────────────────────────────┘

Corner zones = interaction allowed (no dodge)
Side edges = dodge triggered → farthest screen corner
```

`cornerSize` is clamped to at most half the PiP dimension: `min(settings.cornerSize, min(width, height) / 2)`

### Dodge Animation

When a dodge triggers, a `DispatchSourceTimer` fires every 16ms for 180ms total. Each tick:

1. Computes elapsed time via `mach_absolute_time()`
2. Applies **cubic ease-out**: `ease = 1.0 - pow(1.0 - t, 3.0)`
3. Interpolates PiP position from `animStart` to `animEnd`
4. Moves PiP via `AXUIElementSetAttributeValue(kAXPositionAttribute)`
5. Immediately syncs border overlay to match

Target corner is computed by `getFurthestCorner()`: tests all 4 screen corners (inset by `settings.margin`), picks the one whose center is farthest from the mouse (squared distance).

---

## PiP Window Detection

```mermaid
flowchart TD
    A["findPipWindow()"] --> B["Get running Chrome apps\nNSWorkspace.shared.runningApplications\nFilter by name/bundleIdentifier"]
    B --> C["Get floating window rects\nCGWindowListCopyWindowInfo\nFilter layer > 0"]
    C --> D["For each Chrome app:\nAXUIElementCreateApplication\nCopy kAXWindowsAttribute"]
    D --> E["For each window:\nextractPipInfo()"]

    E --> F{"Title contains\n'Picture in Picture' or\n'Picture-in-Picture'?"}
    F -->|Yes| FOUND["Return PipWindowInfo\n(bounds + axWindow)"]

    F -->|No| G{"Document PiP heuristics?"}
    G --> H["Check ALL conditions:"]
    H --> H1["title == '' or 'about:blank'"]
    H1 --> H2["matchesFloat: position matches\na floating window rect (±3px)"]
    H2 --> H3["role == '' or 'AXWindow'\nnot AXDialog/AXFloatingWindow/AXPopover"]
    H3 --> H4["No minimize button\nNo close button"]
    H4 --> H5["200 ≤ width ≤ 800\n100 ≤ height ≤ 600\naspect ratio > 1.4"]
    H5 -->|All pass| FOUND
    H5 -->|Any fail| SKIP["Skip window"]
```

**Caching strategy:** The daemon caches the `AXUIElement` reference and uses `quickCheck()` (fast AX position/size read) on each tick. Full `findPipWindow()` re-scan only happens every 0.5 seconds when the cache misses.

---

## Installation

### Prerequisites

| Requirement | Why |
|-------------|-----|
| macOS | Accessibility API (`AXUIElement`), `CGEvent`, Cocoa overlays |
| Chrome / Chromium | Extension host + PiP windows |
| Xcode CLI Tools | `swiftc` compiler |
| Python 3 | Icon generation during install |

### Steps

```bash
# 1. Build and install
./install.sh
```

The installer runs 4 steps:

```mermaid
flowchart LR
    A["Step 1\nStop existing daemon\nlaunchctl bootout\nor pkill"] --> B["Step 2\nCompile Swift\nswiftc daemon/*.swift\ndaemon/Games/*.swift\n-framework Cocoa\n-framework ApplicationServices\n-framework QuartzCore -O"]
    B --> C["Step 3\nGenerate icons\npython3 inline script\n16/48/128px PNGs"]
    C --> D["Step 4\nInstall launchd agent\ncom.pipbounce.daemon.plist\nKeepAlive + RunAtLoad"]
```

**Output binary:** `~/.pipbounce/pipbounce.app/Contents/MacOS/pipbounce`

**Code signing:** Uses "pipbounce Dev" certificate if found, otherwise ad-hoc (`codesign --sign -`)

```bash
# 2. Load Chrome extension
#    chrome://extensions → Developer mode → Load unpacked → select extension/

# 3. Grant Accessibility permission
#    System Settings → Privacy & Security → Accessibility
#    Add ~/.pipbounce/pipbounce.app
```

---

## Usage

### Triggering PiP

| Method | Mechanism |
|--------|-----------|
| Click extension icon | `popup.js` auto-calls `enterPip()` → `video.requestPictureInPicture()` on largest video |
| **Alt+P** | `background.js` command handler → injects `content.js` → toggles PiP |
| Switch tabs | `autopip.js` content script → `navigator.mediaSession.setActionHandler("enterpictureinpicture")` |

### Extension Popup UI

The popup (240px wide, dark zinc theme) provides:

- **Start/Stop PiP** button (context-aware label)
- **13 game mode buttons** (12 games, Bounce has 2 modes) — each POSTs to daemon, label toggles between start/stop
- **Dodge toggle** — on/off switch
- **Glow toggle** — on/off switch
- **Glow color picker** — 5 dots: purple, blue, red, green, rainbow
- **Corner zone selector** — segmented control: Small (60px), Medium (100px), Large (150px)
- **Hotkey recorder** — click to record, captures modifier+key, translates JS keyCodes to macOS virtual keycodes
- **Status indicator** — green dot "PiP active" / "Online", red dot "Offline — click to restart"

Status polls every 2 seconds via `GET /status`.

---

## Configuration

All settings are stored in the `Settings` singleton (in-memory, not persisted to disk). Changes apply instantly via HTTP API.

| Setting | Property | Default | UI Control | Description |
|---------|----------|---------|------------|-------------|
| Dodge enabled | `enabled` | `true` | Toggle switch | Master on/off for dodge behavior |
| Cooldown | `cooldown` | `0.4s` | — | Min time between consecutive dodges |
| Screen margin | `margin` | `20px` | — | Edge padding when positioning PiP after dodge |
| Corner safe zone | `cornerSize` | `100px` | Segmented: 60/100/150 | Size of each corner interaction zone |
| Glow border | `glow` | `true` | Toggle switch | Show/hide animated border overlay |
| Glow color | `glowColor` | `"purple"` | Color dot picker | Border color: purple, blue, red, green, rainbow |
| Hotkey keycode | `hotkeyCode` | `2` (D key) | Hotkey recorder | macOS virtual keycode for toggle |
| Hotkey flags | `hotkeyFlags` | `0x108` (Cmd+Shift) | Hotkey recorder | Modifier bitmask (0x100=Cmd, 0x008=Alt, 0x004=Ctrl, 0x002=Shift) |

---

## HTTP API Reference

Raw BSD socket server on `127.0.0.1:51789`. All responses are `Content-Type: application/json` with full CORS headers. OPTIONS requests return 204.

### Endpoints

```mermaid
sequenceDiagram
    participant P as Popup (popup.js)
    participant S as ControlServer (:51789)
    participant D as PipBounceDaemon
    participant G as Game Engines

    Note over P,S: Startup
    P->>S: GET /status
    S->>S: findPipWindow()
    S-->>P: {enabled, cooldown, margin, cornerSize,<br/>glow, glowColor, hotkeyCode, hotkeyFlags,<br/>pong, flappy, bounce, invaders, frogger,<br/>runner, snake, breakout, asteroids,<br/>cursorhunt, doodlejump, pacman, pipActive}

    Note over P,S: Settings change
    P->>S: POST /settings {"glow": true, "glowColor": "blue"}
    S->>S: applySettings() → mutate Settings singleton
    S-->>P: {enabled, cooldown, margin, cornerSize, glow}

    Note over P,G: Game toggle
    P->>S: POST /pong
    S->>D: daemon.toggleGame(pong) [main queue sync]
    D->>G: Stop any active game, then pong.start()
    S-->>P: {"pong": true}
```

| Method | Path | Request Body | Response | Notes |
|--------|------|-------------|----------|-------|
| `GET` | `/status` | — | Full state JSON (all settings + all game states + `pipActive`) | Also calls `findPipWindow()` |
| `POST` | `/toggle` | — | `{enabled: bool}` | Toggles `settings.enabled` |
| `POST` | `/settings` | JSON with any subset of settings | `{enabled, cooldown, margin, cornerSize, glow}` | Partial updates OK |
| `POST` | `/restart` | — | `{restarting: true}` | Calls `cleanup()` + `exit(0)` after 100ms; launchd restarts |
| `POST` | `/pong` | — | `{pong: bool}` | Toggle Pong game |
| `POST` | `/flappy` | — | `{flappy: bool}` | Toggle Flappy Bird |
| `POST` | `/bounce` | — | `{bounce: bool}` | Toggle Bounce (auto mode) |
| `POST` | `/bounce-paddle` | — | `{bounce: bool}` | Toggle Bounce (paddle mode — sets `bounce.paddleMode = true`) |
| `POST` | `/invaders` | — | `{invaders: bool}` | Toggle Space Invaders |
| `POST` | `/frogger` | — | `{frogger: bool}` | Toggle Frogger |
| `POST` | `/runner` | — | `{runner: bool}` | Toggle Runner |
| `POST` | `/snake` | — | `{snake: bool}` | Toggle Snake |
| `POST` | `/breakout` | — | `{breakout: bool}` | Toggle Breakout |
| `POST` | `/asteroids` | — | `{asteroids: bool}` | Toggle Asteroids |
| `POST` | `/cursorhunt` | — | `{cursorhunt: bool}` | Toggle Cursor Hunt |
| `POST` | `/doodlejump` | — | `{doodlejump: bool}` | Toggle Doodle Jump |
| `POST` | `/pacman` | — | `{pacman: bool}` | Toggle Pac-Man |

All game endpoints dispatch to main queue synchronously via `DispatchSemaphore` and call `daemon.toggleGame()`, which stops any running game before starting the requested one.

---

## Mini-Games

### Game Engine Architecture

```mermaid
classDiagram
    class MiniGame {
        <<protocol>>
        +active: Bool
        +lastBounds: CGRect
        +start(screen: CGRect, pip: PipWindowInfo, border: RGBBorder)
        +stop()
    }

    class GameBase {
        +active: Bool
        +lastBounds: CGRect
        +score: Int
        +gameOver: Bool
        #cachedAXWindow: AXUIElement?
        #cachedPipSize: CGSize
        #borderRef: RGBBorder?
        #screenH: CGFloat
        #timerIntervalMs: Int = 2
        +machToSeconds(UInt64) CGFloat
        +deltaTime() CGFloat
        +refreshPipSize()
        +movePip(to: CGPoint) Bool
        +syncBorder(around: CGRect)
        +triggerGameOver(message: String)
        +checkGameOverTimeout() Bool
        +createScoreOverlay(screen, width)
        +createFullscreenOverlay(screen) (NSWindow, CALayer)
        +mousePosition() CGPoint?
        +isMouseDown: Bool
        #onStart(screen, pip)*
        #onStop()
        #gameTick()*
    }

    MiniGame <|.. GameBase : implements
    GameBase <|-- PongGame : timerIntervalMs=8
    GameBase <|-- FlappyGame : timerIntervalMs=4
    GameBase <|-- SnakeGame
    GameBase <|-- BounceGame
    GameBase <|-- BreakoutGame
    GameBase <|-- InvadersGame
    GameBase <|-- FroggerGame
    GameBase <|-- RunnerGame
    GameBase <|-- AsteroidsGame
    GameBase <|-- CursorHuntGame
    GameBase <|-- DoodleJumpGame
    GameBase <|-- PacManGame
```

**Key design:** Each game file declares a **global singleton** (e.g., `let pong = PongGame()`) referenced by `ControlServer` and `DodgeDaemon`. The daemon's tick loop bails immediately when any game is active — games own the PiP position entirely during gameplay.

### GameBase Lifecycle

```mermaid
sequenceDiagram
    participant D as DodgeDaemon
    participant GB as GameBase
    participant Sub as Subclass (e.g. PongGame)

    D->>GB: start(screen, pip, border)
    GB->>GB: Cache AXUIElement, PiP size, screenH
    GB->>GB: Reset score, gameOver
    GB->>Sub: onStart(screen, pip)
    Sub->>Sub: Create overlays, set initial state
    GB->>GB: Start DispatchSourceTimer (timerIntervalMs)

    loop Every tick
        GB->>Sub: gameTick()
        Sub->>Sub: deltaTime(), game logic
        Sub->>GB: movePip(to:), syncBorder(around:)
        Sub->>GB: refreshPipSize() [resize-aware]
    end

    alt Game Over
        Sub->>GB: triggerGameOver("GAME OVER - 15")
        GB->>GB: gameEndMach = mach_absolute_time()
        loop Remaining ticks
            Sub->>GB: checkGameOverTimeout()
            GB->>GB: After 2.5s → stop()
        end
    end

    GB->>GB: Cancel timer
    GB->>GB: Restore PiP to bottom-right corner
    GB->>GB: Reset border tilt + hide
    GB->>Sub: onStop()
    Sub->>Sub: Remove overlay windows
```

### Game Details

| Game | Singleton | Timer | Controls | Key Mechanics |
|------|-----------|-------|----------|---------------|
| **Pong** | `pong` | 8ms | Mouse Y = paddle | PiP = ball, AI opponent (150ms reaction delay + noise), rally speed ramp 420→900 px/s over 15s, ball trail (3 ghost layers at 0.6/0.3/0.15 opacity), screen shake on score, match: first to 7 win by 2 |
| **Flappy Bird** | `flappy` | 4ms | Click = flap | PiP resized to 200×112, gravity=900 flapImpulse=-360, green pipe NSWindows (body 56px + cap 70×28px), border tilts with velocity via `rotationPadding`, pipeGap = pipHeight + 160, best score tracking |
| **Snake** | `snake` | 2ms | Mouse = steer, click = boost | Cursor-following head (maxTurnRate 6 rad/s), distance-based tail tracking (sampled every 6px), 3× screen world with smooth camera lerp (0.08), click = 2× speed for 0.3s (2s cooldown), tail grows on food |
| **Bounce** | `bounce` | 2ms | Click-drag = grab & throw | Physics toy: gravity (120), elasticity (0.9), air friction (0.9993), throw velocity from position history, border tilts with movement, rest detection at 3 px/s |
| **Bounce Paddle** | `bounce` | 2ms | Automatic (AI plays) | Same physics + AI paddle on farthest screen edge (80×6px, gradient shimmer), scores on paddle hits, paddle teleports to opposite edge on hit, sacred geometry bursts at 20/50/100 (tier 1/2/3), vibrancy score overlay |
| **Breakout** | `breakout` | 8ms | Mouse X = paddle, click = launch | 10×5 brick grid (5 color rows, top 2 rows = 2 hits), row scoring 50/40/30/20/10, 3 lives (♥), extra lives at 500/1500 pts, levels (paddle shrinks 20px/level, min 80px, speed +10%/level), CAEmitterLayer particle burst on brick death, paddle flash + spring bounce on hit |
| **Space Invaders** | `invaders` | 8ms | Mouse X = ship, hold = rapid fire (4/sec) | 8×5 grid with 11×8 pixel-art bitmap sprites (squid/crab/skull), 5 row colors, mystery UFO (random 50/100/150/300 pts, spawns every 20-30s), wave system (speed ×1.15, shot interval ×0.85 per wave), 3 lives with 1.5s invulnerability blink, explosion particles + floating score pops, max 3 simultaneous player bullets |
| **Frogger** | `frogger` | 8ms | Mouse X = position, L-click = hop forward, R-click = hop back | 8 lanes (0=safe start, 1-6=traffic, 7=goal), 3 vehicle types: motorcycle (fast, narrow), car (medium), truck (slow, wide) with detailed CALayer graphics (wheels, headlights, windshield), near-miss detection (8px threshold), death shake animation (8px amp, 30Hz), speed +15 px/s per crossing, lane backgrounds + dashed center lines |
| **Runner** | `runner` | 8ms | Mouse Y = vertical position | Side-scrolling gap dodger: obstacles with moving gaps (sinusoidal oscillation) scroll left at 200→600 px/s, zone system every ~10 obstacles with zone announcement pause, zone-colored obstacles (grey→steel→purple→brown→forest→crimson), gap glow indicators, death particles |
| **Asteroids** | `asteroids` | 2ms | Mouse = aim (ship thrusts toward), hold = auto-fire | 3× screen world with camera lerp (0.08), thrust physics (400 accel, drift half-life 0.5s), 3 asteroid sizes (large r=25/20pts → medium r=15/50pts → small r=8/100pts), large splits into 2 medium, medium into 2 small, wave system with 1.5s pause, 3 lives + 2s invulnerability, CAEmitterLayer for explosions + thrust trail + ambient space dust, 5 max bullets with 2s lifetime |
| **Cursor Hunt** | `cursorhunt` | 2ms | Move mouse to survive | PiP **chases your cursor** — accelerates toward mouse (400 + 40×time px/s²), max speed ramps (500 + 40×time, cap 1600), friction 0.985, score = survival time in seconds, game over = PiP catches cursor (8px inset hitbox), border tilts with velocity |
| **Doodle Jump** | `doodlejump` | 2ms | Mouse X = horizontal | PiP bounces on platforms (impulse -520, strong -620), gravity 900, camera scrolls up as player reaches new heights, static platforms (green) + moving platforms (brown), platform width = 1.4× PiP width, spacing increases with height, game over = fall below camera |
| **Pac-Man** | `pacman` | 8ms | Mouse = direction | 21×21 maze (hardcoded template), 4 ghosts (red/pink/cyan/orange) with CAShapeLayer bodies + animated eye pupils, power pellets = 6s scared mode (ghosts turn blue, score doubles per ghost: 200→400→800→1600), tunnel wrapping on row 8, camera follows player through world, frosted glass NSWindow overlay, 3 lives, win = all dots collected |

### Rendering

All game graphics use **fullscreen NSWindow overlays** created via `GameBase.createFullscreenOverlay()`:
- `NSWindow` with `.borderless` style, `.floating` level
- `backgroundColor = .clear`, `isOpaque = false`
- `ignoresMouseEvents = true` — cursor passes through
- `collectionBehavior = [.canJoinAllSpaces, .stationary, .transient, .ignoresCycle]`
- Graphics rendered via `CALayer` tree on the content view

Score overlay: separate 160x44 `NSWindow` centered at screen top, black 60% alpha background, 24pt mono bold white text.

---

## RGB Glow Border

The border is a separate `NSWindow` that tracks the PiP position.

### Rendering Pipeline

```mermaid
flowchart TD
    A["show(around: CGRect)"] --> B["Convert AX coords → NSWindow frame\n(flip Y: screenH - origin.y - height)"]
    B --> C{"Window exists?"}
    C -->|No| D["Create NSWindow\n.borderless, .floating\nignoresMouseEvents = true"]
    D --> E["Add CAGradientLayer\ntype: .conic\nstartPoint: (0.5, 0.5)"]
    E --> F["Add CABasicAnimation\nrotation.z: 0→2π\nduration: 3s\nrepeatCount: ∞"]
    F --> G["Add CAShapeLayer mask\neven-odd fill rule\nouter rect - inner rect (1px inset)"]
    C -->|Yes| H["Update frame position"]
    H --> I["CATransaction.begin()\nsetDisableActions(true)"]
    I --> J["Update gradient bounds\ndiag = sqrt(w² + h²) + 20"]
    J --> K["Update mask path\nouter: 3px radius rounded rect\ninner: 2px radius, 1px inset"]
    K --> L["CATransaction.commit()"]
```

### Color Sets

| Color | Gradient Stops |
|-------|---------------|
| Purple | Violet → Pink → Deep Purple → Lavender |
| Blue | Royal Blue → Cyan → Steel Blue → Deep Blue |
| Red | Red → Coral → Crimson → Dark Red |
| Green | Emerald → Mint → Forest → Lime |
| Rainbow | Red → Yellow → Green → Cyan → Blue → Magenta → Red |

### Burst Geometry

`burstGeometry(tier:around:)` creates animated sacred geometry shapes:

| Tier | Shape | Animation |
|------|-------|-----------|
| 1 | Triangle (3-sided polygon) | Spin 0→2π, scale 0.3→1.5, fade out, 2s |
| 2 | Hexagram (two overlapping triangles) | Spin 0→2π, scale 0.3→1.5, fade out, 2s |
| 3+ | Pentagram with circle | Spin 0→4π, scale 0.3→1.5, fade out, 2s |

Shapes are drawn as `CAShapeLayer` sublayers using the current glow color, cleaned up after 2.1s.

### Tilt

`tilt(_ angle: CGFloat)` applies `CATransform3DMakeRotation` to the container layer. Used by Flappy Bird to wobble the border based on vertical velocity. Requires `rotationPadding > 0` for headroom.

---

## Process Lifecycle

```mermaid
flowchart TD
    subgraph Install["install.sh"]
        I1["Stop existing via launchctl\nor pkill"] --> I2["swiftc compile\n-O optimization"]
        I2 --> I3["codesign\n(dev cert or ad-hoc)"]
        I3 --> I4["python3 generate icons\n16/48/128px PNG"]
        I4 --> I5["Write launchd plist\nKeepAlive: true\nRunAtLoad: true"]
        I5 --> I6["launchctl bootstrap\n+ kickstart"]
    end

    subgraph Runtime["Daemon Runtime (main.swift)"]
        R1["setbuf(stdout/stderr, nil)\nUnbuffered output"] --> R2["killExisting()\nRead PID file\nSIGTERM old process\nusleep 300ms"]
        R2 --> R3["writePid()\n~/.pipbounce/pipbounce.pid"]
        R3 --> R4["NSApplication.shared"]
        R4 --> R5["ControlServer().start()\nBSD socket on :51789\nDispatchQueue.global(.utility)"]
        R5 --> R6["PipBounceDaemon().start()\ninstallHotkey()\nTimer.scheduledTimer 1/60s"]
        R6 --> R7["signal(SIGINT/SIGTERM)\ncleanup() + exit(0)"]
        R7 --> R8["RunLoop.main.run()"]
    end

    subgraph Hotkey["Global Hotkey (Hotkey.swift)"]
        HK1["CGEvent.tapCreate\nsession event tap\nkeyDown events"] --> HK2["Check keyCode == settings.hotkeyCode\nflags == settings.hotkeyFlags"]
        HK2 -->|Match| HK3["settings.enabled.toggle()\nReturn nil (consume event)"]
        HK2 -->|No match| HK4["passRetained (forward event)"]
    end

    subgraph Shutdown["Clean Shutdown"]
        S1["SIGTERM or SIGINT"] --> S2["cleanup()\nRemove PID file"]
        S2 --> S3["exit(0)"]
        S3 --> S4["launchd KeepAlive\nrestarts if /restart endpoint\nor unexpected crash"]
    end

    Install --> Runtime
    Runtime --> Hotkey
    Runtime --> Shutdown
```

---

## Project Structure

```
pipbounce/
├── install.sh                          # 4-step build + install + launchd setup
├── README.md
├── extension/                          # Chrome MV3 Extension
│   ├── manifest.json                   # v1.4, permissions: scripting, activeTab, tabs
│   ├── popup.html                      # 240px dark zinc UI, all controls
│   ├── popup.js                        # Settings controller, game toggles, status polling (2s)
│   ├── background.js                   # Alt+P command → injects content.js
│   ├── content.js                      # Find largest video → toggle PiP
│   ├── autopip.js                      # Content script (all pages) → mediaSession auto-PiP
│   └── icons/                          # Generated PNGs (16/48/128px)
└── daemon/                             # Swift source (compiled by swiftc)
    ├── main.swift                      # Entry: PID lock, signals, NSApplication, RunLoop
    ├── DodgeDaemon.swift               # 1/60s tick, CGEvent mouse, dodge + animate
    ├── ControlServer.swift             # BSD socket HTTP on :51789, route dispatch
    ├── PipDiscovery.swift              # AXUIElement + CGWindowList PiP detection
    ├── ScreenGeometry.swift            # Screen frame + farthest corner math
    ├── Settings.swift                  # Config singleton (in-memory, not persisted)
    ├── Hotkey.swift                    # CGEvent tap for global hotkey
    ├── RGBBorder.swift                 # Conic gradient border + burst geometry
    ├── MiniGame.swift                  # Protocol: active, lastBounds, start(), stop()
    └── Games/
        ├── GameBase.swift              # Abstract base: Mach timing, DispatchSourceTimer, score overlay, PiP restore
        ├── PongGame.swift              # AI opponent, rally speed ramp, ball trail, screen shake, first-to-7
        ├── FlappyGame.swift            # Gravity + flap, green pipe NSWindows, PiP resize to 200×112, border tilt
        ├── SnakeGame.swift             # Cursor-following head, 3× world + camera, distance-based tail, click boost
        ├── BounceGame.swift            # Physics toy (drag/throw) + AI paddle mode, burst geometry milestones
        ├── BreakoutGame.swift          # 10×5 bricks (2-hit top rows), lives, levels, CAEmitterLayer particles
        ├── InvadersGame.swift          # 11×8 pixel-art sprites, mystery UFO, wave system, rapid fire, score pops
        ├── FroggerGame.swift           # 8 lanes, 3 vehicle types with detailed graphics, hop forward/back, near-miss
        ├── RunnerGame.swift            # Side-scrolling gap dodger, zone system, moving gaps, death particles
        ├── AsteroidsGame.swift         # 3× world, thrust/drift physics, 3 asteroid sizes, auto-fire, emitter FX
        ├── CursorHuntGame.swift        # PiP chases cursor with ramping acceleration, survive as long as possible
        ├── DoodleJumpGame.swift        # Platform bouncing, camera scroll, static + moving platforms
        └── PacManGame.swift            # 21×21 maze, 4 ghosts with eyes, power pellets, tunnel wrap, glass overlay
```

---

## Troubleshooting

| Problem | Cause | Solution |
|---------|-------|----------|
| "Accessibility permission required" | Daemon can't access AXUIElement | System Settings → Privacy & Security → Accessibility → add `~/.pipbounce/pipbounce.app` (or terminal app) |
| PiP window not detected | Title doesn't match, or Document PiP fails heuristics | Ensure Chrome PiP is active. Document PiP must be: untitled, floating layer, no minimize/close buttons, 200-800px wide, aspect > 1.4 |
| Extension says "Offline" | Daemon not running or port 51789 in use | Check `launchctl list com.pipbounce.daemon`, or run `~/.pipbounce/pipbounce.app/Contents/MacOS/pipbounce` manually |
| Game overlays not visible | Missing Screen Recording permission | System Settings → Privacy & Security → Screen Recording → add the app |
| Build fails | Missing swiftc or python3 | Run `xcode-select --install`, ensure `python3` is in PATH |
| Hotkey not working | CGEvent tap not enabled | Grant Accessibility permission; restart daemon |
| Settings lost on restart | Settings are in-memory only | Expected behavior — settings reset to defaults on daemon restart |
| Daemon won't start (port busy) | Previous instance didn't clean up | Check `lsof -i :51789`, kill stale process, or delete `~/.pipbounce/pipbounce.pid` |

---

## License

MIT
