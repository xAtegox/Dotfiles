#!/usr/bin/env bash
# wal-lib.sh — shared pywal apply/refresh helpers (atego)
#
# NOTE: everything pywal-related that gif-test does is kept here so that
# gif-test and loadouts stay in sync. This is the source of truth for:
#   - wallpaper / theme application (wal backends + dark/medium/light modes)
#   - colour post-processing (process_wal_colors)
#   - dwm / xrdb / kitty refresh
#   - asusctl keyboard backlight sync
# (zed-theme + zennotes sync were removed from the apply path)
# Edit here; both pick it up.
# ─────────────────────────────────────────────
# Constants (defaults, override before sourcing)
# ─────────────────────────────────────────────
: "${WAL_LAST:=$HOME/.cache/wal/wal_last.txt}"
: "${FAVORITES_FILE:=$HOME/.config/wal/favorites.txt}"
: "${SETTINGS_FILE:=$HOME/.cache/wal/wallpaper_settings.tsv}"
: "${PREVIEW_CACHE:=$HOME/.cache/wal_preview_thumbs}"
: "${ZEN_THEME_DIR:=$HOME/.config/zennotes/themes/wal-theme}"
# Mode post-processing presets (passed to process_wal_colors).
# Defaults are gif-test's values; scripts that want their own modes
# (e.g. loadouts) can override these after sourcing.
: "${PROCESS_LIGHT:=-0.18 0.25 -0.10 0.20 vibrant}"
: "${PROCESS_MEDIUM:=0.0 2.0 0.02 2.0 vibrant}"
mkdir -p "$PREVIEW_CACHE" 2>/dev/null || true
mkdir -p "$(dirname "$FAVORITES_FILE")" 2>/dev/null || true
mkdir -p "$(dirname "$SETTINGS_FILE")" 2>/dev/null || true
touch "$FAVORITES_FILE" 2>/dev/null || true
touch "$SETTINGS_FILE" 2>/dev/null || true
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
# Favorites
# ─────────────────────────────────────────────
is_favorite() {
  grep -Fxq -- "$1" "$FAVORITES_FILE"
}
toggle_favorite() {
  local file="$1"
  local tmp
  [ -n "$file" ] || exit 0
  if is_favorite "$file"; then
    tmp="$(mktemp)"
    grep -Fxv -- "$file" "$FAVORITES_FILE" >"$tmp"
    mv "$tmp" "$FAVORITES_FILE"
    notify-send \
      "Wallpaper" \
      "Removed ★ $(basename "$file")" \
      -t 1200
  else
    printf '%s\n' "$file" >>"$FAVORITES_FILE"
    notify-send \
      "Wallpaper" \
      "Added ★ $(basename "$file")" \
      -t 1200
  fi
}
# ─────────────────────────────────────────────
# Per-wallpaper backend/mode memory
#
# get_saved_settings sets SAVED_BACKEND / SAVED_MODE
# and returns 0 if a row exists for the file, 1 if not.
# save_wallpaper_settings upserts a row.
# ─────────────────────────────────────────────
get_saved_settings() {
  local file="$1" line
  line="$(grep -F -- "$(printf '%s\t' "$file")" "$SETTINGS_FILE" 2>/dev/null | tail -1)"
  [ -n "$line" ] || return 1
  SAVED_BACKEND="$(cut -f2 <<<"$line")"
  SAVED_MODE="$(cut -f3 <<<"$line")"
  [ -n "$SAVED_BACKEND" ] && [ -n "$SAVED_MODE" ] || return 1
  return 0
}
save_wallpaper_settings() {
  local file="$1" backend="$2" mode="$3" tmp
  tmp="$(mktemp)"
  grep -Fv -- "$(printf '%s\t' "$file")" "$SETTINGS_FILE" 2>/dev/null >"$tmp" || true
  printf '%s\t%s\t%s\n' "$file" "$backend" "$mode" >>"$tmp"
  mv "$tmp" "$SETTINGS_FILE"
}
# ─────────────────────────────────────────────
# Terminal-only refresh (xrdb / sequences / kitty / zed)
# ─────────────────────────────────────────────
refresh_terminal() {
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
  "$HOME/Linux_Config/Zed/zed-theme-wal/generate_theme" &
  if pgrep -x zed-editor >/dev/null; then
    "$HOME/Linux_Config/Zed/zed-theme-wal/generate_theme"
    pkill -x zed-editor
    sleep 0.2
    zeditor >/dev/null 2>&1 &
  fi
}
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
        s = max(0.0, min(0.8, s + sd))
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
# Apply wallpaper
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
      $PROCESS_LIGHT
    ;;
  medium)
    wal -i "$file" \
      --backend "$backend" \
      -t -n -q
    process_wal_colors \
      $PROCESS_MEDIUM
    ;;
  *)
    wal -i "$file" \
      --backend "$backend" \
      -t -n -q
    ;;
  esac
  sync_keyboard_color
  for sock in "$XDG_RUNTIME_DIR"/nvim.*.0; do
    [ -S "$sock" ] || continue
    nvim --server "$sock" \
      --remote-send \
      ':colorscheme wal<CR>' \
      2>/dev/null
  done
  refresh_dwm
  echo "$file" >"$WAL_LAST"
  if [ -z "${LOADOUT_SILENT:-}" ]; then
    notify-send \
      "Wallpaper" \
      "$(basename "$file") [$mode]" \
      -t 3000
  fi
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
  refresh_dwm
  if [ -z "${LOADOUT_SILENT:-}" ]; then
    notify-send \
      "Theme" \
      "$theme [$mode]" \
      -t 3000
  fi
}