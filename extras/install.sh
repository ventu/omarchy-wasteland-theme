#!/bin/bash
# Wasteland theme extras installer (optional add-on).
#
# Installs the five Wasteland shell plugins, the theme-set hook, the Hyprland
# rules file and the boot animation link. Plugins are switched on with
# `omarchy plugin enable`, so the shell edits its own shell.json. This script
# never writes shell.json itself.
#
# Safe to run more than once. Refuses to run as root, while the screen is
# locked, while the shell isn't answering, or while another copy of Omarchy's
# lock or idle service is enabled. Everything it replaces is copied to
# ~/.local/state/omarchy/wasteland-backups/<timestamp>/ first.
#
# Install the theme first:  omarchy theme install https://github.com/ventu/omarchy-wasteland-theme
# Then:                     bash ~/.config/omarchy/themes/wasteland/extras/install.sh
set -euo pipefail

export OMARCHY_SHELL_IPC_TIMEOUT=${OMARCHY_SHELL_IPC_TIMEOUT:-10s}
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$HERE/lib/common.sh"

BACKUP="$WL_STATE_DIR/wasteland-backups/$(date +%Y%m%d-%H%M%S)"
VERSION=$({ tr -d "[:space:]" < "$WL_EXTRAS/VERSION"; } 2>/dev/null || echo unknown)

(( EUID != 0 )) || wl_die "run this as your own user, not root (no sudo needed)."
for cmd in omarchy-shell omarchy-plugin-enable omarchy-plugin-disable jq python3; do
  command -v "$cmd" >/dev/null 2>&1 || wl_die "'$cmd' not found. This add-on needs Omarchy 4.5 or newer."
done
[[ -f $WL_EXTRAS/on-theme-set && -d $WL_EXTRAS/plugins ]] ||
  wl_die "the Wasteland theme is not installed at $WL_THEME_DIR. Run: omarchy theme install <repo-url>"
wl_require_unlocked

# Another lock or idle service (your own clone of omarchy.lock or omarchy.idle,
# or another theme's) would run next to Wasteland's: two lock screens, two
# screensavers. Stop before changing anything.
others=$(wl_other_service_clones)
if [[ -n $others ]]; then
  printf '\033[31mError:\033[0m another lock or idle plugin is enabled:\n' >&2
  sed 's/^/  /' <<<"$others" >&2
  ids=$(cut -d' ' -f1 <<<"$others" | tr '\n' ' ')
  printf 'Wasteland brings its own, and two would run side by side. Turn yours off first:\n' >&2
  for id in $ids; do printf '  omarchy plugin disable %s\n' "$id" >&2; done
  printf 'then run this again. (Disabling a copy brings Omarchy'"'"'s original back until then.)\n' >&2
  exit 1
fi

# Only the shutdown/reboot CRT effect needs PyGObject; everything else works without it.
if ! /usr/bin/python3 -c 'import gi; gi.require_version("Gio", "2.0")' 2>/dev/null; then
  wl_warn "PyGObject is missing, so the CRT power-off before shutdown and reboot won't play."
  wl_warn "Install it with: omarchy pkg add python-gobject"
fi

mkdir -p "$BACKUP" "$WL_PLUGINS_DIR" "$WL_HOOK_DIR" "$WL_HYPR_DIR" "$WL_BIN_DIR" "$WL_USER_CONF_DIR"
[[ -f $WL_CONFIG/omarchy/shell.json ]] && cp -a "$WL_CONFIG/omarchy/shell.json" "$BACKUP/shell.json"
wl_say "Installing Wasteland extras $VERSION. Backups go to $BACKUP"

# 1. Plugins. Each is staged beside the target and moved into place.
upgraded=0
for id in "${WL_PLUGIN_IDS[@]}"; do
  src="$WL_EXTRAS/plugins/$id" dest="$WL_PLUGINS_DIR/$id" stage="$WL_PLUGINS_DIR/.$id.new"
  [[ -d $src ]] || wl_die "missing $src"
  rm -rf "$stage"
  cp -r "$src" "$stage"
  if [[ -e $dest ]]; then
    upgraded=1
    mkdir -p "$BACKUP/plugins"
    mv "$dest" "$BACKUP/plugins/$id"
  fi
  mv "$stage" "$dest"
done
wl_say "Plugins copied to $WL_PLUGINS_DIR"

