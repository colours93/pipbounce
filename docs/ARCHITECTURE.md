# pipbounce — Architecture

![version](https://img.shields.io/badge/version-1.x-blue) ![last updated](https://img.shields.io/badge/updated-2026--02--19-brightgreen)

pipbounce is a macOS background daemon plus a Chrome extension that makes Picture-in-Picture windows dodge the mouse cursor and doubles as a retro arcade platform. This document covers the overall system architecture, daemon internals, and process lifecycle. For detailed treatment of the dodge algorithm and PiP detection see [DODGE-SYSTEM.md](./DODGE-SYSTEM.md); for the game engine and all thirteen game modes see [GAME-ENGINE.md](./GAME-ENGINE.md); for the glow border and sacred geometry burst system see [RGB-BORDER.md](./RGB-BORDER.md); for the HTTP API see [API-REFERENCE.md](./API-REFERENCE.md).

---

## Diagram color legend

All Mermaid diagrams in this documentation follow a consistent color system:

| Color | Hex | Meaning |
|-------|-----|---------|
| Cyan | `#00fff5` | Data flow / discovery / polling |
| Purple | `#b44dff` | UI / rendering / overlays |
| Green | `#00ff88` | System / lifecycle / infrastructure |
| Red | `#ff4d6d` | Events / actions / mutations |

---

## System Architecture Overview

pipbounce is organized into three cooperating layers that span two processes and the macOS kernel:

1. **Chrome Extension** — A Manifest V3 extension running inside Chrome. It provides the user-visible popup UI and issues commands to the daemon over localhost HTTP. It also injects content scripts that interact with the browser's Picture-in-Picture API to enter and exit PiP mode.

2. **Swift Daemon** — A native macOS process compiled with `swiftc` and managed by `launchd`. It runs a raw BSD socket HTTP server on port 51789, polls the mouse position at 60 fps, discovers PiP windows through the Accessibility API, animates dodges, renders an always-on-top gradient border, and drives thirteen mini-game engines.

3. **macOS System APIs** — The daemon relies on three kernel-level subsystems: the Accessibility API (`AXUIElement`) for reading and writing PiP window geometry, the CGEvent API for global mouse polling and keyboard event tapping, and the WindowServer (`CGWindowList` + `NSWindow`) for floating overlay windows.

The diagram below shows every significant component in all three layers and the connections between them. Arrows are labeled with the mechanism or data type they carry.

```mermaid
%%{init: {'theme': 'dark', 'themeVariables': {'primaryColor': '#0a2540', 'primaryTextColor': '#00fff5', 'primaryBorderColor': '#00fff5', 'lineColor': '#b44dff', 'secondaryColor': '#1a0a3e', 'tertiaryColor': '#0a3520', 'edgeLabelBackground': '#111', 'clusterBkg': '#0d0d14', 'clusterBorder': '#2a2a3a', 'titleColor': '#fafafa', 'nodeTextColor': '#fafafa'}}}%%
graph TB
    classDef chrome fill:#1a0a3e,stroke:#b44dff,color:#e0d0ff
    classDef daemon fill:#0a2540,stroke:#00fff5,color:#d0f4ff
    classDef macos fill:#0a3520,stroke:#00ff88,color:#d0ffe8
    classDef event fill:#3a0a15,stroke:#ff4d6d,color:#ffd0d8
    classDef settings fill:#1a1a0a,stroke:#ffdd44,color:#fffae0

    subgraph EXT["Chrome Extension"]
        BG["background.js\nAlt+P hotkey handler"]
        CS["content.js\nFind largest video\nvideo.requestPictureInPicture()"]
        AP["autopip.js\nmediaSession handler\nauto-PiP on tab switch"]
        POPUP["popup.html + popup.js\nSettings UI + Game launcher\nStatus polling every 2s"]
        PIP["PiP Window\nChrome-managed\nfloating overlay"]
    end

    subgraph DMN["Swift Daemon  ( ~/.pipbounce/pipbounce.app )"]
        MAIN["main.swift\nPID lock + signals\nNSApplication.shared\nRunLoop.main.run()"]
        SRV["ControlServer\nRaw BSD socket :51789\nSO_REUSEADDR, listen(5)\nDispatchQueue global utility\nFull CORS headers"]
        DD["PipBounceDaemon\nTimer.scheduledTimer 1/60s\nCGEvent mouse polling\nDodge animation 16ms DispatchSource\nCubic ease-out 180ms"]
        DISC["PipDiscovery\nNSWorkspace Chrome app scan\nAXUIElement window enumeration\nTitle + Document PiP heuristics\nquickCheck() fast path"]
        GEOM["ScreenGeometry\ngetScreenFrame()\ngetFurthestCorner()\nmargin-aware corner math"]
        HK["Hotkey\nCGEvent.tapCreate\ncgSessionEventTap\nkeyDown mask\nEvent consume on match"]
        RGB["RGBBorder\nNSWindow floating overlay\nCAGradientLayer conic spin 3s\nCAShapeLayer even-odd mask\nBurst geometry animation"]
        SET["Settings singleton\nenabled / cooldown / margin\ncornerSize / glow / glowColor\nhotkeyCode / hotkeyFlags\nin-memory not persisted"]
        GAMES["13 Game Engines\nGameBase DispatchSourceTimer\nPong / Flappy / Snake / Bounce\nBreakout / Invaders / Frogger\nRunner / Asteroids / CursorHunt\nDoodleJump / PacMan"]
        MAIN -->|"ControlServer.start()"| SRV
        MAIN -->|"PipBounceDaemon.start()"| DD
        DD -->|"findPipWindow() / quickCheck()"| DISC
        DD -->|"getFurthestCorner()"| GEOM
        DD -->|"show / hide / tilt"| RGB
        DD -->|"installHotkey()"| HK
        SRV -->|"applySettings()"| SET
        SRV -->|"toggleGame() via main-queue semaphore"| GAMES
        GAMES -->|"movePip() / syncBorder()"| RGB
    end

    subgraph SYS["macOS System APIs"]
        AX["Accessibility API\nAXUIElementCreateApplication\nAXUIElementCopyAttributeValue\nAXUIElementSetAttributeValue\nkAXPositionAttribute kAXSizeAttribute"]
        CGE["CGEvent API\nCGEvent source nil location\nCGEvent.tapCreate session tap\nkeyDown event mask"]
        WS["WindowServer\nCGWindowListCopyWindowInfo\nNSWindow floating overlays\nCALayer rendering tree"]
    end

    POPUP <-->|"HTTP GET / POST\nlocalhost:51789\nJSON responses + CORS"| SRV
    BG -->|"chrome.scripting.executeScript"| CS
    CS -->|"requestPictureInPicture()"| PIP
    AP -->|"requestPictureInPicture()"| PIP
    DISC -->|"kAXWindowsAttribute\nkAXPositionAttribute kAXSizeAttribute\nkAXTitleAttribute kAXRoleAttribute\nkAXMinimizeButton kAXCloseButton"| AX
    AX -->|"read / write window geometry"| PIP
    DD -->|"CGEvent location mouse position"| CGE
    HK -->|"tapCreate session event tap"| CGE
    DISC -->|"floatingWindowRects() layer > 0"| WS
    RGB -->|"NSWindow borderless floating\nignoresMouseEvents canJoinAllSpaces"| WS

    class BG,CS,AP,POPUP,PIP chrome
    class MAIN,SRV,DD,DISC,GEOM,HK,RGB,SET,GAMES daemon
    class AX,CGE,WS macos
```

### Key architectural decisions

**No Xcode project.** The daemon is compiled with a single `swiftc` invocation during `./install.sh`. All source files are passed directly on the command line. This keeps the build reproducible without a developer account or project file.

**Raw BSD sockets.** `ControlServer` opens a TCP socket with `socket(AF_INET, SOCK_STREAM, 0)` and handles HTTP with basic string parsing. This avoids the need for Vapor, NIO, or any third-party HTTP library while remaining compatible with the browser's `fetch()` API through explicit CORS headers.

**Global singletons for all subsystems.** `settings`, `pong`, `flappy`, `bounce`, and the other game instances are file-scope `let` constants visible across the entire daemon. This is intentional: `ControlServer` and `DodgeDaemon` must reference the same game objects, and Swift's module system guarantees these constants are initialized exactly once before `main.swift` runs.

**Accessibility API for PiP control.** The daemon moves and reads PiP windows through `AXUIElement` rather than private window-server APIs. This is the only officially supported way for a third-party process to reposition another application's window on macOS, at the cost of requiring the Accessibility permission.

---

## Daemon Internals

### Bootstrap sequence

`main.swift` is the entry point. It runs synchronously from top to bottom before handing control to `RunLoop.main.run()`. The order of operations matters: stdio is made unbuffered first so that `launchd` captures log output immediately, then any pre-existing daemon instance is stopped, then the process registers itself, and only then are the subsystems started.

```
setbuf(stdout, nil)       — unbuffered stdout for launchd log capture
setbuf(stderr, nil)       — unbuffered stderr

killExisting()            — read ~/.pipbounce/pipbounce.pid
                          — SIGTERM the old PID
                          — usleep(300_000) — give it 300ms to exit

writePid()                — create ~/.pipbounce/ if needed
                          — write getpid() to the PID file

NSApplication.shared      — initialize Cocoa run loop infrastructure

ControlServer().start()   — bind :51789, start accept loop on global(.utility)
PipBounceDaemon().start() — installHotkey() + schedule 1/60s timer

signal(SIGINT)  { cleanup(); exit(0) }
signal(SIGTERM) { cleanup(); exit(0) }

RunLoop.main.run()        — block forever, dispatching timers and events
```

`NSApplication.shared` is required even though pipbounce is a background daemon (it has `LSUIElement = true` in its `Info.plist`). Cocoa's window and timer machinery depends on the application object being initialized. The `RunLoop.main.run()` call at the end drives both the 60 fps timer and the CGEvent tap source.

### The 1/60s tick loop

`PipBounceDaemon.start()` schedules a `Timer.scheduledTimer` with interval `1/60.0` seconds on the main run loop. Every tick calls `PipBounceDaemon.tick()`, which is the central coordinator for the dodge behavior.

The tick immediately bails out if any game engine is active or a dodge animation is in progress. This is a deliberate design: game engines own their own `DispatchSourceTimer` at their preferred intervals (2 ms for physics-heavy games, 8 ms for turn-based ones), so the 60 fps timer would be redundant and would contend for the AX API during gameplay.

When no game is active, the tick polls the mouse position with `CGEvent(source: nil).location`, then resolves the PiP window through a two-tier cache:

1. **Fast path** — If `cachedPipWindow` holds an `AXUIElement` from a previous successful scan, `quickCheck()` reads its current position and size in a single AX roundtrip. If that succeeds the cache is considered valid.
2. **Slow path** — If the fast path fails (the window closed, moved processes, or was never found), a full `findPipWindow()` re-scan is triggered, but no more than once every 500 ms (`discoveryInterval`). This prevents the AX API from being hammered when no PiP is open.

The diagram below shows the full decision tree inside a single tick:

```mermaid
%%{init: {'theme': 'dark', 'themeVariables': {'primaryColor': '#0a2540', 'primaryTextColor': '#00fff5', 'primaryBorderColor': '#00fff5', 'lineColor': '#b44dff', 'secondaryColor': '#1a0a3e', 'tertiaryColor': '#0a3520', 'edgeLabelBackground': '#111', 'clusterBkg': '#0d0d14', 'clusterBorder': '#2a2a3a', 'titleColor': '#fafafa', 'nodeTextColor': '#fafafa'}}}%%
flowchart TD
    classDef check fill:#0a2540,stroke:#00fff5,color:#d0f4ff
    classDef action fill:#0a3520,stroke:#00ff88,color:#d0ffe8
    classDef event fill:#3a0a15,stroke:#ff4d6d,color:#ffd0d8
    classDef skip fill:#1a1a1a,stroke:#444,color:#aaa

    T["tick() called\nTimer.scheduledTimer 1/60s"] --> G["Any game active\nor animating?"]
    G -->|"yes"| BAIL["return immediately\nno AX IPC contention"]
    G -->|"no"| MOUSE["CGEvent source nil\nRead mouse position"]
    MOUSE --> CACHE["cachedPipWindow != nil?"]
    CACHE -->|"yes"| QC["quickCheck cached AXUIElement\nRead position + size via AX"]
    QC -->|"success"| HASP["pip resolved from cache"]
    QC -->|"fail / nil"| TROT["discoveryInterval elapsed?\n0.5s throttle"]
    CACHE -->|"no"| TROT
    TROT -->|"no"| HIDEB["rgbBorder.hide()\nreturn"]
    TROT -->|"yes"| SCAN["findPipWindow()\nFull Chrome + AX scan\nUpdate cachedPipWindow"]
    SCAN -->|"not found"| RESET["interacting = false\nwasOnPip = false\ncachedPipWindow = nil\nrgbBorder.hide()"]
    SCAN -->|"found"| HASP

    HASP --> GLOW["settings.glow?"]
    GLOW -->|"true"| SHOW["rgbBorder.show(around: pip.bounds)"]
    GLOW -->|"false"| HIDEB2["rgbBorder.hide()"]
    SHOW --> ENB["settings.enabled?"]
    HIDEB2 --> ENB
    ENB -->|"false"| DONE["return"]
    ENB -->|"true"| ONPIP["pip.bounds.contains(mousePos)?"]
    ONPIP -->|"not on PiP"| CLEARINT["interacting = false\nwasOnPip = false"]
    ONPIP -->|"on PiP AND !wasOnPip\n(fresh entry)"| CORNER["isInPipCorner()?"]
    CORNER -->|"corner zone"| SETINT["interacting = true\n(suppress dodge)"]
    CORNER -->|"side edge"| DODGE["dodgeIfReady(pip, mousePos)"]

    class T,MOUSE check
    class HASP,SHOW action
    class DODGE,RESET event
    class BAIL,HIDEB,HIDEB2,DONE,CLEARINT skip
```

### Subsystem responsibilities

The daemon is composed of eight cooperating subsystems. The table below summarizes what each one owns and how it communicates with others.

| Subsystem | File | Owns | Communicates via |
|-----------|------|------|-----------------|
| `main.swift` | `main.swift` | PID lifecycle, signal handlers, startup order | Direct calls at boot |
| `ControlServer` | `ControlServer.swift` | HTTP server socket, request routing | Reads/writes `settings` singleton; dispatches to `daemon.toggleGame()` via main-queue semaphore |
| `PipBounceDaemon` | `DodgeDaemon.swift` | 60 fps tick, dodge animation, game coordinator | Calls `findPipWindow()`, `quickCheck()`, `getFurthestCorner()`, `rgbBorder` methods |
| `PipDiscovery` | `PipDiscovery.swift` | PiP window detection logic | Returns `PipWindowInfo`; calls AX API and `CGWindowListCopyWindowInfo` |
| `ScreenGeometry` | `ScreenGeometry.swift` | Screen frame conversion, corner math | Pure functions, no shared state |
| `Hotkey` | `Hotkey.swift` | Global keyboard event tap | Mutates `settings.enabled` directly |
| `RGBBorder` | `RGBBorder.swift` | Floating overlay NSWindow, CALayer rendering, burst geometry | Called by `PipBounceDaemon` and game engines |
| `Settings` | `Settings.swift` | All runtime configuration | Global `let settings = Settings()` instance |

### Dodge animation

When `dodgeIfReady()` determines a dodge should fire, it captures the current PiP position (`animStart`), the target corner position (`animEnd`), and the current Mach time (`animStartMach`), then starts a `DispatchSourceTimer` that fires every 16 ms with `.strict` flags.

Each animation tick calls `stepAnimation()`, which computes interpolation parameter `t = elapsed / 0.18` (180 ms total), then applies a **cubic ease-out** function:

```
ease = 1.0 - pow(1.0 - t, 3.0)
```

This function accelerates quickly at the start and decelerates smoothly at the end, giving the PiP window the feel of a spring-loaded snap rather than a linear slide. The AX write (`AXUIElementSetAttributeValue(kAXPositionAttribute)`) and the border overlay update happen in the same timer callback, microseconds apart, so the glow border stays locked to the window throughout the animation.

The Mach time API (`mach_absolute_time` + `mach_timebase_info`) is used instead of `Date()` for sub-millisecond accuracy consistent with what game engines use.

### Game coordination

`PipBounceDaemon.toggleGame(_ game: MiniGame)` is the single entry point for starting and stopping game engines. It is always called on the main queue (dispatched from `ControlServer` via `DispatchSemaphore`). The method:

1. Iterates over all 12 game singletons and stops any that are currently active
2. Resets the border tilt and hides the border
3. If the requested game was not already active, calls `game.start(screen:pip:border:)`

This ensures only one game runs at a time and that the dodge timer is free to resume when all games are stopped.

---

## Process Lifecycle

### Installation

`install.sh` is a four-step idempotent installer. It can be re-run safely at any time to update the binary. The diagram below shows the sequence:

```mermaid
%%{init: {'theme': 'dark', 'themeVariables': {'primaryColor': '#0a3520', 'primaryTextColor': '#00ff88', 'primaryBorderColor': '#00ff88', 'lineColor': '#00fff5', 'secondaryColor': '#0a2540', 'tertiaryColor': '#1a0a3e', 'edgeLabelBackground': '#111', 'clusterBkg': '#0d0d14', 'clusterBorder': '#2a2a3a', 'titleColor': '#fafafa', 'nodeTextColor': '#fafafa'}}}%%
flowchart LR
    classDef step fill:#0a3520,stroke:#00ff88,color:#d0ffe8
    classDef detail fill:#0a2540,stroke:#00fff5,color:#d0f4ff

    S1["Step 1\nStop existing daemon"]
    S2["Step 2\nCompile Swift daemon"]
    S3["Step 3\nGenerate extension icons"]
    S4["Step 4\nInstall launchd agent"]

    D1["launchctl bootout\ngui/UID/com.pipbounce.daemon\nor pkill -x pipbounce\nor no-op if not running"]
    D2["swiftc daemon/*.swift Games/*.swift\n-framework Cocoa\n-framework ApplicationServices\n-framework QuartzCore\n-O optimization\nOutput: ~/.pipbounce/pipbounce.app\n          Contents/MacOS/pipbounce\ncodesign: dev cert or ad-hoc --sign -"]
    D3["python3 inline script\nGenerate 16 / 48 / 128 px PNGs\nSaved to extension/icons/\nPure PNG encoder no dependencies"]
    D4["Write com.pipbounce.daemon.plist\nKeepAlive: true\nRunAtLoad: true\nStdout/Stderr to pipbounce.log\nlaunchctl bootstrap gui/UID\nlaunchctl kickstart -k\ntccutil reset Accessibility"]

    S1 --> S2 --> S3 --> S4
    S1 -. detail .-> D1
    S2 -. detail .-> D2
    S3 -. detail .-> D3
    S4 -. detail .-> D4

    class S1,S2,S3,S4 step
    class D1,D2,D3,D4 detail
```

After a successful install, launchd owns the daemon process. `KeepAlive: true` means launchd will restart the process if it exits for any reason, including the `POST /restart` endpoint which calls `exit(0)` after a 100 ms delay.

### Runtime startup and shutdown

The flowchart below covers the full lifecycle from the moment launchd executes the binary through to a clean SIGTERM shutdown.

```mermaid
%%{init: {'theme': 'dark', 'themeVariables': {'primaryColor': '#0a2540', 'primaryTextColor': '#00fff5', 'primaryBorderColor': '#00fff5', 'lineColor': '#00ff88', 'secondaryColor': '#1a0a3e', 'tertiaryColor': '#0a3520', 'edgeLabelBackground': '#111', 'clusterBkg': '#0d0d14', 'clusterBorder': '#2a2a3a', 'titleColor': '#fafafa', 'nodeTextColor': '#fafafa'}}}%%
flowchart TD
    classDef boot fill:#0a2540,stroke:#00fff5,color:#d0f4ff
    classDef run fill:#0a3520,stroke:#00ff88,color:#d0ffe8
    classDef event fill:#3a0a15,stroke:#ff4d6d,color:#ffd0d8
    classDef hotkey fill:#1a0a3e,stroke:#b44dff,color:#e0d0ff

    LCH["launchd executes binary\n~/.pipbounce/pipbounce.app\n  Contents/MacOS/pipbounce"] --> UB["setbuf stdout nil\nsetbuf stderr nil\nUnbuffered for launchd log capture"]
    UB --> KE["killExisting()\nRead ~/.pipbounce/pipbounce.pid\nSIGTERM old PID if different from getpid()\nusleep 300ms"]
    KE --> WP["writePid()\nCreate ~/.pipbounce/ directory\nWrite getpid() atomically"]
    WP --> NA["NSApplication.shared\nInitialize Cocoa event loop infrastructure"]
    NA --> CS["ControlServer.start()\nCreate AF_INET SOCK_STREAM socket\nSO_REUSEADDR\nBind 127.0.0.1:51789\nlisten(5)\nAccept loop on DispatchQueue.global(.utility)"]
    CS --> DS["PipBounceDaemon.start()\nCheck AXIsProcessTrusted()\ninstallHotkey()\nSchedule Timer 1/60s on main RunLoop"]

    subgraph HKS["Global Hotkey (CGEvent tap)"]
        HK1["CGEvent.tapCreate\ncgSessionEventTap headInsertEventTap\nkeyDown event mask"]
        HK2{"keyCode == hotkeyCode\nAND flags == hotkeyFlags?"}
        HK3["settings.enabled.toggle()\nReturn nil — event consumed"]
        HK4["Unmanaged.passRetained\nEvent forwarded unchanged"]
        HK1 --> HK2
        HK2 -->|"match"| HK3
        HK2 -->|"no match"| HK4
    end

    DS --> HK1
    DS --> SIG["Register signal handlers\nsignal SIGINT  { cleanup(); exit(0) }\nsignal SIGTERM { cleanup(); exit(0) }"]
    SIG --> RL["RunLoop.main.run()\nBlock forever\nDrives timer + CGEvent tap source"]

    RL -->|"every 1/60s"| TICK["PipBounceDaemon.tick()\nMouse poll + PiP discovery\nDodge logic"]
    RL -->|"HTTP request arrives"| REQ["ControlServer.handleClient(fd)\nParse HTTP request\nRoute to handler\nWrite JSON response"]
    RL -->|"SIGTERM or SIGINT"| SHUT["cleanup()\nRemove ~/.pipbounce/pipbounce.pid\nexit(0)"]
    SHUT --> LCD["launchd KeepAlive\nRestarts process automatically\nif unexpected exit or /restart"]

    class LCH,UB,KE,WP,NA,CS,DS boot
    class RL,TICK,REQ run
    class SHUT,LCD event
    class HK1,HK2,HK3,HK4 hotkey
```

### File system layout

After installation the following files are created. The daemon binary and PID file live under `~/.pipbounce/`; the launchd plist lives in the standard user LaunchAgents directory.

```
~/.pipbounce/
├── pipbounce.app/
│   ├── Contents/
│   │   ├── Info.plist              LSUIElement=true, CFBundleIdentifier=com.pipbounce.daemon
│   │   └── MacOS/
│   │       └── pipbounce           Compiled binary (codesigned)
├── pipbounce.pid                   Current daemon PID (removed on clean exit)
└── pipbounce.log                   Stdout + stderr captured by launchd

~/Library/LaunchAgents/
└── com.pipbounce.daemon.plist      KeepAlive + RunAtLoad, points to binary above
```

### Permissions required

The daemon requires two macOS permissions that must be granted manually after installation:

| Permission | Why it is needed | Where to grant |
|------------|-----------------|---------------|
| Accessibility | `AXUIElement` API — required to read and write PiP window position and enumerate Chrome's windows | System Settings → Privacy & Security → Accessibility |
| (optional) Screen Recording | Required by some games that need `CGWindowListCopyWindowInfo` with image data | System Settings → Privacy & Security → Screen Recording |

The installer calls `tccutil reset Accessibility com.pipbounce.daemon` to clear any stale grant for a previous binary hash, prompting macOS to re-request the permission for the newly compiled binary.

---

## Source file map

```
pipbounce/
├── install.sh                       4-step build + install + launchd setup
├── README.md
├── extension/                       Chrome MV3 Extension
│   ├── manifest.json                permissions: scripting, activeTab, tabs
│   ├── popup.html                   320px dark zinc UI
│   ├── popup.js                     Settings controller, game toggles, status polling
│   ├── background.js                Alt+P command handler
│   ├── content.js                   Find largest video, toggle PiP
│   ├── autopip.js                   mediaSession auto-PiP on tab switch
│   ├── icons.js                     SVG icon definitions for game cards
│   └── icons/                       Generated 16/48/128px PNGs
└── daemon/                          Swift source (compiled by swiftc)
    ├── main.swift                   Entry: PID lock, signals, NSApplication, RunLoop
    ├── DodgeDaemon.swift            1/60s tick, CGEvent mouse, dodge animation
    ├── ControlServer.swift          BSD socket HTTP :51789, route dispatch
    ├── PipDiscovery.swift           AXUIElement + CGWindowList PiP detection
    ├── ScreenGeometry.swift         Screen frame conversion + farthest corner math
    ├── Settings.swift               Config singleton (in-memory, not persisted)
    ├── Hotkey.swift                 CGEvent tap for global hotkey
    ├── RGBBorder.swift              Conic gradient border + burst geometry
    ├── MiniGame.swift               Protocol: active, lastBounds, start(), stop()
    └── Games/
        ├── GameBase.swift           Abstract base: Mach timing, timer, score overlay, PiP restore
        ├── PongGame.swift
        ├── FlappyGame.swift
        ├── SnakeGame.swift
        ├── BounceGame.swift
        ├── BreakoutGame.swift
        ├── InvadersGame.swift
        ├── FroggerGame.swift
        ├── RunnerGame.swift
        ├── AsteroidsGame.swift
        ├── CursorHuntGame.swift
        ├── DoodleJumpGame.swift
        └── PacManGame.swift
```
