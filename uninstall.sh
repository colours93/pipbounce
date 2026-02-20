#!/bin/bash
# XPip standalone uninstaller
# Use this if the daemon isn't running or you can't reach the menu bar icon.

set -euo pipefail

LABELS=("com.xpip.daemon" "com.pipbounce.daemon")
INSTALL_DIRS=("$HOME/.xpip" "$HOME/.pipbounce")

echo "Uninstalling XPip..."

# Stop daemon(s) and remove launchd plists
for label in "${LABELS[@]}"; do
  launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
  rm -f "$HOME/Library/LaunchAgents/$label.plist"
done

# Remove install directories
for dir in "${INSTALL_DIRS[@]}"; do
  rm -rf "$dir"
done

echo "XPip uninstalled."
echo ""
echo "Note: Remove the Chrome extension manually from chrome://extensions"
