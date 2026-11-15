#!/bin/bash
# Removes the Wasteland theme extras and puts Omarchy's stock lock screen, idle
# service, workspaces, clock and menu button back. Plugins are switched off with
# `omarchy plugin disable` / `enable`, so the shell edits its own shell.json.
# Refuses to run as root or while the screen is locked. Removed files are moved
# to ~/.local/state/omarchy/wasteland-backups/<timestamp>-uninstall/.
#
# The theme itself stays installed; pick another theme, or remove it with
# `omarchy theme remove wasteland`. Pass --purge to also delete your
# ~/.config/omarchy/wasteland/features.conf.
set -euo pipefail

export OMARCHY_SHELL_IPC_TIMEOUT=${OMARCHY_SHELL_IPC_TIMEOUT:-10s}
CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}"
STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
PLUGINS_DIR="$CONFIG/omarchy/plugins"
HYPR_DIR="$CONFIG/hypr"
BACKUP="$STATE_HOME/omarchy/wasteland-backups/$(date +%Y%m%d-%H%M%S)-uninstall"
PURGE=0
[[ ${1:-} == --purge ]] && PURGE=1

say() { printf '\033[32m==>\033[0m %s\n' "$*"; }
die() { printf '\033[31mError:\033[0m %s\n' "$*" >&2; exit 1; }
locked() {
  [[ $(omarchy-shell lock isLocked 2>/dev/null) == false ]] || return 0
  if command -v omarchy-hyprland-session-locked >/dev/null 2>&1 && omarchy-hyprland-session-locked; then return 0; fi
  return 1
}
require_unlocked() { locked && die "the screen is locked; unlock it and run this again. ${1:-}"; return 0; }
known() { omarchy-shell shell listPlugins | jq -e --arg id "$1" 'any(.[]; .id == $id)' >/dev/null; }
in_bar() { omarchy-shell shell listPlugins | jq -e --arg id "$1" 'any(.[]; .id == $id and .enabled)' >/dev/null; }

(( EUID != 0 )) || die "run this as your own user, not root."
require_unlocked
mkdir -p "$BACKUP"
[[ -f $CONFIG/omarchy/shell.json ]] && cp -a "$CONFIG/omarchy/shell.json" "$BACKUP/shell.json"

# 1. Put the stock pieces back through the shell.
if known wasteland.menubutton && in_bar wasteland.menubutton; then
  in_bar omarchy.menu || omarchy-plugin-enable omarchy.menu --before wasteland.menubutton
  sleep 1
  require_unlocked
  omarchy-plugin-disable wasteland.menubutton
  sleep 1
fi
for id in wasteland.clock wasteland.workspaces wasteland.idle wasteland.lock; do
  require_unlocked "Stopped before disabling $id; run this script again."
  if known "$id"; then omarchy-plugin-disable "$id" || true; sleep 1; fi
done
# Disabling a clone brings its original back; make sure of it for the two services.
for id in omarchy.lock omarchy.idle; do
  if jq -e --arg id "$id" '(.disabledPlugins // []) | index($id)' "$CONFIG/omarchy/shell.json" >/dev/null 2>&1; then
    require_unlocked
    omarchy-plugin-enable "$id"
    sleep 1
  fi
done

# 2. Move the files out.
require_unlocked "Stock pieces are back; run this script again to remove the files."
mkdir -p "$BACKUP/plugins"
for id in wasteland.lock wasteland.idle wasteland.workspaces wasteland.clock wasteland.menubutton; do
  [[ -e $PLUGINS_DIR/$id ]] && mv "$PLUGINS_DIR/$id" "$BACKUP/plugins/$id"
done
[[ -e $CONFIG/omarchy/hooks/theme-set.d/20-wasteland-extras ]] && mv "$CONFIG/omarchy/hooks/theme-set.d/20-wasteland-extras" "$BACKUP/"
[[ -L $HOME/.local/bin/wasteland-boot ]] && rm -f "$HOME/.local/bin/wasteland-boot"
[[ -e $HYPR_DIR/wasteland.lua ]] && mv "$HYPR_DIR/wasteland.lua" "$BACKUP/"
if [[ -f $HYPR_DIR/hyprland.lua ]] && grep -q 'require("hypr.wasteland")' "$HYPR_DIR/hyprland.lua"; then
  cp -a "$HYPR_DIR/hyprland.lua" "$BACKUP/hyprland.lua"
  grep -v -e 'require("hypr.wasteland")' -e '^-- Wasteland theme extras (remove with extras/uninstall.sh)$' "$HYPR_DIR/hyprland.lua" > "$HYPR_DIR/.hyprland.lua.new" || true
  mv "$HYPR_DIR/.hyprland.lua.new" "$HYPR_DIR/hyprland.lua"
fi
rm -f "$STATE_HOME/omarchy/wasteland-extras.json"
(( PURGE )) && rm -rf "$CONFIG/omarchy/wasteland"
omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true

say "Wasteland extras removed. Backups: $BACKUP"
echo "The theme is still installed. Switch away with: omarchy theme set <name>"
