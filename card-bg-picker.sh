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
# Security: omarchy-menu-images is resolved to an absolute executable (a
# hijacked $PATH cannot silently redirect it); the chosen image is validated
# with ImageMagick identify before printing — only known raster formats under
# 50 MiB and within 8192x8192 / 40 MP are accepted. The plugin additionally
# runs this script under setsid+timeout so the picker cannot outlive its bound.

set -u

current="$1"

menu=$(command -v omarchy-menu-images) || exit 0
case "$menu" in
  /*) [ -x "$menu" ] || exit 0 ;;
  *) exit 0 ;; # must resolve to an absolute path
esac

theme_name=$(cat "$HOME/.local/state/omarchy/current/theme.name" 2>/dev/null) || theme_name=""

dirs=("$HOME/.local/state/omarchy/current/theme/backgrounds")
if [[ -n $theme_name && -d "$HOME/.config/omarchy/backgrounds/$theme_name" ]]; then
  dirs+=("$HOME/.config/omarchy/backgrounds/$theme_name")
fi

selection=$("$menu" --selected "${current:-}" "${dirs[@]}") || exit 0
[[ -n $selection ]] || exit 0

# Bounded image decode: format/type, byte size, and dimensions.
if ! command -v identify >/dev/null 2>&1 && ! [ -x /usr/bin/identify ]; then
  exit 0 # no image validation available — refuse rather than trust blindly
fi
ID=/usr/bin/identify

info=$("$ID" -format "%m %wx%h" -- "$selection" 2>/dev/null) || exit 0
read -r ftype dims <<< "$info"
[[ $ftype =~ ^(PNG|JPEG|WEBP|AVIF|GIF)$ ]] || exit 0

bytes=$(/usr/bin/stat -c %s -- "$selection" 2>/dev/null) || exit 0
(( bytes <= 52428800 )) || exit 0 # 50 MiB

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