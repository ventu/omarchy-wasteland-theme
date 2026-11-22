# Wasteland extras: shared paths and checks. Sourced by install.sh,
# uninstall.sh and bin/wasteland-lock-check; not meant to be run on its own.
#
# Paths: every Wasteland file sits under $HOME/.config and $HOME/.local/state,
# whatever XDG_CONFIG_HOME / XDG_STATE_HOME say. Omarchy's own commands work
# the same way (themes always live in $HOME/.config/omarchy/themes). A script
# run from a terminal can see different XDG variables than the shell started
# by Hyprland, and then the two would read and write different state files.
# Fixed paths rule that out.

WL_CONFIG="$HOME/.config"
WL_STATE_DIR="$HOME/.local/state/omarchy"
WL_THEME_DIR="$WL_CONFIG/omarchy/themes/wasteland"
WL_EXTRAS="$WL_THEME_DIR/extras"
WL_PLUGINS_DIR="$WL_CONFIG/omarchy/plugins"
WL_HOOK_DIR="$WL_CONFIG/omarchy/hooks/theme-set.d"
WL_HYPR_DIR="$WL_CONFIG/hypr"
WL_BIN_DIR="$HOME/.local/bin"
WL_USER_CONF_DIR="$WL_CONFIG/omarchy/wasteland"
WL_EXTRAS_STATE="$WL_STATE_DIR/wasteland-extras.json"
WL_THEME_NAME_FILE="$WL_STATE_DIR/current/theme.name"
# Version of the extras the installer last put in place (see extras/VERSION).
WL_INSTALLED_VERSION_FILE="$WL_USER_CONF_DIR/installed-version"
WL_PLUGIN_IDS=(wasteland.lock wasteland.idle wasteland.workspaces wasteland.clock wasteland.menubutton)

wl_say() { printf '\033[32m==>\033[0m %s\n' "$*"; }
wl_warn() { printf '\033[33mNote:\033[0m %s\n' "$*" >&2; }
wl_die() { printf '\033[31mError:\033[0m %s\n' "$*" >&2; exit 1; }

# The shell answers IPC at all.
wl_shell_up() { omarchy-shell shell listPlugins >/dev/null 2>&1; }

# A lock service is loaded and answering (prints true or false).
wl_lock_service_up() {
  local answer
  answer=$(omarchy-shell lock isLocked 2>/dev/null) || return 1
  [[ $answer == true || $answer == false ]]
}

# Prints locked, unlocked or unknown. Asks the lock service first, then
# Hyprland (omarchy-hyprland-session-locked: 0 locked, 1 unlocked,
# 2 undetermined). A lock service that is not answering is only "unlocked"
# when Hyprland confirms it.
wl_lock_state() {
  local answer session
  answer=$(omarchy-shell lock isLocked 2>/dev/null) || answer=""
  if command -v omarchy-hyprland-session-locked >/dev/null 2>&1; then
    omarchy-hyprland-session-locked >/dev/null 2>&1 && session=0 || session=$?
  else
    session=2
  fi
  if [[ $answer == true || $session == 0 ]]; then
    echo locked
  elif [[ $answer == false || $session == 1 ]]; then
    echo unlocked
  else
    echo unknown
  fi
}

# Stops the script unless the shell is up and the screen is unlocked. $1 is
# an extra hint for the user.
wl_require_unlocked() {
  wl_shell_up ||
    wl_die "the Omarchy shell isn't responding. Start it with omarchy-restart-shell, then run this again. ${1:-}"
  case $(wl_lock_state) in
    locked) wl_die "the screen is locked; unlock it and run this again. ${1:-}" ;;
    unknown) wl_die "can't tell whether the screen is locked: the lock service isn't answering and Hyprland can't say either. ${1:-}" ;;
  esac
  return 0
}

# Enabled lock or idle services that are copies of Omarchy's but not ours,
# one "id (copy of source)" per line. Two lock or idle services at once would
# both lock the screen and both start the screensaver.
wl_other_service_clones() {
  local ours
  ours=$(printf '%s\n' "${WL_PLUGIN_IDS[@]}" | jq -R . | jq -s .)
  omarchy-shell shell listPlugins 2>/dev/null | jq -r --argjson ours "$ours" '
    .[]
    | select(.enabled and (.clonedFrom == "omarchy.lock" or .clonedFrom == "omarchy.idle"))
    | select(.id as $id | $ours | index($id) | not)
    | "\(.id) (copy of \(.clonedFrom))"'
}

wl_plugin_enabled() {
  omarchy-shell shell listPlugins 2>/dev/null | jq -e --arg id "$1" 'any(.[]; .id == $id and .enabled)' >/dev/null
}
