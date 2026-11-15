-- Wasteland theme extras for Hyprland. Installed to ~/.config/hypr/wasteland.lua
-- by the theme's extras/install.sh, which adds require("hypr.wasteland") to
-- ~/.config/hypr/hyprland.lua. uninstall.sh removes both.

-- Boot animation window (class org.wasteland.boot): fullscreen, opaque, no
-- blur, shadow, border or animation. No workspace is assigned, so it stays on
-- the current one.
o.window("^org\\.wasteland\\.boot$", {
  fullscreen = true,
  no_anim = true,
  opaque = true,
  no_blur = true,
  no_shadow = true,
  border_size = 0,
  rounding = 0,
  opacity = "1.0 override 1.0 override 1.0 override",
  tag = "-default-opacity",
})

-- The wasteland.lock plugin draws the CRT power effects on these layers, so
-- Hyprland must not fade them in or out.
hl.layer_rule({ match = { namespace = "^(wasteland-crt|omarchy-lock-preview)$" }, no_anim = true, animation = "none" })

-- Boot animation after login. It checks the Wasteland extras itself and exits
-- at once when BOOT is off or another theme is in use.
o.exec_on_start("sleep 1 && " .. o.launch(os.getenv("HOME") .. "/.local/bin/wasteland-boot"))
