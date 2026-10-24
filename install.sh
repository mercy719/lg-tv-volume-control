#!/bin/bash
# Install lgtv_volumed, its watchdog and the Hammerspoon module.
#   ./install.sh 192.168.1.50
set -euo pipefail

TV_IP="${1:-${LGTV_IP:-}}"
[ -n "$TV_IP" ] || { echo "usage: $0 <tv-ip>"; exit 1; }

REPO="$(cd "$(dirname "$0")" && pwd)"
DATA="$HOME/.local/share/lgtv-volumed"
LABEL="io.github.lgtv-volumed"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG="$HOME/Library/Logs/lgtv-volumed.log"
WATCHDOG_LABEL="$LABEL.watchdog"
WATCHDOG_PLIST="$HOME/Library/LaunchAgents/$WATCHDOG_LABEL.plist"
WATCHDOG_LOG="$HOME/Library/Logs/lgtv-volumed-watchdog.log"

mkdir -p "$DATA"
cp "$REPO/lgtv_volumed.py" "$DATA/"
cp "$REPO/watchdog.sh" "$DATA/"
chmod 755 "$DATA/watchdog.sh"

# The venv must be based on Apple's /usr/bin/python3: other Python builds (uv, pyenv, Homebrew)
# are blocked by the macOS "Local Network" permission and fail with "Errno 65 No route to host".
if [ ! -x "$DATA/venv/bin/python" ]; then
  /usr/bin/python3 -m venv "$DATA/venv"
fi
"$DATA/venv/bin/pip" install -q --upgrade pip bscpylgtv

# Proxy variables make bscpylgtv's websocket fail with InvalidProxyMessage
env -u http_proxy -u https_proxy -u all_proxy -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY \
  "$DATA/venv/bin/python" "$DATA/lgtv_volumed.py" pair --tv "$TV_IP"

cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array>
    <string>$DATA/venv/bin/python</string>
    <string>$DATA/lgtv_volumed.py</string>
    <string>serve</string>
    <string>--tv</string><string>$TV_IP</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>$LOG</string>
  <key>StandardErrorPath</key><string>$LOG</string>
</dict></plist>
EOF
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"

cat > "$WATCHDOG_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$WATCHDOG_LABEL</string>
  <key>ProgramArguments</key><array>
    <string>/bin/bash</string>
    <string>$DATA/watchdog.sh</string>
    <string>$TV_IP</string>
    <string>$LABEL</string>
    <string>http://127.0.0.1:18765/status</string>
    <string>$DATA/watchdog</string>
  </array>
  <key>StartInterval</key><integer>15</integer>
  <key>RunAtLoad</key><true/>
  <key>ProcessType</key><string>Background</string>
  <key>StandardOutPath</key><string>$WATCHDOG_LOG</string>
  <key>StandardErrorPath</key><string>$WATCHDOG_LOG</string>
</dict></plist>
EOF
launchctl bootout "gui/$(id -u)/$WATCHDOG_LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$WATCHDOG_PLIST"

mkdir -p "$HOME/.hammerspoon"
cp "$REPO/hammerspoon/lgtv_volume.lua" "$HOME/.hammerspoon/"
if ! grep -q 'lgtv_volume' "$HOME/.hammerspoon/init.lua" 2>/dev/null; then
  echo 'require("lgtv_volume").start()' >> "$HOME/.hammerspoon/init.lua"
fi

sleep 2
echo "Daemon status: $(curl -s --noproxy '*' http://127.0.0.1:18765/status || echo 'not responding, see '"$LOG")"
echo "Done. Reload Hammerspoon config (or restart Hammerspoon) to activate the volume keys."
