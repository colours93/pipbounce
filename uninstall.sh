#!/bin/bash
# PipBounce standalone uninstaller
# Use this if the daemon isn't running or you can't reach the menu bar icon.

set -euo pipefail

LABEL="com.pipbounce.daemon"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
INSTALL_DIR="$HOME/.pipbounce"

echo "Uninstalling PipBounce..."

# Stop the daemon
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true

# Remove launchd plist
rm -f "$PLIST"

# Remove install directory
rm -rf "$INSTALL_DIR"

echo "PipBounce uninstalled."
echo ""
echo "Note: Remove the Chrome extension manually from chrome://extensions"
