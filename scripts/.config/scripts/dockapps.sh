#!/bin/sh

# Window Maker dockapps for dwm

# kill old instances
pkill wmclock
pkill wmcpuload
pkill wmbattery
pkill wmwifi
pkill wmgtemp

sleep 0.1

# start dockapps
wmclock &
wmcpuload -bw &
wmbattery &
wmwifi -bw &
wmgtemp &

# screen size
SCREEN_W=$(xdpyinfo | awk '/dimensions/{print $2}' | cut -dx -f1)

# Dockapps are 64x64, so this puts their RIGHT edge
# exactly against the RIGHT edge of the screen.
X=$((SCREEN_W - 64))

Y=50
GAP=70

move_window() {
  NAME="$1"
  POS="$2"

  ID=""

  # Wait up to 2 seconds for the window
  for i in $(seq 1 20); do
    ID=$(xdotool search --name "$NAME" 2>/dev/null | head -n1)

    [ -n "$ID" ] && break

    sleep 0.1
  done

  if [ -n "$ID" ]; then
    xdotool windowmove "$ID" "$X" "$POS"
  fi
}

# place widgets
move_window "wmclock" "$Y"
move_window "wmcpuload" "$((Y + GAP))"
move_window "wmbattery" "$((Y + GAP * 2))"
move_window "wmwifi" "$((Y + GAP * 3))"
move_window "wmgtemp" "$((Y + GAP * 4))"
