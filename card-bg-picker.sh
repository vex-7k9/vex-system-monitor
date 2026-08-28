#!/bin/bash

# omarchy:summary=Pick a background for the plugin hover card (reuses the desktop tile selector)
# omarchy:args=[current-image]
# omarchy:examples=card-bg-picker.sh ~/.local/state/omarchy/current/background

# Opens the same background carousel the Omarchy desktop uses
# (omarchy-menu-images -> image-selector), scoped to the theme and user
# background directories, and prints the chosen path so the plugin can persist
# it as its cardBackground setting. Prints nothing when the picker is
# dismissed, so a cancel never touches the card background.

current="$1"

theme_name=$(cat "$HOME/.local/state/omarchy/current/theme.name" 2>/dev/null)

dirs=("$HOME/.local/state/omarchy/current/theme/backgrounds")
if [[ -n $theme_name && -d "$HOME/.config/omarchy/backgrounds/$theme_name" ]]; then
  dirs+=("$HOME/.config/omarchy/backgrounds/$theme_name")
fi

selection=$(omarchy-menu-images --selected "${current:-}" "${dirs[@]}") || exit 0
[[ -n $selection ]] && printf '%s' "$selection"