#!/bin/bash
# Install ytm-bar: the YouTube Music widget for the Omarchy bar.
#
#   ./install.sh                install, put the widget first in the bar's right
#                               section, start the player service and add the
#                               keybinding
#   ./install.sh --no-bindings  skip the keybinding (and the blur)
#   ./install.sh --no-blur      leave Hyprland's blur as it is
#
# Safe to run again: links are refreshed and config blocks (between "ytm-bar"
# marker comments, which uninstall.sh removes) are replaced with the latest.
set -euo pipefail

NAME=ytm-bar
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ID="$(sed -n 's/.*"id": *"\([^"]*\)".*/\1/p' "$REPO/manifest.json" | head -1)"
BIN="$HOME/.local/bin"
UNITS="$HOME/.config/systemd/user"
PACKAGES=(mpv yt-dlp python-ytmusicapi mpv-mpris python-pillow)

bindings=1
blur=1
for arg in "$@"; do
  case "$arg" in
    --no-bindings) bindings=0 ;;
    --no-blur) blur=0 ;;
    -h|--help) sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done

if ! command -v omarchy-shell >/dev/null 2>&1; then
  echo "This plugin needs Omarchy (omarchy-shell not found)." >&2
  exit 1
fi
echo "==> Installing $NAME from $REPO"

link() {  # link SOURCE TARGET — replace an existing link, back up a real file
  local src=$1 dst=$2
  mkdir -p "$(dirname "$dst")"
  if [[ -e $dst && ! -L $dst ]]; then
    mv "$dst" "$dst.bak.$(date +%s)"
    echo "    backed up existing $dst"
  fi
  ln -sfn "$src" "$dst"
  echo "    $dst -> $src"
}

add_block() {  # add_block SNIPPET TARGET — append between markers, replacing an older copy
  local snippet=$1 target=$2
  mkdir -p "$(dirname "$target")"
  touch "$target"
  if grep -q ">>> $NAME >>>" "$target"; then
    sed -i "/>>> $NAME >>>/,/<<< $NAME <<</d" "$target"
    cat "$snippet" >>"$target"
    echo "    updated $target"
  else
    printf '\n' >>"$target"
    cat "$snippet" >>"$target"
    echo "    added to $target"
  fi
}

remove_block() {
  local target=$1
  [[ -f $target ]] && grep -q ">>> $NAME >>>" "$target" || return 0
  sed -i "/>>> $NAME >>>/,/<<< $NAME <<</d" "$target"
  echo "    removed the old ytm-bar block from $target"
}

chmod +x "$REPO/bin/"*

echo "--> Packages"
missing=()
for pkg in "${PACKAGES[@]}"; do
  pacman -Q "$pkg" >/dev/null 2>&1 || missing+=("$pkg")
done
if (( ${#missing[@]} )); then
  echo "    ! missing: ${missing[*]} — run: omarchy pkg add ${missing[*]}"
else
  echo "    mpv, yt-dlp, ytmusicapi, mpv-mpris and pillow are installed"
fi

echo "--> Scripts"
link "$REPO/bin/ytm-bar" "$BIN/ytm-bar"
link "$REPO/bin/ytm-tui" "$BIN/ytm-tui"

echo "--> Player service"
link "$REPO/systemd/ytm-bar.service" "$UNITS/ytm-bar.service"
systemctl --user daemon-reload
systemctl --user enable ytm-bar.service >/dev/null 2>&1
# Don't restart a running service: that would interrupt the music (it comes back
# paused, at the same spot).
if systemctl --user is-active --quiet ytm-bar.service; then
  echo "    ytm-bar.service is running — 'systemctl --user restart ytm-bar' loads a newer bin/ytm-bar (music resumes paused)"
else
  systemctl --user start ytm-bar.service
  echo "    ytm-bar.service enabled and started"
fi

echo "--> Omarchy bar plugin ($PLUGIN_ID)"
plugin_dir="$HOME/.config/omarchy/plugins/$PLUGIN_ID"
if [[ "$(readlink -f "$plugin_dir" 2>/dev/null)" == "$REPO" ]]; then
  echo "    plugin folder is this repo"
elif [[ -e $plugin_dir ]]; then
  echo "    $plugin_dir already exists and is not this repo — move it away first" >&2
  exit 1
else
  link "$REPO" "$plugin_dir"
fi
# A freshly linked plugin isn't known to the running shell until it rescans.
omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
if ! jq -e --arg id "$PLUGIN_ID" '[.bar.layout[]?[]?.id] | index($id)' "$HOME/.config/omarchy/shell.json" >/dev/null 2>&1; then
  # Right section, first: the pill's width follows the title, and in the centred
  # middle section every song change would shift the clock.
  omarchy plugin enable "$PLUGIN_ID" --section right >/dev/null
  first="$(jq -r '.bar.layout.right[0].id // empty' "$HOME/.config/omarchy/shell.json" 2>/dev/null)"
  [[ -n $first && $first != "$PLUGIN_ID" ]] && omarchy bar move "$PLUGIN_ID" --section right --before "$first" >/dev/null 2>&1 || true
  echo "    added to the bar (start of the right section)"
else
  echo "    already in the bar"
fi
if (( bindings )); then
  hypr_bindings="$HOME/.config/hypr/bindings.lua"
  snippet="$REPO/omarchy/bindings.lua"
  # The card can't be blurred while Hyprland's blur is off (Omarchy's default).
  # Then the block turns it on too, for the card alone (omarchy/blur.lua). Kept
  # on a re-run, when it's the block's own lines that turned blur on.
  if (( blur )) && { grep -q "install.sh adds this only" "$hypr_bindings" 2>/dev/null ||
       hyprctl getoption decoration:blur:enabled 2>/dev/null | grep -q false; }; then
    snippet="$(mktemp)"
    trap 'rm -f "$snippet"' EXIT
    { sed '$d' "$REPO/omarchy/bindings.lua"; cat "$REPO/omarchy/blur.lua"; tail -1 "$REPO/omarchy/bindings.lua"; } >"$snippet"
    echo "    Hyprland's blur was off: turning it on for the card only (--no-blur to skip)"
  fi
  add_block "$snippet" "$hypr_bindings"
fi
# The Pear Desktop version started the app at login; the service replaces that.
remove_block "$HOME/.config/hypr/autostart.lua"
hyprctl reload >/dev/null 2>&1 || true

echo "--> Account"
if [[ -s $HOME/.config/ytm-bar/browser.json ]]; then
  echo "    logged in — 'ytm-bar logout' to forget it"
else
  echo "    not logged in: search and radio work; run 'ytm-bar login' to like songs"
fi
echo "==> Done"