# 2. Hook, feature switches, boot link, Hyprland rules.
[[ -e $WL_HOOK_DIR/20-wasteland-extras ]] && cp -a "$WL_HOOK_DIR/20-wasteland-extras" "$BACKUP/"
install -m 755 "$WL_EXTRAS/hooks/20-wasteland-extras" "$WL_HOOK_DIR/20-wasteland-extras"
[[ -f $WL_USER_CONF_DIR/features.conf ]] || install -m 644 "$WL_EXTRAS/features.conf" "$WL_USER_CONF_DIR/features.conf"
ln -sfn "$WL_EXTRAS/bin/wasteland-boot" "$WL_BIN_DIR/wasteland-boot"
[[ -e $WL_HYPR_DIR/wasteland.lua ]] && cp -a "$WL_HYPR_DIR/wasteland.lua" "$BACKUP/"
install -m 644 "$WL_EXTRAS/hypr/wasteland.lua" "$WL_HYPR_DIR/wasteland.lua"
if [[ -f $WL_HYPR_DIR/hyprland.lua ]] && ! grep -q 'require("hypr.wasteland")' "$WL_HYPR_DIR/hyprland.lua"; then
  cp -a "$WL_HYPR_DIR/hyprland.lua" "$BACKUP/hyprland.lua"
  { cat "$WL_HYPR_DIR/hyprland.lua"; printf '\n-- Wasteland theme extras (remove with extras/uninstall.sh)\nrequire("hypr.wasteland")\n'; } > "$WL_HYPR_DIR/.hyprland.lua.new"
  mv "$WL_HYPR_DIR/.hyprland.lua.new" "$WL_HYPR_DIR/hyprland.lua"
  wl_say "Added require(\"hypr.wasteland\") to $WL_HYPR_DIR/hyprland.lua"
elif [[ ! -f $WL_HYPR_DIR/hyprland.lua ]]; then
  wl_warn "$WL_HYPR_DIR/hyprland.lua not found; add require(\"hypr.wasteland\") to your Hyprland config yourself."
fi

# 3. State file, written before the plugins load so their file watches find it.
# Creating it first also stops on-theme-set from scheduling a shell restart.
# The version marker goes first too, so on-theme-set doesn't report the
# plugins as out of date.
printf '%s\n' "$VERSION" > "$WL_INSTALLED_VERSION_FILE"
mkdir -p "$WL_STATE_DIR"
[[ -f $WL_EXTRAS_STATE ]] || : > "$WL_EXTRAS_STATE"
WASTELAND_NO_LOCK_CHECK=1 bash "$WL_EXTRAS/on-theme-set" "$(cat "$WL_THEME_NAME_FILE" 2>/dev/null || echo "")"

# 4. Let the shell see the new plugins, then switch them on.
wl_require_unlocked "Files are in place; run this script again to switch the plugins on."
omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
missing=1
for _ in $(seq 1 20); do
  known=$(omarchy-shell shell listPlugins 2>/dev/null | jq -r '.[].id' 2>/dev/null || true)
  missing=0
  for id in "${WL_PLUGIN_IDS[@]}"; do grep -qx "$id" <<<"$known" || missing=1; done
  (( missing )) || break
  sleep 0.5
done
(( missing == 0 )) || wl_die "the shell did not pick up the plugins. Run: omarchy-shell shell rescanPlugins, then this script again."

for id in wasteland.lock wasteland.idle wasteland.workspaces wasteland.clock; do
  wl_require_unlocked "Stopped before enabling $id; run this script again."
  omarchy-plugin-enable "$id"
  sleep 1
done

wl_require_unlocked "Stopped before the menu button; run this script again."
if ! wl_plugin_enabled wasteland.menubutton; then
  if wl_plugin_enabled omarchy.menu; then
    omarchy-plugin-enable wasteland.menubutton --before omarchy.menu
    sleep 1
    wl_require_unlocked "Stopped before removing the stock menu button; run: omarchy plugin disable omarchy.menu"
    # A bar widget's "disable" only takes it off the bar; the Omarchy menu itself keeps working.
    omarchy-plugin-disable omarchy.menu
  else
    omarchy-plugin-enable wasteland.menubutton left --index 0
  fi
fi

if (( upgraded )); then
  # The shell caches compiled QML by path, so updated plugin files need a restart.
  wl_require_unlocked "Restart the shell yourself once unlocked: omarchy-restart-shell"
  wl_say "Restarting the shell to load the updated plugins"
  omarchy-restart-shell || true
fi

# 5. Make sure a lock screen actually loaded. If wasteland.lock failed, this
# hands the lock back to Omarchy's and says so.
if [[ -x $WL_EXTRAS/bin/wasteland-lock-check ]]; then
  "$WL_EXTRAS/bin/wasteland-lock-check" ||
    wl_die "the Wasteland lock screen didn't load, so Omarchy's lock screen is back on. Details: journalctl --user -t wasteland-lock-check"
fi

wl_say "Wasteland extras $VERSION installed."
echo "Apply the theme if it is not active yet:  omarchy theme set wasteland"
echo "Turn single extras off in:                $WL_USER_CONF_DIR/features.conf"
echo "Remove everything again:                  bash $WL_EXTRAS/uninstall.sh"
