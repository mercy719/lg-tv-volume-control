#!/bin/bash
# Remove the LaunchAgents, daemon files and Hammerspoon module (init.lua line is left for you to delete).
LABEL="io.github.lgtv-volumed"
WATCHDOG_LABEL="$LABEL.watchdog"
launchctl bootout "gui/$(id -u)/$WATCHDOG_LABEL" 2>/dev/null
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null
rm -f "$HOME/Library/LaunchAgents/$LABEL.plist" \
  "$HOME/Library/LaunchAgents/$WATCHDOG_LABEL.plist" \
  "$HOME/.hammerspoon/lgtv_volume.lua"
rm -rf "$HOME/.local/share/lgtv-volumed"
echo 'Removed. Delete the require("lgtv_volume").start() line from ~/.hammerspoon/init.lua.'
