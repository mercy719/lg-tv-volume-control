#!/bin/bash
# Remove the LaunchAgent, daemon files and Hammerspoon module (init.lua line is left for you to delete).
LABEL="io.github.lgtv-volumed"
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null
rm -f "$HOME/Library/LaunchAgents/$LABEL.plist" "$HOME/.hammerspoon/lgtv_volume.lua"
rm -rf "$HOME/.local/share/lgtv-volumed"
echo 'Removed. Delete the require("lgtv_volume").start() line from ~/.hammerspoon/init.lua.'
