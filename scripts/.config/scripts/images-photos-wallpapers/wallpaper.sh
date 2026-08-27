#!/usr/bin/env bash
# ─────────────────────────────────────────────
# wallpaper picker — atego
# ─────────────────────────────────────────────
WALL_DIR="$HOME/Pictures/wallpaper"
WAL_LAST="$(dirname "$0")/wal_last.txt"
PREVIEW_CACHE="$HOME/.cache/wal_preview_thumbs"
ZEN_THEME_DIR="$HOME/.config/zennotes/themes/wal-theme"
LOADOUTS_DIR="$HOME/.config/wal/loadouts"
mkdir -p "$PREVIEW_CACHE"
mkdir -p "$LOADOUTS_DIR"
SELF="$(realpath "$0")"
# ─────────────────────────────────────────────
# Backends
# ─────────────────────────────────────────────
mapfile -t BACKENDS < <(
  wal --backend 2>/dev/null |
    tail -n +2 |
    sed 's/^ - //' |
    grep -v '^wal$'
)
BACKENDS=(wal "${BACKENDS[@]}")
BACKEND_IDX=0
# ─────────────────────────────────────────────
# Shared fzf styling
# ─────────────────────────────────────────────
FZF_STYLE=(
  --no-sort --reverse --style=full --border=sharp
  --no-scrollbar --padding="0,0" --prompt=" "
  --pointer="▌" --marker="●" --input-label=" "
  --info=right
  --color="bg:-1,bg+:#161916,fg:#888880,fg+:#c0c0ba"
  --color="hl:#6a7d5e,hl+:#8aaa74"
  --color="border:#333630,preview-border:#333630"
  --color="prompt:#8aaa74,pointer:#8aaa74,marker:#6a7d5e"
  --color="input-label:#3a4436,preview-label:#3a4436,label:#3a4436"
  --color="info:#3a4436,spinner:#8aaa74"
)
# ─────────────────────────────────────────────
# List mode
#
# This exists so fzf can reload the list by
# executing this script again. No shell functions
# are needed inside fzf.
# ─────────────────────────────────────────────
print_wallpaper_list() {
  find -L "$WALL_DIR" -type f \( \
    -iname "*.jpg" \
    -o -iname "*.png" \
    -o -iname "*.jpeg" \
    \) |
    while IFS= read -r file; do
      printf '%s\t%s\n' "$file" "$(basename "$file")"
    done |
    sort -t $'\t' -k2,2
}
# ─────────────────────────────────────────────
# Simple input helpers (used by the loadout wizard)
# ─────────────────────────────────────────────
ask_text() {
  local header="$1" default="${2:-}"
  fzf \
    "${FZF_STYLE[@]}" \
    --header="$header" \
    --print-query \
    --query="$default" \
    --border-label=" Input " \
    --border-label-pos=2 \
    </dev/null | head -1
}
ask_choice() {
  local header="$1" default="$2"
  shift 2
  printf '%s\n' "$@" | fzf \
    "${FZF_STYLE[@]}" \
    --header="$header" \
    --query="$default" \
    --border-label=" Select " \
    --border-label-pos=2
}
# ─────────────────────────────────────────────
# Wallpaper picker (reused by the main loop and
# by the loadout wizard). Extra fzf args (binds
# etc) may be appended after label/query.
# ─────────────────────────────────────────────
wallpaper_picker() {
  local label="$1" query="$2"
  shift 2
  "$SELF" --list |
    fzf \
      "${FZF_STYLE[@]}" \
      --border-label=" Wallpaper " \
      --border-label-pos=2 \
      --preview-label="$label" \
      --preview-border=sharp \
      --delimiter=$'\t' \
      --with-nth=2 \
      --query="$query" \
      --preview='
file={1};
ueberzugpp cmd \
    -s "$SOCKET" \
    -i walpreview \
    -a add \
    -x $((FZF_PREVIEW_LEFT + 2)) \
    -y $((FZF_PREVIEW_TOP + 1)) \
    --max-width 48 \
    --max-height 12 \
    -f "$file" \
    2>/dev/null
' \
      --preview-window="right:48%:nowrap" \
      "$@" |
    cut -f1
}
if [[ "$1" == "--list" || "$1" == "--inside-list" ]]; then
  print_wallpaper_list
  exit 0
