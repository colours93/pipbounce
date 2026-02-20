# XPip

macOS daemon + Chrome extension. PiP windows dodge your cursor and become retro arcade machines.

## Build & Install

### Dev rebuild (daily driver)

```bash
bash dev.sh
```

Compile + sign + restart. No icons, no launchd setup. Uses stable `XPip Dev` cert to preserve Accessibility TCC grant. No password prompts.

### Full install

```bash
bash install.sh
```

Full build pipeline: stop daemon, compile, sign with hardened runtime, generate extension icons, install launchd agent. Use this on first setup or after changing launchd config.

### Distribution

```bash
# Notarize (requires Apple Developer ID)
NOTARIZE=1 APPLE_ID=... TEAM_ID=... APP_PASSWORD=... bash install.sh

# Build .dmg
DMG=1 bash install.sh
```

The binary lives at `~/.xpip/xpip.app/Contents/MacOS/xpip`.

## Accessibility Permission

The daemon needs Accessibility access to move PiP windows. On first launch without permission, an onboarding window guides the user through granting it. It auto-detects when permission is granted and closes itself.

Manual path: System Settings > Privacy & Security > Accessibility > add `~/.xpip/xpip.app`.

Without this, AXUIElement calls fail silently and nothing moves.

## Menu Bar

The daemon shows an `NSStatusItem` in the macOS menu bar. From it you can:
- Toggle dodge on/off, glow on/off
- Launch any of the 14 game modes
- See Accessibility permission status
- Restart the daemon, uninstall, or quit

The icon dims when dodge is disabled. `LSUIElement` stays `true` (no dock icon).

## Architecture

- `daemon/` — Pure Swift, no Package.swift, no Xcode project. Compiled directly with `swiftc`.
- `daemon/main.swift` — Entry point. Sets up `NSApplication`, `ControlServer`, `XPipDaemon`, `MenuBarController`.
- `daemon/MenuBarController.swift` — NSStatusItem menu bar icon with settings toggles, game launcher, uninstall.
- `daemon/OnboardingWindow.swift` — First-launch Accessibility permission guide window.
- `daemon/Uninstaller.swift` — Confirmation dialog + cleanup (bootout launchd, remove plist, remove ~/.xpip).
- `daemon/DodgeDaemon.swift` — Core dodge logic, PiP window tracking, animation, game toggling.
- `daemon/Settings.swift` — JSON settings at `~/.xpip/settings.json`.
- `daemon/ControlServer.swift` — HTTP API on port 51789 for Chrome extension communication.
- `daemon/SoundKit.swift` — 5 SFX → NSSound mapping, preloaded at startup.
- `daemon/Games/` — 14 game modes (13 games, Bounce has 2 modes), all subclass `GameBase` in `GameBase.swift`
- `daemon/Games/GameBase.swift` — Shared game infrastructure: `GameState` enum, collision helpers, overlays, score labels, pip movement, border sync, pixel art rendering, `LayerPool` integration
- `daemon/Games/LayerPool.swift` — CALayer recycler (dequeue/enqueue/drain) to eliminate allocation churn
- `daemon/Games/Sprites/` — 10 extracted pixel-art sprite enum files (pre-baked CGImage constants)
- `daemon/xpip.entitlements` — Hardened runtime entitlements (no sandbox, Apple Events).
- `extension/` — Chrome extension (popup UI, background script, content script)
- `install.sh` — Full build system with signing, notarization, dmg packaging.
- `dev.sh` — Fast dev rebuild: compile + sign + restart.
- `uninstall.sh` — Standalone uninstall script (for when daemon can't be reached).
- `docs/` — Full documentation: ARCHITECTURE.md, GAME-ENGINE.md, DODGE-SYSTEM.md, RGB-BORDER.md, API-REFERENCE.md

## Key Conventions

- No external dependencies. Only system frameworks: Cocoa, ApplicationServices, QuartzCore.
- Pixel art sprites live in `daemon/Games/Sprites/` as `enum XxxSprites` with static `CGImage?` constants via `GameBase.renderPixelArt([[UInt32]], scale: Int)`.
- Use `GameBase` collision helpers: `rectsCollide()`, `circleHitsRect()`, `distance()`, `pointInRect()`.
- Use `layerPool.dequeue()` / `layerPool.enqueue()` for hot-path CALayer creation/destruction.
- Use `SoundKit.shared.play(.hit)` for sound effects.
- Use `GameState` enum (`.ready`, `.playing`, `.gameOver`) with `triggerGameOver()` / `checkGameOverTimeout()`.
- Games use AX coordinates (Y=0 at top, Y increases downward). Overlay layers use NS/Quartz coords (Y=0 at bottom). Convert with `nsY = screenH - axY - height`.
- `screenH` is the full screen height in points (from `GameBase`).
- All games run on `DispatchSourceTimer` at configurable `timerIntervalMs` (typically 2-8ms).

## Logs

```bash
tail -f ~/.xpip/xpip.log
```

## Stop/Restart/Uninstall

```bash
# Stop
launchctl bootout gui/$(id -u)/com.xpip.daemon

# Restart (dev)
bash dev.sh

# Restart (full)
bash install.sh

# Uninstall (from menu bar or standalone)
bash uninstall.sh
```
