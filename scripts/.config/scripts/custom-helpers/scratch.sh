#!/usr/bin/env bash
# Ephemeral scratch pad.
# Opens a small st terminal in the top-right corner.
# Type immediately — no editor needed.
# ctrl+c clears, closing wipes everything.

DISPLAY="${DISPLAY:-:0}"

# Get screen width to position top-right
SCREEN_W=$(xrandr --query | grep '\*' | awk '{print $1}' | cut -dx -f1 | head -1)
SCREEN_W="${SCREEN_W:-1920}"

WIN_W=400
WIN_H=300
MARGIN=20

X=$(( SCREEN_W - WIN_W - MARGIN ))
Y=$MARGIN

st \
    -c "scratchpad" \
    -n "scratchpad" \
    -T "Scratch" \
    -g "50x15+${X}+${Y}" \
    -e bash --norc --noprofile -c '
        SCRATCH="/tmp/scratchpad.txt"
        > "$SCRATCH"

        redraw() {
            clear
            echo " scratch  —  ctrl+c: clear"
            echo "─────────────────────────────────────────────────"
            cat "$SCRATCH" 2>/dev/null
        }

        # ctrl+c clears
        trap "{ > \"$SCRATCH\"; redraw; }" INT

        # on exit wipe
        trap "rm -f \"$SCRATCH\"" EXIT

        redraw

        # Read character by character and append to file
        while IFS= read -r -s -n1 char; do
            if [[ "$char" == "" ]]; then
                # Enter key — newline
                echo "" >> "$SCRATCH"
            elif [[ "$char" == $'"'"'\177'"'"' || "$char" == $'"'"'\010'"'"' ]]; then
                # Backspace — remove last character
                content=$(cat "$SCRATCH")
                content="${content%?}"
                printf "%s" "$content" > "$SCRATCH"
            else
                printf "%s" "$char" >> "$SCRATCH"
            fi
            redraw
        done
    '
