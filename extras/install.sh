#!/bin/bash
# Wasteland theme extras installer (optional add-on).
#
# Installs the five Wasteland shell plugins, the theme-set hook, the Hyprland
# rules file and the boot animation link. Plugins are switched on with
# `omarchy plugin enable`, so the shell edits its own shell.json. This script
# never writes shell.json itself.
#
# Safe to run more than once. Refuses to run as root or while the screen is
# locked. Everything it replaces is copied to
# ~/.local/state/omarchy/wasteland-backups/<timestamp>/ first.
#
# Install the theme first:  omarchy theme install https://github.com/<you>/omarchy-wasteland-theme
# Then:                     bash ~/.config/omarchy/themes/wasteland/extras/install.sh
set -euo pipefail

export OMARCHY_SHELL_IPC_TIMEOUT=${OMARCHY_SHELL_IPC_TIMEOUT:-10s}
CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}"
STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
THEME_DIR="$CONFIG/omarchy/themes/wasteland"
EXTRAS="$THEME_DIR/extras"
PLUGINS_DIR="$CONFIG/omarchy/plugins"
HOOK_DIR="$CONFIG/omarchy/hooks/theme-set.d"
HYPR_DIR="$CONFIG/hypr"
BIN_DIR="$HOME/.local/bin"
USER_CONF_DIR="$CONFIG/omarchy/wasteland"
BACKUP="$STATE_HOME/omarchy/wasteland-backups/$(date +%Y%m%d-%H%M%S)"
PLUGIN_IDS=(wasteland.lock wasteland.idle wasteland.workspaces wasteland.clock wasteland.menubutton)

say() { printf '\033[32m==>\033[0m %s\n' "$*"; }
die() { printf '\033[31mError:\033[0m %s\n' "$*" >&2; exit 1; }

locked() {
  [[ $(omarchy-shell lock isLocked 2>/dev/null) == false ]] || return 0
  if command -v omarchy-hyprland-session-locked >/dev/null 2>&1 && omarchy-hyprland-session-locked; then return 0; fi
  return 1
}
require_unlocked() { locked && die "the screen is locked; unlock it and run this again. ${1:-}"; return 0; }

(( EUID != 0 )) || die "run this as your own user, not root (no sudo needed)."
for cmd in omarchy-shell omarchy-plugin-enable omarchy-plugin-disable jq python3; do
  command -v "$cmd" >/dev/null 2>&1 || die "'$cmd' not found. This add-on needs Omarchy 4.5 or newer."
done
[[ -f $EXTRAS/on-theme-set && -d $EXTRAS/plugins ]] ||
  die "the Wasteland theme is not installed at $THEME_DIR. Run: omarchy theme install <repo-url>"
require_unlocked

mkdir -p "$BACKUP" "$PLUGINS_DIR" "$HOOK_DIR" "$HYPR_DIR" "$BIN_DIR" "$USER_CONF_DIR"
[[ -f $CONFIG/omarchy/shell.json ]] && cp -a "$CONFIG/omarchy/shell.json" "$BACKUP/shell.json"
say "Backups go to $BACKUP"

# 1. Plugins. Each is staged beside the target and moved into place.
upgraded=0
for id in "${PLUGIN_IDS[@]}"; do
  src="$EXTRAS/plugins/$id" dest="$PLUGINS_DIR/$id" stage="$PLUGINS_DIR/.$id.new"
  [[ -d $src ]] || die "missing $src"
  rm -rf "$stage"
  cp -r "$src" "$stage"
  if [[ -e $dest ]]; then
    upgraded=1
    mkdir -p "$BACKUP/plugins"
    mv "$dest" "$BACKUP/plugins/$id"
  fi
  mv "$stage" "$dest"
done
say "Plugins copied to $PLUGINS_DIR"

