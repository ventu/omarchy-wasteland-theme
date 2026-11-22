#!/bin/bash
# Removes the Wasteland theme extras and puts Omarchy's stock lock screen, idle
# service, workspaces, clock and menu button back. Plugins are switched off with
# `omarchy plugin disable` / `enable`, so the shell edits its own shell.json.
# Refuses to run as root, while the screen is locked or while the shell isn't
# answering. Removed files are moved to
# ~/.local/state/omarchy/wasteland-backups/<timestamp>-uninstall/.
#
# The theme itself stays installed; pick another theme, or remove it with
# `omarchy theme remove wasteland`. Pass --purge to also delete your
# ~/.config/omarchy/wasteland/features.conf.
set -euo pipefail

export OMARCHY_SHELL_IPC_TIMEOUT=${OMARCHY_SHELL_IPC_TIMEOUT:-10s}
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$HERE/lib/common.sh"

BACKUP="$WL_STATE_DIR/wasteland-backups/$(date +%Y%m%d-%H%M%S)-uninstall"
PURGE=0
[[ ${1:-} == --purge ]] && PURGE=1

known() { omarchy-shell shell listPlugins | jq -e --arg id "$1" 'any(.[]; .id == $id)' >/dev/null; }

(( EUID != 0 )) || wl_die "run this as your own user, not root."
wl_require_unlocked
mkdir -p "$BACKUP"
[[ -f $WL_CONFIG/omarchy/shell.json ]] && cp -a "$WL_CONFIG/omarchy/shell.json" "$BACKUP/shell.json"

# 1. Put the stock pieces back through the shell.
if known wasteland.menubutton && wl_plugin_enabled wasteland.menubutton; then
  wl_plugin_enabled omarchy.menu || omarchy-plugin-enable omarchy.menu --before wasteland.menubutton
  sleep 1
  wl_require_unlocked
  omarchy-plugin-disable wasteland.menubutton
  sleep 1
fi
for id in wasteland.clock wasteland.workspaces wasteland.idle wasteland.lock; do
  wl_require_unlocked "Stopped before disabling $id; run this script again."
  if known "$id"; then omarchy-plugin-disable "$id" || true; sleep 1; fi
done
# Disabling a clone brings its original back; make sure of it for the two services.
for id in omarchy.lock omarchy.idle; do
  if jq -e --arg id "$id" '(.disabledPlugins // []) | index($id)' "$WL_CONFIG/omarchy/shell.json" >/dev/null 2>&1; then
    wl_require_unlocked
    omarchy-plugin-enable "$id"
    sleep 1
  fi
done

# 2. Move the files out.
wl_require_unlocked "Stock pieces are back; run this script again to remove the files."
mkdir -p "$BACKUP/plugins"
for id in "${WL_PLUGIN_IDS[@]}"; do
  [[ -e $WL_PLUGINS_DIR/$id ]] && mv "$WL_PLUGINS_DIR/$id" "$BACKUP/plugins/$id"
done
[[ -e $WL_HOOK_DIR/20-wasteland-extras ]] && mv "$WL_HOOK_DIR/20-wasteland-extras" "$BACKUP/"
[[ -L $WL_BIN_DIR/wasteland-boot ]] && rm -f "$WL_BIN_DIR/wasteland-boot"
[[ -e $WL_HYPR_DIR/wasteland.lua ]] && mv "$WL_HYPR_DIR/wasteland.lua" "$BACKUP/"
if [[ -f $WL_HYPR_DIR/hyprland.lua ]] && grep -q 'require("hypr.wasteland")' "$WL_HYPR_DIR/hyprland.lua"; then
  cp -a "$WL_HYPR_DIR/hyprland.lua" "$BACKUP/hyprland.lua"
  grep -v -e 'require("hypr.wasteland")' -e '^-- Wasteland theme extras (remove with extras/uninstall.sh)$' "$WL_HYPR_DIR/hyprland.lua" > "$WL_HYPR_DIR/.hyprland.lua.new" || true
  mv "$WL_HYPR_DIR/.hyprland.lua.new" "$WL_HYPR_DIR/hyprland.lua"
fi
rm -f "$WL_EXTRAS_STATE" "$WL_INSTALLED_VERSION_FILE" "$WL_STATE_DIR/wasteland-stale-notified"
(( PURGE )) && rm -rf "$WL_USER_CONF_DIR"
omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true

wl_say "Wasteland extras removed. Backups: $BACKUP"
echo "The theme is still installed. Switch away with: omarchy theme set <name>"
