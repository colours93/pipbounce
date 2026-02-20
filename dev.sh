#!/bin/bash
set -euo pipefail

# Fast dev rebuild: compile + restart. Skips icons, signing, launchd setup.
# Usage: bash dev.sh

DAEMON_DIR="$(cd "$(dirname "$0")" && pwd)/daemon"
APP_BUNDLE="$HOME/.xpip/xpip.app"
BINARY="$HOME/.xpip/xpip.app/Contents/MacOS/xpip"
LABEL="com.xpip.daemon"

SWIFT_FILES=("$DAEMON_DIR"/*.swift "$DAEMON_DIR"/Games/*.swift "$DAEMON_DIR"/Games/Sprites/*.swift)
mkdir -p "$APP_BUNDLE/Contents/MacOS"

printf "Compiling %d files..." "${#SWIFT_FILES[@]}"
swiftc "${SWIFT_FILES[@]}" \
    -o "$BINARY" \
    -framework Cocoa \
    -framework ApplicationServices \
    -framework QuartzCore \
    -O

# Use stable dev cert to preserve Accessibility TCC grant
SIGN_ID=$(security find-identity -v -p codesigning | grep -E "XPip Dev|xpip Dev|pipbounce Dev" | head -1 | awk -F'"' '{print $2}' || true)
if [ -n "$SIGN_ID" ]; then
    codesign --force --sign "$SIGN_ID" "$APP_BUNDLE" 2>/dev/null
else
    codesign --force --sign - "$APP_BUNDLE" 2>/dev/null
fi

printf " done.\n"

# KeepAlive restarts it automatically after kill
launchctl kickstart -k "gui/$(id -u)/$LABEL" 2>/dev/null || {
    # Fallback if not bootstrapped yet
    echo "Not bootstrapped — run install.sh first"
    exit 1
}

echo "Restarted. tail -f ~/.xpip/xpip.log"