# 2. Hook, feature switches, boot link, Hyprland rules.
[[ -e $HOOK_DIR/20-wasteland-extras ]] && cp -a "$HOOK_DIR/20-wasteland-extras" "$BACKUP/"
install -m 755 "$EXTRAS/hooks/20-wasteland-extras" "$HOOK_DIR/20-wasteland-extras"
[[ -f $USER_CONF_DIR/features.conf ]] || install -m 644 "$EXTRAS/features.conf" "$USER_CONF_DIR/features.conf"
ln -sfn "$EXTRAS/bin/wasteland-boot" "$BIN_DIR/wasteland-boot"
[[ -e $HYPR_DIR/wasteland.lua ]] && cp -a "$HYPR_DIR/wasteland.lua" "$BACKUP/"
install -m 644 "$EXTRAS/hypr/wasteland.lua" "$HYPR_DIR/wasteland.lua"
if [[ -f $HYPR_DIR/hyprland.lua ]] && ! grep -q 'require("hypr.wasteland")' "$HYPR_DIR/hyprland.lua"; then
  cp -a "$HYPR_DIR/hyprland.lua" "$BACKUP/hyprland.lua"
  { cat "$HYPR_DIR/hyprland.lua"; printf '\n-- Wasteland theme extras (remove with extras/uninstall.sh)\nrequire("hypr.wasteland")\n'; } > "$HYPR_DIR/.hyprland.lua.new"
  mv "$HYPR_DIR/.hyprland.lua.new" "$HYPR_DIR/hyprland.lua"
  say "Added require(\"hypr.wasteland\") to $HYPR_DIR/hyprland.lua"
elif [[ ! -f $HYPR_DIR/hyprland.lua ]]; then
  echo "Note: $HYPR_DIR/hyprland.lua not found; add require(\"hypr.wasteland\") to your Hyprland config yourself."
fi

# 3. State file, written before the plugins load so their file watches find it.
# Creating it first also stops on-theme-set from scheduling a shell restart.
mkdir -p "$STATE_HOME/omarchy"
[[ -f $STATE_HOME/omarchy/wasteland-extras.json ]] || : > "$STATE_HOME/omarchy/wasteland-extras.json"
bash "$EXTRAS/on-theme-set" "$(cat "$STATE_HOME/omarchy/current/theme.name" 2>/dev/null || echo "")"

# 4. Let the shell see the new plugins, then switch them on.
require_unlocked "Files are in place; run this script again to switch the plugins on."
omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
for _ in $(seq 1 20); do
  known=$(omarchy-shell shell listPlugins 2>/dev/null | jq -r '.[].id' 2>/dev/null || true)
  missing=0
  for id in "${PLUGIN_IDS[@]}"; do grep -qx "$id" <<<"$known" || missing=1; done
  (( missing )) || break
  sleep 0.5
done
(( missing == 0 )) || die "the shell did not pick up the plugins. Run: omarchy-shell shell rescanPlugins, then this script again."

in_bar() { omarchy-shell shell listPlugins | jq -e --arg id "$1" 'any(.[]; .id == $id and .enabled)' >/dev/null; }

for id in wasteland.lock wasteland.idle wasteland.workspaces wasteland.clock; do
  require_unlocked "Stopped before enabling $id; run this script again."
  omarchy-plugin-enable "$id"
  sleep 1
done

require_unlocked "Stopped before the menu button; run this script again."
if ! in_bar wasteland.menubutton; then
  if in_bar omarchy.menu; then
    omarchy-plugin-enable wasteland.menubutton --before omarchy.menu
    sleep 1
    require_unlocked "Stopped before removing the stock menu button; run: omarchy plugin disable omarchy.menu"
    # A bar widget's "disable" only takes it off the bar; the Omarchy menu itself keeps working.
    omarchy-plugin-disable omarchy.menu
  else
    omarchy-plugin-enable wasteland.menubutton left --index 0
  fi
fi

if (( upgraded )); then
  # The shell caches compiled QML by path, so updated plugin files need a restart.
  require_unlocked "Restart the shell yourself once unlocked: omarchy-restart-shell"
  say "Restarting the shell to load the updated plugins"
  omarchy-restart-shell || true
fi

say "Wasteland extras installed."
echo "Apply the theme if it is not active yet:  omarchy theme set wasteland"
echo "Turn single extras off in:                $USER_CONF_DIR/features.conf"
echo "Remove everything again:                  bash $EXTRAS/uninstall.sh"