fi
# ─────────────────────────────────────────────
# Refresh-only mode
# ─────────────────────────────────────────────
if [[ "$1" == "--refresh" ]]; then
  ln -sf \
    "$HOME/.cache/wal/colors.Xresources" \
    "$HOME/.Xresources"
  {
    cat "$HOME/.cache/wal/colors.Xresources"
    [ -f "$HOME/.cache/wal/xrdb_extra" ] &&
      cat "$HOME/.cache/wal/xrdb_extra"
    [ -f "$HOME/.cache/wal/dmenu" ] &&
      cat "$HOME/.cache/wal/dmenu"
  } >/tmp/xresources_combined.tmp
  xrdb -load /tmp/xresources_combined.tmp
  if [ -f "$HOME/.cache/wal/sequences" ]; then
    for pts in /dev/pts/*; do
      [ -w "$pts" ] &&
        cat "$HOME/.cache/wal/sequences" \
          >"$pts" 2>/dev/null &
    done
    wait
  fi
  if command -v kitty >/dev/null 2>&1; then
    kitty @ \
      --to unix:/tmp/kitty \
      set-colors \
      --all \
      "$HOME/.cache/wal/colors-kitty.conf" \
      2>/dev/null || true
  fi
  exit 0
fi
# ─────────────────────────────────────────────
# Per-wallpaper backend/mode memory
#
# Read helpers used by the preview pane and by
# apply_loadout(). All fields come from
# ~/.config/wal/loadouts/<name>.json
# ─────────────────────────────────────────────
loadout_read_fields() {
  # argv: json path
  # prints: wallpaper \t color_source \t theme \t color_wallpaper \t backend \t mode
  python3 - "$1" <<'PYEOF'
import json
import sys
path = sys.argv[1]
try:
    d = json.load(open(path))
except Exception:
    d = {}
print("\t".join([
    d.get("wallpaper", ""),
    d.get("color_source", "none"),
    d.get("theme", ""),
    d.get("color_wallpaper", ""),
    d.get("backend", "wal"),
    d.get("mode", "dark"),
]))
PYEOF
}
loadout_read_extra() {
  python3 - "$1" <<'PYEOF'
import json
import sys
path = sys.argv[1]
try:
    d = json.load(open(path))
except Exception:
    d = {}
print(json.dumps(d.get("extra", {})))
PYEOF
}
loadout_extra_set() {
  # argv: current_extras_json key value
  python3 - "$1" "$2" "$3" <<'PYEOF'
import json
import sys
extras_json, key, val = sys.argv[1:4]
d = json.loads(extras_json) if extras_json else {}
d[key] = val
print(json.dumps(d))
PYEOF
}
loadout_write() {
  # argv: path name wallpaper color_source theme color_wallpaper backend mode extras_json
  python3 - "$@" <<'PYEOF'
import json
import sys
(path, name, wallpaper, color_source,
 theme, color_wallpaper, backend, mode, extras) = sys.argv[1:10]
data = {
    "name": name,
    "wallpaper": wallpaper,
    "color_source": color_source,
    "theme": theme,
    "color_wallpaper": color_wallpaper,
    "backend": backend,
    "mode": mode,
    "extra": json.loads(extras) if extras else {},
}
with open(path, "w") as f:
    json.dump(data, f, indent=2)
PYEOF
}
list_loadouts() {
  local f
  for f in "$LOADOUTS_DIR"/*.json; do
    [ -f "$f" ] || continue
    basename "$f" .json
  done | sort
}
show_loadout_preview() {
  local name="$1" file="$LOADOUTS_DIR/$name.json"
  [ -f "$file" ] || return
  local wallpaper color_source theme color_wallpaper backend mode
  IFS=$'\t' read -r wallpaper color_source theme color_wallpaper backend mode \
    < <(loadout_read_fields "$file")
  echo "$name"
  echo
  echo "wallpaper: $([ -n "$wallpaper" ] && basename "$wallpaper" || echo -)"
  case "$color_source" in
  theme)
    echo "colours:   theme ($theme)"
    ;;
  wallpaper)
    echo "colours:   wallpaper ($([ -n "$color_wallpaper" ] && basename "$color_wallpaper" || echo -))"
    echo "backend:   $backend"
    ;;
  *)
    echo "colours:   none"
    ;;
  esac
  [ "$color_source" != "none" ] && echo "mode:      $mode"
  local extras
  extras="$(loadout_read_extra "$file")"
  if [ -n "$extras" ] && [ "$extras" != "{}" ]; then
    echo
    echo "extra"
    python3 - "$extras" <<'PYEOF'
import json
import sys
d = json.loads(sys.argv[1])
for k, v in d.items():
    print(f"  {k}: {v}")
PYEOF
  fi
  if [ -n "$wallpaper" ] && [ -f "$wallpaper" ] && [ -n "${SOCKET:-}" ]; then
    ueberzugpp cmd \
      -s "$SOCKET" \
      -i walpreview \
      -a add \
      -x $((FZF_PREVIEW_LEFT + 2)) \
      -y $((FZF_PREVIEW_TOP + 12)) \
      --max-width 40 \
      --max-height 8 \
      -f "$wallpaper" \
      2>/dev/null
  fi
}
if [[ "$1" == "--preview-loadout" ]]; then
  show_loadout_preview "$2"
  exit 0
fi
# ─────────────────────────────────────────────
# Spawn kitty
# ─────────────────────────────────────────────
if [[ "$1" != "--inside" ]]; then
  read -r SCREEN_W SCREEN_H < <(
    xrandr --current 2>/dev/null |
      grep ' connected primary' |
      grep -oP '\d+x\d+' |
      head -1 |
      tr 'x' ' '
  )
  [ -z "$SCREEN_W" ] && SCREEN_W=1920
  [ -z "$SCREEN_H" ] && SCREEN_H=1080
  # Compact window
  FONT_W=8
  FONT_H=16
  COLS=$((SCREEN_W * 64 / 100 / FONT_W))
  ROWS=$((SCREEN_H * 43 / 100 / FONT_H))
  [ "$COLS" -lt 85 ] && COLS=85
  [ "$ROWS" -lt 18 ] && ROWS=18
  POS_X=$(((SCREEN_W - COLS * FONT_W) / 2))
  POS_Y=$(((SCREEN_H - ROWS * FONT_H) / 2))
  WAL_SEQ="$HOME/.cache/wal/sequences"
  WAL_KITTY="$HOME/.cache/wal/colors-kitty.conf"
  KITTY_CONF="/tmp/walpicker_kitty_$$.conf"
  {
    printf '# wal colors\n'
    [ -f "$WAL_KITTY" ] &&
      cat "$WAL_KITTY"
    printf 'font_size 10\n'
    printf 'confirm_os_window_close 0\n'
    printf 'initial_window_width %sc\n' "$COLS"
    printf 'initial_window_height %sc\n' "$ROWS"
    printf 'remember_window_size no\n'
    printf 'placement_strategy top-left\n'
    printf 'window_padding_width 5\n'
    printf 'window_margin_width 0\n'
  } >"$KITTY_CONF"
  LAUNCHER="/tmp/walpicker_$$.sh"
  {
    printf '#!/usr/bin/env bash\n'
    if [ -f "$WAL_SEQ" ]; then
      printf 'cat "%s" 2>/dev/null\n' "$WAL_SEQ"
    fi
    printf 'exec "%s" --inside\n' "$SELF"
  } >"$LAUNCHER"
  chmod +x "$LAUNCHER"
  exec kitty \
    --class "wal-picker" \
    --title "Wallpaper Picker" \
    --override "initial_window_x=${POS_X}" \
    --override "initial_window_y=${POS_Y}" \
    --config "$KITTY_CONF" \
    -e "$LAUNCHER"
fi
shift
# ─────────────────────────────────────────────
# Ueberzugpp
# ─────────────────────────────────────────────
UB_PID_FILE="/tmp/.wal_$$"
cleanup() {
  if [ -n "${SOCKET:-}" ]; then
    ueberzugpp cmd \
      -s "$SOCKET" \
      -a exit \
      2>/dev/null || true
  fi
  rm -f \
    "$UB_PID_FILE" \
    /tmp/walpicker_*.sh \
    /tmp/walpicker_kitty_*.conf \
    2>/dev/null
}
trap cleanup EXIT HUP INT QUIT TERM
ueberzugpp layer \
  --no-stdin \
  --silent \
  --pid-file "$UB_PID_FILE" \
  2>/dev/null
UB_PID="$(cat "$UB_PID_FILE" 2>/dev/null)"
if [ -z "$UB_PID" ]; then
  echo "ERROR: ueberzugpp failed to start" >&2
  exit 1
fi
export SOCKET="/tmp/ueberzugpp-${UB_PID}.socket"
# ─────────────────────────────────────────────
# DWM / environment refresh
# ─────────────────────────────────────────────
refresh_dwm() {
  ln -sf \
    "$HOME/.cache/wal/colors.Xresources" \
    "$HOME/.Xresources"
  {
    cat "$HOME/.cache/wal/colors.Xresources"
    [ -f "$HOME/.cache/wal/xrdb_extra" ] &&
      cat "$HOME/.cache/wal/xrdb_extra"
    [ -f "$HOME/.cache/wal/dmenu" ] &&
      cat "$HOME/.cache/wal/dmenu"
  } >/tmp/xresources_combined.tmp
  xrdb -load /tmp/xresources_combined.tmp
  xdotool key super+ctrl+x
  pkill -RTMIN+8 dwmblocks 2>/dev/null || true
  pkill -RTMIN+10 dwmblocks 2>/dev/null || true
  if [ -f "$HOME/.cache/wal/sequences" ]; then
    for pts in /dev/pts/*; do
      [ -w "$pts" ] &&
        cat "$HOME/.cache/wal/sequences" \
          >"$pts" 2>/dev/null &
    done
    wait
  fi
  if command -v kitty >/dev/null 2>&1; then
    kitty @ set-colors \
      --all \
      "$HOME/.cache/wal/colors-kitty.conf" \
      2>/dev/null || true
  fi
}
set_static() {
  feh --bg-scale "$1"
}
# ─────────────────────────────────────────────
# Color post-processing
# ─────────────────────────────────────────────
process_wal_colors() {
  python3 - "$1" "$2" "$3" "$4" "${5:-}" <<'PYEOF'
import colorsys
import json
import re
import sys
from pathlib import Path
def hex_to_hsl(c):
    c = c.lstrip("#")
    r, g, b = (
        int(c[i:i+2], 16) / 255.0
        for i in (0, 2, 4)
    )
    return colorsys.rgb_to_hls(r, g, b)
def hsl_to_hex(h, l, s):
    r, g, b = colorsys.hls_to_rgb(h, l, s)
    return "#{:02x}{:02x}{:02x}".format(
        int(r * 255),
        int(g * 255),
        int(b * 255)
    )
def enrich(c, ld, sd, vibrant):
    h, l, s = hex_to_hsl(c)
    l = max(0.0, min(1.0, l - ld))
    if vibrant:
        s = min(1.0, s * (1.0 + sd))
    else:
        s = min(0.8, s + sd)
    return hsl_to_hex(h, l, s)
bg_l, bg_s, other_l, other_s = (
    float(x) for x in sys.argv[1:5]
)
vibrant = (
    len(sys.argv) > 5 and
    sys.argv[5] == "vibrant"
)
cache = Path.home() / ".cache" / "wal"
colors_json = cache / "colors.json"
data = json.loads(colors_json.read_text())
cmap = {}
for key, orig in data.get("colors", {}).items():
    new = enrich(
        orig,
        bg_l if key == "color0" else other_l,
        bg_s if key == "color0" else other_s,
        vibrant
    )
    cmap[orig] = new
    data["colors"][key] = new
for key, orig in data.get("special", {}).items():
    new = enrich(
        orig,
        bg_l if key == "background" else other_l,
        bg_s if key == "background" else other_s,
        vibrant
    )
    cmap[orig] = new
    data["special"][key] = new
colors_json.write_text(
    json.dumps(data, indent=2)
)
for fname in (
    "sequences",
    "colors.Xresources",
    "colors-wal.vim"
):
    p = cache / fname
    if p.exists():
        txt = p.read_text()
        for old, new in cmap.items():
            txt = re.sub(
                re.escape(old),
                new,
                txt,
                flags=re.IGNORECASE
            )
        p.write_text(txt)
sp = data.get("special", {})
co = data.get("colors", {})
wp = data.get("wallpaper", "")
sh = f"""# Shell variables
wallpaper='{wp}'
background='{sp.get("background", "#000000")}'
foreground='{sp.get("foreground", "#ffffff")}'
cursor='{sp.get("cursor", "#ffffff")}'
"""
for i in range(16):
    sh += (
        f"color{i}="
        f"'{co.get(f'color{i}', '#000000')}'\n"
    )
(cache / "colors.sh").write_text(sh)
kitty = f"""foreground   {sp.get("foreground", "#ffffff")}
background   {sp.get("background", "#000000")}
cursor       {sp.get("cursor", "#ffffff")}
"""
pairs = (
    (0, 8),
    (1, 9),
    (2, 10),
    (3, 11),
    (4, 12),
    (5, 13),
    (6, 14),
    (7, 15),
)
for a, b in pairs:
    kitty += (
        f"color{a:<5}  "
        f"{co.get(f'color{a}', '#000000')}\n"
        f"color{b:<5}  "
        f"{co.get(f'color{b}', '#000000')}\n"
    )
(cache / "colors-kitty.conf").write_text(kitty)
tpl_dir = Path.home() / ".config" / "wal" / "templates"
if tpl_dir.exists():
    for tpl in tpl_dir.glob("*"):
        if tpl.is_file():
            txt = tpl.read_text()
            for k, v in co.items():
                txt = txt.replace(
                    f"{{{k}}}",
                    v
                )
            for k, v in sp.items():
                txt = txt.replace(
                    f"{{{k}}}",
                    v
                )
            txt = txt.replace(
                "{wallpaper}",
                wp
            )
            (cache / tpl.name).write_text(txt)
PYEOF
}
# ─────────────────────────────────────────────
# Keyboard backlight
# ─────────────────────────────────────────────
sync_keyboard_color() {
  local colors_json="$HOME/.cache/wal/colors.json"
  [ -f "$colors_json" ] || return
  local accent
  accent="$(python3 -c "
import colorsys
import json
from pathlib import Path
try:
    data = json.loads(
        Path('$colors_json').read_text()
    )
    c = data.get('colors', {}).get(
        'color4',
        '#000000'
    ).lstrip('#')
    r, g, b = (
        int(c[i:i+2], 16) / 255.0
        for i in (0, 2, 4)
    )
    h, l, s = colorsys.rgb_to_hls(r, g, b)
    l = 0.12
    s = min(1.0, s * 1.6)
    r, g, b = colorsys.hls_to_rgb(h, l, s)
    print(
        f'{int(r*255):02x}'
        f'{int(g*255):02x}'
        f'{int(b*255):02x}'
    )
except Exception:
    pass
")"
  [ -n "$accent" ] || return
  asusctl -k low >/dev/null 2>&1
  asusctl aura effect static \
    -c "$accent" \
    >/dev/null 2>&1
}
# ─────────────────────────────────────────────
# ZenNotes theme
# ─────────────────────────────────────────────
sync_zennotes_theme() {
  local colors_json="$HOME/.cache/wal/colors.json"
  [ -f "$colors_json" ] || return
  python3 - "$colors_json" "$ZEN_THEME_DIR" <<'PYEOF'
import colorsys
import json
import sys
from pathlib import Path
colors_json, theme_dir = sys.argv[1], Path(sys.argv[2])
def hex_to_rgb(c):
    c = c.lstrip("#")
    return tuple(
        int(c[i:i+2], 16)
        for i in (0, 2, 4)
    )
def rgb_str(c):
    r, g, b = hex_to_rgb(c)
    return f"{r} {g} {b}"
def hex_to_hls(c):
    r, g, b = (
        v / 255.0
        for v in hex_to_rgb(c)
    )
    return colorsys.rgb_to_hls(r, g, b)
def shift(c, dl=0.0, ds=0.0):
    h, l, s = hex_to_hls(c)
    l = max(0.0, min(1.0, l + dl))
    s = max(0.0, min(1.0, s + ds))
    r, g, b = colorsys.hls_to_rgb(h, l, s)
    return (
        f"{int(r * 255)} "
        f"{int(g * 255)} "
        f"{int(b * 255)}"
    )
data = json.loads(
    Path(colors_json).read_text()
)
sp = data.get("special", {})
co = data.get("colors", {})
bg = sp.get(
    "background",
    "#1c1c1e"
)
fg = sp.get(
    "foreground",
    "#ffffff"
)
accent = co.get(
    "color4",
    "#0a84ff"
)
_, l_bg, _ = hex_to_hls(bg)
dark = l_bg < 0.5
sign = 1 if dark else -1
tokens = {
    "--z-bg":
        rgb_str(bg),
    "--z-bg-softer":
        shift(bg, sign * 0.02),
    "--z-bg-1":
        shift(bg, sign * 0.05),
    "--z-bg-2":
        shift(bg, sign * 0.09),
    "--z-bg-3":
        shift(bg, sign * 0.14),
    "--z-bg-4":
        shift(bg, sign * 0.24),
    "--z-fg":
        rgb_str(fg),
    "--z-fg-1":
        shift(fg, sign * 0.02),
    "--z-fg-2":
        shift(fg, -sign * 0.27),
    "--z-grey-2":
        shift(fg, -sign * 0.27),
    "--z-grey-1":
        shift(fg, -sign * 0.36),
    "--z-grey-0":
        shift(fg, -sign * 0.45),
    "--z-grey-dim":
        shift(fg, -sign * 0.60),
    "--z-accent":
        rgb_str(accent),
    "--z-accent-soft":
        shift(accent, sign * 0.12),
    "--z-accent-muted":
        shift(accent, 0.0, -0.35),
    "--z-red":
        rgb_str(
            co.get(
                "color1",
                "#c14a4a"
            )
        ),
    "--z-green":
        rgb_str(
            co.get(
                "color2",
                "#6c782e"
            )
        ),
    "--z-yellow":
        rgb_str(
            co.get(
                "color3",
                "#b47109"
            )
        ),
    "--z-blue":
        rgb_str(
            co.get(
                "color4",
                "#45707a"
            )
        ),
    "--z-purple":
        rgb_str(
            co.get(
                "color5",
                "#945e80"
            )
        ),
    "--z-aqua":
        rgb_str(
            co.get(
                "color6",
                "#4c7a5d"
            )
        ),
    "--z-shadow":
        rgb_str(bg)
        if dark
        else "17 17 19",
    "--z-glass-a1":
        "0.6",
    "--z-glass-a2":
        "0.48",
    "--z-glass-a3":
        "0.34",
    "--z-glass-a4":
        "0.24",
}
body = "\n".join(
    f"  {k}: {v};"
    for k, v in tokens.items()
)
css = (
    "/* Wal Theme — auto-generated. */\n"
    ":root {\n"
    f"  color-scheme: "
    f"{'dark' if dark else 'light'};\n"
    f"{body}\n"
    "}\n"
)
theme_dir.mkdir(
    parents=True,
    exist_ok=True
)
(theme_dir / "theme.css").write_text(css)
manifest_path = theme_dir / "manifest.json"
if not manifest_path.exists():
    manifest = {
        "name": "Wal Theme",
        "author": "atego",
        "version": "1.0.0",
        "description":
            "Auto-generated theme synced to "
            "the current pywal palette.",
        "modes": "both",
        "preview": {
            "light": accent,
            "dark": accent
        }
    }
    manifest_path.write_text(
        json.dumps(
            manifest,
            indent=2
        )
    )
