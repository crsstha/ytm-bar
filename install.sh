#!/bin/bash
# Install ytm-bar: the YouTube Music (Pear Desktop) widget for the Omarchy bar.
#
#   ./install.sh                install, put the widget after the clock, add the
#                               keybinding + hidden-window rule
#   ./install.sh --no-bindings  skip the keybinding and window rule
#   ./install.sh --autostart    also start YouTube Music (hidden) at login
#
# Safe to run again: links are refreshed and config blocks (between "ytm-bar"
# marker comments, which uninstall.sh removes) are replaced with the latest.
set -euo pipefail

NAME=ytm-bar
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ID="$(sed -n 's/.*"id": *"\([^"]*\)".*/\1/p' "$REPO/manifest.json" | head -1)"
BIN="$HOME/.local/bin"
PORT="${YTM_BAR_PORT:-26538}"

bindings=1
autostart=0
for arg in "$@"; do
  case "$arg" in
    --no-bindings) bindings=0 ;;
    --autostart) autostart=1 ;;
    -h|--help) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
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

chmod +x "$REPO/bin/"*

echo "--> Script"
link "$REPO/bin/ytm-bar" "$BIN/ytm-bar"

echo "--> YouTube Music (Pear Desktop)"
if command -v youtube-music >/dev/null 2>&1; then
  echo "    installed"
else
  echo "    ! not installed — run: omarchy pkg aur add pear-desktop-bin"
fi
code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 "http://127.0.0.1:$PORT/api/v1/song" || true)"
case "$code" in
  401|403) echo "    API Server is on (port $PORT)" ;;
  200|204) echo "    API Server is on (port $PORT) — but without auth; consider 'Authorize at first request'" ;;
  *) echo "    ! API Server not reachable on port $PORT — open YouTube Music, then"
     echo "      Plugins → API Server → enable, authorization: \"Authorize at first request\"" ;;
esac

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
  omarchy plugin enable "$PLUGIN_ID" --section center >/dev/null
  omarchy bar move "$PLUGIN_ID" --after omarchy.clock >/dev/null 2>&1 || true
  echo "    added to the bar (center, after the clock)"
else
  echo "    already in the bar"
fi
(( bindings )) && add_block "$REPO/omarchy/bindings.lua" "$HOME/.config/hypr/bindings.lua"
(( autostart )) && add_block "$REPO/omarchy/autostart.lua" "$HOME/.config/hypr/autostart.lua"
hyprctl reload >/dev/null 2>&1 || true

echo "--> Keep running in the tray"
pear_config="$HOME/.config/YouTube Music/config.json"
if [[ -f $pear_config ]] && jq -e '.options.tray == true' "$pear_config" >/dev/null 2>&1; then
  echo "    tray is on"
else
  echo "    ! turn on YouTube Music's tray (Options → Tray → Enabled) so closing the"
  echo "      window doesn't quit the app"
fi

echo "--> Token"
if [[ -s $HOME/.config/ytm-bar/token ]]; then
  echo "    connected — 'ytm-bar auth' asks for a new token"
else
  echo "    click the widget's \"Connect\" (or run 'ytm-bar auth') and approve it in YouTube Music"
fi
echo "==> Done"
