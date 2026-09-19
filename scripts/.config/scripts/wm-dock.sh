#!/bin/dash

export DISPLAY=:0
export XAUTHORITY="$HOME/.Xauthority"

POSFILE="$HOME/.config/wm-dock/positions.conf"

mkdir -p "$(dirname "$POSFILE")"

# ==================================================
# APPS
#
# NAME         INSTANCE       CLASS       COMMAND
# ==================================================

APPS='
wmbatteries  wmbatteries    DockApp      wmbatteries
wmnetload    wmnetload      Wmnetload    wmnetload -w -i auto -u 1
wmmemload    wmmemload      DockApp      wmmemload
wmcpuload    wmcpuload      DockApp      wmcpuload
wmclockmon   wmclockmon     DockApp      wmclockmon
WMmp         WMmp           DockApp      MPD_HOST=127.0.0.1 MPD_PORT=6601 WMmp
'

# ==================================================
# Find window
# ==================================================

find_window() {
  INSTANCE="$1"
  CLASS="$2"

  wmctrl -lx | awk \
    -v wanted="$INSTANCE.$CLASS" \
    '$3 == wanted {print $1; exit}'
}

# ==================================================
# Get saved position
# ==================================================

get_position() {
  NAME="$1"

  grep "^$NAME|" "$POSFILE" 2>/dev/null |
    head -n1 |
    cut -d'|' -f2-3 |
    tr '|' ' '
}

# ==================================================
# Start application
# ==================================================

start_app() {
  COMMAND="$1"

  sh -c "$COMMAND" >/dev/null 2>&1 &
}

# ==================================================
# Position window
#
# IMPORTANT:
# This ONLY reads positions.
# It NEVER saves or changes positions.conf.
# ==================================================

position_window() {
  ID="$1"
  NAME="$2"

  SAVED=$(get_position "$NAME")

  if [ -z "$SAVED" ]; then
    echo "WARNING: No saved position for $NAME"
    return
  fi

  X=$(echo "$SAVED" | awk '{print $1}')
  Y=$(echo "$SAVED" | awk '{print $2}')

  wmctrl -i -r "$ID" -e "0,$X,$Y,64,64"
}

# ==================================================
# Kill existing dockapps
# ==================================================

echo "$APPS" |
  while read -r NAME INSTANCE CLASS COMMAND; do
    [ -z "$NAME" ] && continue

    pkill -x "$INSTANCE" 2>/dev/null
  done

sleep 0.3

# ==================================================
# Start dockapps
# ==================================================

echo "$APPS" |
  while read -r NAME INSTANCE CLASS COMMAND; do
    [ -z "$NAME" ] && continue

    start_app "$COMMAND"
  done

# ==================================================
# Wait for windows and position them
# ==================================================

echo "$APPS" |
  while read -r NAME INSTANCE CLASS COMMAND; do
    [ -z "$NAME" ] && continue

    ID=""

    # Give each application up to 2 seconds to appear
    i=0
    while [ "$i" -lt 20 ]; do
      ID=$(find_window "$INSTANCE" "$CLASS")

      [ -n "$ID" ] && break

      sleep 0.1
      i=$((i + 1))
    done

    if [ -n "$ID" ]; then
      position_window "$ID" "$NAME"
    else
      echo "WARNING: Could not find $NAME"
    fi
  done
