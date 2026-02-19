#!/bin/bash
set -euo pipefail

# ---------------------------------------------------------------------------
#  pipbounce Installer
#  Compiles the Swift daemon, generates extension icons, and prints
#  post-install instructions.
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DAEMON_DIR="$SCRIPT_DIR/daemon"
EXTENSION_DIR="$SCRIPT_DIR/extension"
INSTALL_DIR="$HOME/.pipbounce"
APP_BUNDLE="$INSTALL_DIR/pipbounce.app"
BINARY="$APP_BUNDLE/Contents/MacOS/pipbounce"
PORT=51789

# ---------------------------------------------------------------------------
#  Helpers
# ---------------------------------------------------------------------------

log()      { printf "[%s] %s\n" "$1" "$2"; }
log_ok()   { printf "      %s\n" "$1"; }
bail()     { printf "ERROR: %s\n" "$1" >&2; exit 1; }
section()  { printf "\n--- %s %s\n" "$1" "$(printf '%*s' $((60 - ${#1})) '' | tr ' ' '-')"; }

# ---------------------------------------------------------------------------
#  Pre-flight checks
# ---------------------------------------------------------------------------

section "Pre-flight"

SWIFT_FILES=("$DAEMON_DIR"/*.swift "$DAEMON_DIR"/Games/*.swift)
if [ ${#SWIFT_FILES[@]} -eq 0 ]; then
    bail "No Swift source files found in $DAEMON_DIR"
fi

if ! command -v swiftc >/dev/null 2>&1; then
    bail "swiftc not found. Install Xcode or the Command Line Tools first."
fi

if ! command -v python3 >/dev/null 2>&1; then
    bail "python3 not found. Install Python 3 first."
fi

log "OK" "All prerequisites met."

# ---------------------------------------------------------------------------
#  Step 1 -- Stop any running pipbounce process
# ---------------------------------------------------------------------------

section "Step 1/4: Stop existing daemon"

PLIST_LABEL="com.pipbounce.daemon"
PLIST_PATH="$HOME/Library/LaunchAgents/$PLIST_LABEL.plist"

if launchctl list "$PLIST_LABEL" >/dev/null 2>&1; then
    launchctl bootout "gui/$(id -u)/$PLIST_LABEL" 2>/dev/null || true
    sleep 0.5
    log "1/4" "Stopped existing launchd agent."
elif pgrep -x pipbounce >/dev/null 2>&1; then
    pkill -x pipbounce && sleep 0.5
    log "1/4" "Killed running pipbounce process."
else
    log "1/4" "No running pipbounce process found. Continuing."
fi

# ---------------------------------------------------------------------------
#  Step 2 -- Compile the Swift daemon
# ---------------------------------------------------------------------------

section "Step 2/4: Compile daemon"

mkdir -p "$APP_BUNDLE/Contents/MacOS"

cat > "$APP_BUNDLE/Contents/Info.plist" << 'INFOPLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.pipbounce.daemon</string>
    <key>CFBundleName</key>
    <string>pipbounce</string>
    <key>CFBundleExecutable</key>
    <string>pipbounce</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
INFOPLIST

log "2/4" "Compiling ${#SWIFT_FILES[@]} Swift files ..."

swiftc "${SWIFT_FILES[@]}" \
    -o "$BINARY" \
    -framework Cocoa \
    -framework ApplicationServices \
    -framework QuartzCore \
    -O

chmod +x "$BINARY"
SIGN_ID=$(security find-identity -v -p codesigning | grep -E "pipbounce Dev|xpip Dev" | head -1 | awk -F'"' '{print $2}' || true)
if [ -n "$SIGN_ID" ]; then
    codesign --force --sign "$SIGN_ID" "$APP_BUNDLE"
    log_ok "Signed with stable identity: $SIGN_ID"
else
    codesign --force --sign - "$APP_BUNDLE"
    log_ok "Signed ad-hoc (run install once to create stable cert)"
fi
log_ok "Built $APP_BUNDLE"

# ---------------------------------------------------------------------------
#  Step 3 -- Generate extension icons
# ---------------------------------------------------------------------------

section "Step 3/4: Generate icons"

SCRIPT_DIR="$SCRIPT_DIR" python3 - << 'PYEOF'
import struct, zlib, os

def create_icon(size):
    pixels = []
    pad = max(1, size // 8)
    for y in range(size):
        row = []
        for x in range(size):
            in_bg = pad <= x < size - pad and pad <= y < size - pad
            main_r, main_b = int(size * 0.65), int(size * 0.65)
            in_main = pad + 1 <= x <= main_r and pad + 1 <= y <= main_b
            pip_l, pip_t = int(size * 0.55), int(size * 0.55)
            in_pip = pip_l <= x <= size - pad - 1 and pip_t <= y <= size - pad - 1
            arrow_cx, arrow_cy = int(size * 0.42), int(size * 0.78)
            in_arrow = (abs(x - arrow_cx) + abs(y - arrow_cy)) <= max(2, size // 10)
            if in_pip:
                row.extend([100, 180, 255, 255])
            elif in_arrow:
                row.extend([100, 180, 255, 200])
            elif in_main:
                row.extend([40, 40, 50, 255])
            elif in_bg:
                row.extend([60, 60, 75, 255])
            else:
                row.extend([0, 0, 0, 0])
        pixels.append(bytes(row))
    def chunk(ctype, data):
        c = ctype + data
        return struct.pack('>I', len(data)) + c + struct.pack('>I', zlib.crc32(c) & 0xffffffff)
    sig = b'\x89PNG\r\n\x1a\n'
    ihdr = struct.pack('>IIBBBBB', size, size, 8, 6, 0, 0, 0)
    raw = b''
    for r in pixels:
        raw += b'\x00' + r
    return sig + chunk(b'IHDR', ihdr) + chunk(b'IDAT', zlib.compress(raw)) + chunk(b'IEND', b'')

icon_dir = os.path.join(os.environ.get('SCRIPT_DIR', '.'), 'extension', 'icons')
os.makedirs(icon_dir, exist_ok=True)
for s in [16, 48, 128]:
    with open(os.path.join(icon_dir, f'icon{s}.png'), 'wb') as f:
        f.write(create_icon(s))
    print(f"      icon{s}.png")
PYEOF

# ---------------------------------------------------------------------------
#  Step 4 -- Install and start launchd agent
# ---------------------------------------------------------------------------

section "Step 4/4: Install launchd agent"

mkdir -p "$HOME/Library/LaunchAgents"

cat > "$PLIST_PATH" << PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$PLIST_LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$BINARY</string>
    </array>
    <key>KeepAlive</key>
    <true/>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$INSTALL_DIR/pipbounce.log</string>
    <key>StandardErrorPath</key>
    <string>$INSTALL_DIR/pipbounce.log</string>
</dict>
</plist>
PLISTEOF

# Skip TCC reset — preserve existing Accessibility approval across reinstalls.
# The stable code signature (or ad-hoc with same bundle ID) keeps the grant valid.

launchctl bootstrap "gui/$(id -u)" "$PLIST_PATH" 2>/dev/null || true
launchctl kickstart -k "gui/$(id -u)/$PLIST_LABEL" 2>/dev/null || true

sleep 0.5

if launchctl list "$PLIST_LABEL" >/dev/null 2>&1; then
    log "4/4" "Daemon installed and running via launchd."
    log_ok "It will auto-start on login and restart when triggered by the extension."
else
    log "4/4" "Launchd agent installed. Start manually: launchctl load $PLIST_PATH"
fi

# Open System Settings to Accessibility pane so user can grant permission
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility" 2>/dev/null || true

# ---------------------------------------------------------------------------
#  Done -- print setup instructions
# ---------------------------------------------------------------------------

printf "\n"
printf "===================================================================\n"
printf "  Installation complete. Daemon is running.\n"
printf "===================================================================\n"
printf "\n"
printf "NEXT STEPS\n"
printf "\n"
printf "  1. Grant Accessibility permission (if not already done)\n"
printf "     System Settings -> Privacy & Security -> Accessibility\n"
printf "     Click \"+\" and add:  %s\n" "$APP_BUNDLE"
printf "\n"
printf "  2. Load the Chrome extension\n"
printf "     a. Open  chrome://extensions\n"
printf "     b. Enable \"Developer mode\" (top-right toggle)\n"
printf "     c. Click \"Load unpacked\" and select:\n"
printf "        %s\n" "$EXTENSION_DIR"
printf "\n"
printf "  The daemon starts automatically on login and restarts each\n"
printf "  time you open the extension popup. Logs: %s/pipbounce.log\n" "$INSTALL_DIR"
printf "\n"
printf "  To stop:  launchctl bootout gui/\$(id -u)/com.pipbounce.daemon\n"
printf "\n"
