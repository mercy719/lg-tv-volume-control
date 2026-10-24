#!/bin/bash
# Restart lgtv-volumed when the TV is reachable but its local API stays unhealthy.
# Usage: watchdog.sh TV_IP [SERVICE_LABEL [API_URL [STATE_DIR]]]
set -u

TV_IP="${1:-${LGTV_IP:-}}"
SERVICE_LABEL="${2:-${LGTV_SERVICE_LABEL:-io.github.lgtv-volumed}}"
API_URL="${3:-${LGTV_API_URL:-http://127.0.0.1:18765/status}}"
STATE_DIR="${4:-${LGTV_WATCHDOG_STATE_DIR:-$HOME/.local/share/lgtv-volumed/watchdog}}"
FAILURES_FILE="$STATE_DIR/consecutive_failures"
LAST_RESTART_FILE="$STATE_DIR/last_restart"
LOG_FILE="$STATE_DIR/watchdog.log"
NOW=$(/bin/date +%s)

if [ -z "$TV_IP" ]; then
  echo "usage: $0 TV_IP [SERVICE_LABEL [API_URL [STATE_DIR]]]" >&2
  exit 64
fi

mkdir -p "$STATE_DIR"

# Probe from a separate process. Do not make the daemon reconnect and log errors
# every interval while the TV is off or unreachable.
if ! /usr/bin/nc -z -G 2 "$TV_IP" 3000 >/dev/null 2>&1 && \
   ! /usr/bin/nc -z -G 2 "$TV_IP" 3001 >/dev/null 2>&1; then
  /bin/rm -f "$FAILURES_FILE"
  exit 0
fi

unset http_proxy https_proxy all_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY
HTTP_CODE=$(/usr/bin/curl --noproxy '*' -sS --max-time 8 -o /dev/null \
  -w '%{http_code}' "$API_URL" 2>/dev/null || true)

if [ "$HTTP_CODE" = "200" ]; then
  /bin/rm -f "$FAILURES_FILE"
  exit 0
fi

case "$HTTP_CODE" in
  000|503) ;;
  *) /bin/rm -f "$FAILURES_FILE"; exit 0 ;;
esac

FAILURES=0
if [ -f "$FAILURES_FILE" ]; then
  OLD_FAILURES=$(/bin/cat "$FAILURES_FILE" 2>/dev/null || echo 0)
  case "$OLD_FAILURES" in ''|*[!0-9]*) FAILURES=0 ;; *) FAILURES=$OLD_FAILURES ;; esac
fi
FAILURES=$((FAILURES + 1))
echo "$FAILURES" > "$FAILURES_FILE"

# The supplied LaunchAgent runs every 15 seconds: require 30 seconds of failure.
[ "$FAILURES" -ge 2 ] || exit 0

if [ -f "$LAST_RESTART_FILE" ]; then
  LAST_RESTART=$(/bin/cat "$LAST_RESTART_FILE" 2>/dev/null || echo 0)
  case "$LAST_RESTART" in ''|*[!0-9]*) LAST_RESTART=0 ;; esac
  if [ $((NOW - LAST_RESTART)) -lt 300 ]; then
    exit 0
  fi
fi

echo "$(/bin/date '+%F %T') TV ${TV_IP} is reachable; API failed ${FAILURES} times (HTTP ${HTTP_CODE})" >> "$LOG_FILE"

if [ "${DRY_RUN:-0}" = "1" ]; then
  echo "$(/bin/date '+%F %T') DRY_RUN: would restart ${SERVICE_LABEL}" >> "$LOG_FILE"
  exit 0
fi

# Enter cooldown only after a successful kickstart; otherwise retry next time.
if ! /bin/launchctl kickstart -k "gui/$(/usr/bin/id -u)/$SERVICE_LABEL" >/dev/null 2>&1; then
  echo "$(/bin/date '+%F %T') Failed to restart ${SERVICE_LABEL}" >> "$LOG_FILE"
  exit 1
fi

echo "$NOW" > "$LAST_RESTART_FILE"
/bin/rm -f "$FAILURES_FILE"

RECOVERED=0
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
  /bin/sleep 1
  CODE=$(/usr/bin/curl --noproxy '*' -sS --max-time 5 -o /dev/null \
    -w '%{http_code}' "$API_URL" 2>/dev/null || true)
  if [ "$CODE" = "200" ]; then
    RECOVERED=1
    break
  fi
done

if [ "$RECOVERED" = "1" ]; then
  echo "$(/bin/date '+%F %T') Restarted ${SERVICE_LABEL}; volume control recovered" >> "$LOG_FILE"
  exit 0
else
  echo "$(/bin/date '+%F %T') Restarted ${SERVICE_LABEL}; API is still unhealthy (last HTTP ${CODE:-000})" >> "$LOG_FILE"
  exit 1
fi
