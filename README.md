# xpip

A macOS tool that makes Picture-in-Picture windows dodge your mouse cursor. A Chrome extension triggers PiP for any video on any site, while a native Swift daemon watches your cursor and moves the PiP window out of the way -- unless you approach it from a corner, which lets you interact with playback controls.

## How It Works

The system has two cooperating parts:

1. **Chrome extension** -- Activates PiP on any website using the browser's native `video.requestPictureInPicture()` API. Provides a popup UI for settings and a keyboard shortcut (Alt+P) for toggling PiP. Auto-PiP triggers when you switch tabs while a video is playing.

2. **macOS daemon** (`~/.xpip/xpip`) -- A Swift process that polls the mouse position at 30fps via `CGEvent`, locates the PiP window through the macOS Accessibility API (`AXUIElement`), and decides whether to dodge or allow interaction based on the mouse's entry angle.

**The dodge rule is simple:** if the mouse touches the PiP window from a side edge, the window jumps to the farthest screen corner. If the mouse enters through one of the four corner zones of the PiP window, dodging is suppressed and you can interact normally (play/pause, scrub, close). When the mouse leaves the window, the state resets.

The extension and daemon communicate over HTTP on `localhost:51789`. The daemon exposes a JSON API for reading and writing settings. A PID lock file prevents multiple daemon instances.

## Prerequisites

- macOS (requires Accessibility API and CGEvent)
- Chrome or any Chromium-based browser
- Xcode Command Line Tools (provides the Swift compiler)

Install the command line tools if you don't have them:

```
xcode-select --install
```

## Installation

### 1. Build and install the daemon

```
./install.sh
```

This compiles `xpip.swift` into `~/.xpip/xpip` and generates extension icons.

### 2. Load the Chrome extension

1. Open `chrome://extensions`
2. Enable **Developer mode** (top-right toggle)
3. Click **Load unpacked** and select the `extension/` directory from this repository

### 3. Grant Accessibility permission

The daemon needs Accessibility access to find and move PiP windows.

1. Open **System Settings > Privacy & Security > Accessibility**
2. Add `~/.xpip/xpip` (or the terminal application you run it from)

The daemon will prompt for this permission on first launch if it is not already granted.

### 4. Start the daemon

```
~/.xpip/xpip
```

The daemon runs in the foreground and logs to stdout. It listens on `http://127.0.0.1:51789` for settings changes from the extension.

## Usage

### Triggering PiP

- **Click the extension icon** in the Chrome toolbar -- this opens the popup and automatically activates PiP on the current tab's largest video.
- **Press Alt+P** to toggle PiP without opening the popup.
- **Switch tabs** while a video is playing -- auto-PiP activates via the Media Session API.

PiP works on any site with a standard `<video>` element: YouTube, Vimeo, Twitch, Netflix, and others.

### Dodge behavior

When the PiP window is active and the daemon is running:

- **Side entry** -- Moving the mouse into the PiP from any non-corner edge causes it to jump to the screen corner farthest from the cursor.
- **Corner entry** -- Moving the mouse into the PiP through one of its four corner zones disables dodging, letting you interact with playback controls, the scrub bar, or the close button.
- **Leaving the window** -- Moving the mouse out of the PiP resets the interaction state. The next touch will evaluate entry angle again.

The dodge respects a cooldown period to prevent rapid bouncing between corners.

## Configuration

Click the extension icon to open the settings popup. All changes take effect immediately via the daemon's HTTP API.

| Setting           | Default | Range       | Description                                              |
|-------------------|---------|-------------|----------------------------------------------------------|
| Dodge enabled     | On      | On / Off    | Master toggle for dodge behavior                         |
| Dodge distance    | 200px   | 80--400px   | Reserved; distance threshold for dodge activation        |
| Cooldown          | 0.4s    | 0.1--2.0s   | Minimum time between consecutive dodges                  |
| Screen margin     | 20px    | 5--60px     | Padding from screen edges when positioning the window    |
| Corner safe zone  | 120px   | 40--250px   | Size of each corner entry zone on the PiP window         |

A larger corner safe zone makes it easier to approach the PiP for interaction. A smaller one makes dodging more aggressive.

## Project Structure

```
daemon/xpip.swift        macOS daemon: mouse tracking, window movement, HTTP API
extension/manifest.json      Chrome MV3 extension manifest
extension/background.js      Keyboard shortcut handler (Alt+P)
extension/content.js         PiP toggle logic (finds largest video, enters/exits PiP)
extension/autopip.js         Auto-PiP on tab switch via Media Session API
extension/popup.html         Settings popup UI
extension/popup.js           Settings controller, communicates with daemon API
install.sh                   Compiles the daemon and generates extension icons
```

## Architecture

```
+---------------------+          HTTP (localhost:51789)          +--------------------+
|  Chrome Extension   | <-------------------------------------> |   Swift Daemon     |
|                     |   GET /status                           |                    |
|  popup.js           |   POST /settings {json}                 |  xpip.swift    |
|  background.js      |   POST /toggle                          |                    |
|  content.js         |                                         |  - CGEvent poll    |
|  autopip.js         |                                         |  - AXUIElement     |
+---------------------+                                         |  - Window move     |
        |                                                       +--------------------+
        | video.requestPictureInPicture()                              |
        v                                                              v
+---------------------+                                         +--------------------+
|  Browser PiP Window | <--- Accessibility API (find + move) -- |  macOS WindowServer|
+---------------------+                                         +--------------------+
```

The daemon runs a 30fps timer on the main run loop. Each tick:

1. Reads the current mouse position from `CGEvent`.
2. Enumerates Chrome's windows via `AXUIElement` to find one matching PiP heuristics (title contains "picture in picture", or a small landscape window with a blank title).
3. If the mouse has just entered the PiP bounds, checks whether the entry point falls within a corner zone.
4. Corner entry: sets interaction mode (no dodge). Side entry: computes the farthest screen corner and moves the window there via `AXUIElementSetAttributeValue`.
5. Mouse leaving the PiP resets state.

A PID lock file at `~/.xpip/xpip.pid` ensures only one daemon instance runs. Starting a new instance sends `SIGTERM` to the old one.

## Troubleshooting

**Daemon says "Accessibility permission required"**
Grant permission in System Settings > Privacy & Security > Accessibility. You may need to add your terminal application (Terminal.app, iTerm2, etc.) rather than the daemon binary itself.

**PiP window not detected**
The daemon identifies PiP windows by title ("Picture in Picture" or "Picture-in-Picture") or by heuristics for Document PiP windows (small, landscape, blank title). If your browser localizes the window title differently, detection may fail.

**Extension says "Daemon not running"**
Start the daemon manually with `~/.xpip/xpip`. It must be running for settings sync and status display to work. Dodge behavior depends entirely on the daemon; the extension only handles PiP activation.

## License

MIT
