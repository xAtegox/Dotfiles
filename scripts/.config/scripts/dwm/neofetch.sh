#!/bin/bash
kitty --title "Welcome" \
  --override initial_window_width=670 \
  --override initial_window_height=450 \
  --override remember_window_size=no \
  -e bash -c "neofetch; read -n1" &

sleep 0.3
xdotool search --name "Welcome" windowmove 30 40
