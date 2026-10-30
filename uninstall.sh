#!/bin/bash
# Remove what install.sh set up. Keeps your login (~/.config/ytm-bar) unless --purge.
set -euo pipefail

NAME=ytm-bar
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ID="$(sed -n 's/.*"id": *"\([^"]*\)".*/\1/p' "$REPO/manifest.json" | head -1)"
purge=0
[[ ${1:-} == --purge ]] && purge=1

unlink_if_ours() {  # only remove links that point into this repo
  local dst=$1
  if [[ -L $dst && "$(readlink -f "$dst")" == "$REPO"* ]]; then
    rm "$dst" && echo "    removed $dst"
  fi
}

remove_block() {
  local target=$1
  [[ -f $target ]] && grep -q ">>> $NAME >>>" "$target" || return 0
  sed -i "/>>> $NAME >>>/,/<<< $NAME <<</d" "$target"
  echo "    removed ytm-bar block from $target"
}

echo "==> Uninstalling $NAME"
systemctl --user disable --now ytm-bar.service >/dev/null 2>&1 || true
unlink_if_ours "$HOME/.config/systemd/user/ytm-bar.service"
systemctl --user daemon-reload || true
unlink_if_ours "$HOME/.local/bin/ytm-bar"
unlink_if_ours "$HOME/.local/bin/ytm-tui"
unlink_if_ours "$HOME/.local/bin/ytm-panel"

if command -v omarchy >/dev/null 2>&1; then
  omarchy plugin disable "$PLUGIN_ID" >/dev/null 2>&1 || true
  unlink_if_ours "$HOME/.config/omarchy/plugins/$PLUGIN_ID"
fi
remove_block "$HOME/.config/hypr/bindings.lua"
remove_block "$HOME/.config/hypr/autostart.lua"
hyprctl reload >/dev/null 2>&1 || true
remove_block "$(readlink -f "$HOME/.config/i3/config")"
i3-msg reload >/dev/null 2>&1 || true

rm -rf "${XDG_STATE_HOME:-$HOME/.local/state}/ytm-bar"
if (( purge )); then
  rm -rf "$HOME/.config/ytm-bar"
  echo "    removed the YouTube Music login"
else
  echo "    kept ~/.config/ytm-bar (YouTube Music login) — use --purge to remove it"
fi
echo "==> Done"
