#!/bin/bash

# omarchy:summary=Pick a background for the plugin hover card (reuses the desktop tile selector)
# omarchy:args=[current-image]
# omarchy:examples=card-bg-picker.sh ~/.local/state/omarchy/current/background

# Opens the same background carousel the Omarchy desktop uses
# (omarchy-menu-images -> image-selector), scoped to the theme and user
# background directories, and prints the chosen path so the plugin can persist
# it as its cardBackground setting. Prints nothing when the picker is
# dismissed, so a cancel never touches the card background.
#
# Security: omarchy-menu-images is NOT resolved through $PATH (a hijacked,
# user-writable PATH entry could redirect it). Instead it is looked up at a
# fixed system location and canonically resolved, then verified to be a
# root-owned executable the invoking user cannot write — so a forged/root-mine
# file is never run. The menu's stdout is capped at the producer (head -c), so
# the surrounding QML never buffers unbounded output. The chosen image is
# validated with a bounded ImageMagick identify (resource/frame limits, header-
# only ping) after the byte-size gate — only known raster formats, under 50 MiB
# and within 8192x8192 / 40 MP are accepted. The plugin additionally runs this
# script under setsid+timeout so the picker cannot outlive its bound.

set -u

current="$1"

# Trusted helper resolution: fixed system locations only, canonicalized via
# realpath (removes any $PATH/$HOME reload), then ownership/unwritability check.
menu=""
for cand in /usr/bin/omarchy-menu-images /usr/local/bin/omarchy-menu-images; do
  if [ -L "$cand" ] || [ -f "$cand" ]; then
    menu=$(/usr/bin/realpath -- "$cand" 2>/dev/null) || menu=""
    [ -n "$menu" ] && break
  fi
done
[ -n "$menu" ] || exit 0
[ -f "$menu" ] && [ -x "$menu" ] || exit 0
st=$(/usr/bin/stat -c "%u %a" -- "$menu" 2>/dev/null) || { set -- "" ""; }
set -- $st
[ "$1" = "0" ] || exit 0                 # must be root-owned
[ -n "$2" ] || exit 0
perms=$((8#$2))                          # octal mode -> number
[ $(( perms & 0022 )) -eq 0 ] || exit 0  # no group/other write (unwritable by us)

theme_name=$(cat "$HOME/.local/state/omarchy/current/theme.name" 2>/dev/null) || theme_name=""

dirs=("$HOME/.local/state/omarchy/current/theme/backgrounds")
if [[ -n $theme_name && -d "$HOME/.config/omarchy/backgrounds/$theme_name" ]]; then
  dirs+=("$HOME/.config/omarchy/backgrounds/$theme_name")
fi

# Producer-side cap: the menu's stdout is bounded with head -c before the shell
# buffers it, so a runaway carousel can never fill memory here or in QML.
selection=$("$menu" --selected "${current:-}" "${dirs[@]}" 2>/dev/null | /usr/bin/head -c 65536)
selection=${selection%$'\n'}
[[ -n $selection ]] || exit 0

# Bounded image decode: byte-size gate first, then a resource/frame-limited,
# header-only identify. Runs AFTER the byte gate so we never feed a huge file
# to ImageMagick; -ping reads metadata without decoding pixels; -limit constrains
# ImageMagick's own memory/disk/width/height budgets.
bytes=$(/usr/bin/stat -c %s -- "$selection" 2>/dev/null) || exit 0
(( bytes <= 52428800 )) || exit 0 # 50 MiB

ID=/usr/bin/identify
[ -x "$ID" ] || exit 0

info=$("$ID" -ping \
  -limit area 64MiB -limit memory 128MiB -limit map 128MiB -limit disk 64MiB \
  -limit width 16384 -limit height 16384 \
  -format "%m %wx%h" -- "$selection" 2>/dev/null) || exit 0
info=${info%$'\r'}
read -r ftype dims <<< "$info"
[[ $ftype =~ ^(PNG|JPEG|WEBP|AVIF|GIF)$ ]] || exit 0

width=${dims%x*}
height=${dims#*x}
if [[ $width =~ ^[0-9]+$ ]] && [[ $height =~ ^[0-9]+$ ]]; then
  (( width <= 8192 )) || exit 0
  (( height <= 8192 )) || exit 0
  (( width * height <= 40000000 )) || exit 0 # 40 MP
else
  exit 0
fi

printf '%s' "$selection"