PYEOF
}
# ─────────────────────────────────────────────
# Apply wallpaper (full colour generation)
# ─────────────────────────────────────────────
apply() {
  local file="$1"
  local backend="$2"
  local mode="${3:-dark}"
  [ -f "$file" ] || return 1
  set_static "$file"
  case "$mode" in
  light)
    wal -i "$file" \
      --backend "$backend" \
      -t -n -q
    process_wal_colors \
      -0.18 0.25 \
      -0.10 0.20 \
      vibrant
    ;;
  medium)
    wal -i "$file" \
      --backend "$backend" \
      -t -n -q
    process_wal_colors \
      0.0 2.0 \
      0.02 2.0 \
      vibrant
    ;;
  *)
    wal -i "$file" \
      --backend "$backend" \
      -t -n -q
    ;;
  esac
  sync_keyboard_color
  sync_zennotes_theme
  for sock in "$XDG_RUNTIME_DIR"/nvim.*.0; do
    [ -S "$sock" ] || continue
    nvim --server "$sock" \
      --remote-send \
      ':colorscheme wal<CR>' \
      2>/dev/null
  done
  refresh_dwm
  echo "$file" >"$WAL_LAST"
  notify-send \
    "Wallpaper" \
    "$(basename "$file") [$mode]" \
    -t 3000
}
# ─────────────────────────────────────────────
# Apply wallpaper only — no theme/colour change
# ─────────────────────────────────────────────
apply_wallpaper_only() {
  local file="$1"
  [ -f "$file" ] || return 1
  set_static "$file"
  echo "$file" >"$WAL_LAST"
  notify-send \
    "Wallpaper" \
    "$(basename "$file") [image only]" \
    -t 3000
}
# ─────────────────────────────────────────────
# Apply theme only
# ─────────────────────────────────────────────
apply_theme() {
  local theme="$1"
  local mode="${2:-dark}"
  echo "$theme $mode" \
    >"$HOME/.cache/wal/last_theme"
  case "$mode" in
  light)
    wal --theme "$theme" \
      -t -n -q
    process_wal_colors \
      -0.18 0.25 \
      -0.10 0.20 \
      vibrant
    ;;
  medium)
    wal --theme "$theme" \
      -t -n -q
    process_wal_colors \
      0.0 2.0 \
      0.02 2.0 \
      vibrant
    ;;
  *)
    wal --theme "$theme" \
      -t -n -q
    ;;
  esac
  sync_keyboard_color
  sync_zennotes_theme
  refresh_dwm
  notify-send \
    "Theme" \
    "$theme [$mode]" \
    -t 3000
}
# ─────────────────────────────────────────────
# Theme picker
# ─────────────────────────────────────────────
pick_theme() {
  local query="${1:-}"
  wal --theme 2>/dev/null |
    grep -oP '(?<=- )[\w\.-]+' |
    sort |
    fzf \
      "${FZF_STYLE[@]}" \
      --border-label=" Theme " \
      --border-label-pos=2 \
      --query="$query" \
      --preview-label="[ $MODE ]  ctrl-m mode  esc back" \
      --preview-border=sharp \
      --preview="
theme={};
wal --theme \"\$theme\" -t -n -q 2>/dev/null;
python3 -c \"
import json
from pathlib import Path
try:
    data = json.loads(
        Path('$HOME/.cache/wal/colors.json').read_text()
    )
    sp = data.get('special', {})
    cols = list(data.get('colors', {}).values())
    bg = sp.get('background', '#000000')
    fg = sp.get('foreground', '#ffffff')
    def block(c):
        r = int(c[1:3], 16)
        g = int(c[3:5], 16)
        b = int(c[5:7], 16)
        lum = (
            0.299*r +
            0.587*g +
            0.114*b
        )
        tc = (
            '0;0;0'
            if lum > 140
            else '255;255;255'
        )
        return (
            f'\\\\033[48;2;{r};{g};{b}m'
            f'\\\\033[38;2;{tc}m'
            f' {c} \\\\033[0m'
        )
    print()
    print('  special')
    print('  ' + block(bg) + '  background')
    print('  ' + block(fg) + '  foreground')
    print()
    print('  colors')
    for i, c in enumerate(cols[:8]):
        c2 = (
            cols[i+8]
            if i+8 < len(cols)
            else c
        )
        print(
            f'  {block(c)} color{i:<2}  '
            f'{block(c2)} color{i+8}'
        )
    print()
except Exception:
    print('no colors.json yet')
\" 2>/dev/null
" \
      --preview-window="right:48%:nowrap" \
      --bind="ctrl-m:become(echo __TOGGLE_MODE__)"
}
# ─────────────────────────────────────────────
# Loadouts: apply
# ─────────────────────────────────────────────
apply_loadout() {
  local name="$1" file="$LOADOUTS_DIR/$name.json"
  [ -f "$file" ] || return 1
  local wallpaper color_source theme color_wallpaper backend mode
  IFS=$'\t' read -r wallpaper color_source theme color_wallpaper backend mode \
    < <(loadout_read_fields "$file")
  case "$color_source" in
  theme)
    [ -n "$wallpaper" ] && [ -f "$wallpaper" ] && set_static "$wallpaper"
    apply_theme "$theme" "$mode"
    [ -n "$wallpaper" ] && [ -f "$wallpaper" ] && echo "$wallpaper" >"$WAL_LAST"
    ;;
  wallpaper)
    if [ -n "$color_wallpaper" ] && [ -f "$color_wallpaper" ]; then
      if [ "$wallpaper" = "$color_wallpaper" ]; then
        apply "$wallpaper" "$backend" "$mode"
      else
        [ -n "$wallpaper" ] && [ -f "$wallpaper" ] && set_static "$wallpaper"
        wal -i "$color_wallpaper" --backend "$backend" -t -n -q
        case "$mode" in
        light) process_wal_colors -0.18 0.25 -0.10 0.20 vibrant ;;
        medium) process_wal_colors 0.0 2.0 0.02 2.0 vibrant ;;
        esac
        sync_keyboard_color
        sync_zennotes_theme
        refresh_dwm
        [ -n "$wallpaper" ] && echo "$wallpaper" >"$WAL_LAST"
      fi
    fi
    ;;
  *)
    [ -n "$wallpaper" ] && [ -f "$wallpaper" ] && apply_wallpaper_only "$wallpaper"
    ;;
  esac
  notify-send "Loadout" "Applied: $name" -t 2000
}
# ─────────────────────────────────────────────
# Loadouts: create / edit wizard
#
# A loadout is a wallpaper plus (optionally) a
# colour source — a theme, or another wallpaper
# run through a backend/mode — plus a free-form
# "extra" map for anything added later (e.g. a
# fastfetch image path).
# ─────────────────────────────────────────────
loadout_wizard() {
  local edit_name="$1"
  local def_wallpaper="" def_color_source="none" def_theme=""
  local def_color_wallpaper="" def_backend="${BACKENDS[0]}" def_mode="dark"
  local def_extras="{}"
  if [ -n "$edit_name" ] && [ -f "$LOADOUTS_DIR/$edit_name.json" ]; then
    IFS=$'\t' read -r def_wallpaper def_color_source def_theme def_color_wallpaper def_backend def_mode \
      < <(loadout_read_fields "$LOADOUTS_DIR/$edit_name.json")
    def_extras="$(loadout_read_extra "$LOADOUTS_DIR/$edit_name.json")"
  fi

  local name
  name="$(ask_text " Loadout name " "$edit_name")"
  [ -n "$name" ] || return 0

  local wallpaper
  wallpaper="$(wallpaper_picker " Pick background wallpaper   esc cancel " "${def_wallpaper:+$(basename "$def_wallpaper")}")"
  [ -n "$wallpaper" ] || return 0

  local color_choice
  color_choice="$(ask_choice " Colour source " "" \
    "Theme" \
    "This wallpaper" \
    "Different wallpaper" \
    "None (no colours)")"
  [ -n "$color_choice" ] || return 0

  local color_source="none" theme="" color_wallpaper="" backend=""
  case "$color_choice" in
  Theme)
    color_source="theme"
    while true; do
      theme="$(pick_theme "$def_theme")"
      case "$theme" in
      "" | __BACK__) return 0 ;;
      __TOGGLE_MODE__) continue ;;
      *) break ;;
      esac
    done
    ;;
  "This wallpaper")
    color_source="wallpaper"
    color_wallpaper="$wallpaper"
    backend="$(ask_choice " Backend " "$def_backend" "${BACKENDS[@]}")"
    [ -n "$backend" ] || return 0
    ;;
  "Different wallpaper")
    color_source="wallpaper"
    color_wallpaper="$(wallpaper_picker " Pick colour wallpaper   esc cancel " "${def_color_wallpaper:+$(basename "$def_color_wallpaper")}")"
    [ -n "$color_wallpaper" ] || return 0
    backend="$(ask_choice " Backend " "$def_backend" "${BACKENDS[@]}")"
    [ -n "$backend" ] || return 0
    ;;
  "None (no colours)")
    color_source="none"
    ;;
  esac

  local mode="dark"
  if [ "$color_source" != "none" ]; then
    mode="$(ask_choice " Mode " "$def_mode" "dark" "medium" "light")"
    [ -n "$mode" ] || return 0
  fi

  local extras_json="$def_extras"
  [ -n "$extras_json" ] || extras_json="{}"
  while true; do
    local add_more
    add_more="$(ask_choice " Add extra field? (e.g. fastfetch_image) " "" "No" "Yes")"
    [ "$add_more" = "Yes" ] || break
    local key val
    key="$(ask_text " Field name " "")"
    [ -n "$key" ] || continue
    val="$(ask_text " Value for '$key' " "")"
    extras_json="$(loadout_extra_set "$extras_json" "$key" "$val")"
  done

  loadout_write \
    "$LOADOUTS_DIR/$name.json" \
    "$name" \
    "$wallpaper" \
    "$color_source" \
    "$theme" \
    "$color_wallpaper" \
    "$backend" \
    "$mode" \
    "$extras_json"

  if [ -n "$edit_name" ] && [ "$edit_name" != "$name" ] && [ -f "$LOADOUTS_DIR/$edit_name.json" ]; then
    rm -f "$LOADOUTS_DIR/$edit_name.json"
  fi

  notify-send "Loadouts" "Saved: $name" -t 1500
}
# ─────────────────────────────────────────────
# Main loop
#
# Nothing here remembers past choices per
# wallpaper any more — backend/mode are just
# whatever the session currently has selected.
# Applying something never closes the picker;
# only esc/empty selection on the wallpaper tab
# quits.
# ─────────────────────────────────────────────
MODE="dark"
VIEW="wallpapers"
while true; do
  BACKEND="${BACKENDS[$BACKEND_IDX]}"
  if [ "$VIEW" = "wallpapers" ]; then
    PLABEL=" ${BACKEND} [$MODE]  ctrl-w image only  ctrl-b backend  ctrl-m mode  ctrl-t theme  ctrl-r random  ctrl-l loadouts  esc quit "
    SEL="$(
      wallpaper_picker "$PLABEL" "" \
        --bind="ctrl-w:become(echo __WALLPAPER_ONLY__:{1})" \
        --bind="ctrl-b:become(echo __NEXT_BACKEND__)" \
        --bind="ctrl-m:become(echo __NEXT_MODE__)" \
        --bind="ctrl-t:become(echo __THEME_PICKER__)" \
        --bind="ctrl-r:become(echo __RANDOM__)" \
        --bind="ctrl-l:become(echo __LOADOUTS__)"
    )"
    case "$SEL" in
    "")
      exit 0
      ;;
    __NEXT_BACKEND__)
      BACKEND_IDX=$(((BACKEND_IDX + 1) % ${#BACKENDS[@]}))
      continue
      ;;
    __NEXT_MODE__)
      case "$MODE" in
      dark) MODE="light" ;;
      light) MODE="medium" ;;
      medium) MODE="dark" ;;
      esac
      notify-send \
        "Wallpaper Picker" \
        "Mode -> $MODE" \
        -t 1200
      continue
      ;;
    __THEME_PICKER__)
      THEME="$(pick_theme "")"
      case "$THEME" in
      "" | __BACK__)
        continue
        ;;
      __TOGGLE_MODE__)
        case "$MODE" in
        dark) MODE="light" ;;
        light) MODE="medium" ;;
        medium) MODE="dark" ;;
        esac
        notify-send \
          "Wallpaper Picker" \
          "Mode -> $MODE" \
          -t 1200
        continue
        ;;
      *)
        apply_theme "$THEME" "$MODE"
        continue
        ;;
      esac
      ;;
    __RANDOM__)
      RANDOM_IMG="$(
        find -L "$WALL_DIR" -type f \( \
          -iname "*.jpg" \
          -o -iname "*.png" \
          -o -iname "*.jpeg" \
          \) |
          shuf -n 1
      )"
      [ -n "$RANDOM_IMG" ] && apply "$RANDOM_IMG" "$BACKEND" "$MODE"
      continue
      ;;
    __LOADOUTS__)
      VIEW="loadouts"
      continue
      ;;
    __WALLPAPER_ONLY__:*)
      apply_wallpaper_only "${SEL#__WALLPAPER_ONLY__:}"
      continue
      ;;
    *)
      apply "$SEL" "$BACKEND" "$MODE"
      continue
      ;;
    esac
  else
    SEL="$(
      list_loadouts |
        fzf \
          "${FZF_STYLE[@]}" \
          --border-label=" Loadouts " \
          --border-label-pos=2 \
          --preview-label=" ctrl-c create  ctrl-e edit  ctrl-d delete  ctrl-l load  esc back " \
          --preview-border=sharp \
          --preview="'$SELF' --preview-loadout {}" \
          --preview-window="right:48%:nowrap" \
          --bind="ctrl-c:become(echo __CREATE__)" \
          --bind="ctrl-e:become(echo __EDIT__:{})" \
          --bind="ctrl-d:become(echo __DELETE__:{})" \
          --bind="ctrl-l:become(echo __LOAD__:{})" \
          --bind="enter:become(echo __LOAD__:{})"
    )"
    case "$SEL" in
    "")
      VIEW="wallpapers"
      continue
      ;;
    __CREATE__)
      loadout_wizard ""
      continue
      ;;
    __EDIT__:*)
      loadout_wizard "${SEL#__EDIT__:}"
      continue
      ;;
    __DELETE__:*)
      LNAME="${SEL#__DELETE__:}"
      if [ -n "$LNAME" ]; then
        rm -f "$LOADOUTS_DIR/$LNAME.json"
        notify-send "Loadouts" "Deleted: $LNAME" -t 1200
      fi
      continue
      ;;
    __LOAD__:*)
      LNAME="${SEL#__LOAD__:}"
      [ -n "$LNAME" ] && apply_loadout "$LNAME"
      continue
      ;;
    *)
      continue
      ;;
    esac
  fi
done
