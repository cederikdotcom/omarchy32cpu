hl.on("hyprland.start", function()
  -- Slow app launch fix -- set systemd vars before starting session services.
  hl.exec_cmd("systemctl --user import-environment $(env | cut -d'=' -f 1)")
  hl.exec_cmd("dbus-update-activation-environment --systemd --all")

  hl.exec_cmd("omarchy-launch-shell")
  hl.exec_cmd("omarchy-provision-first-run")
  hl.exec_cmd("omarchy-powerprofiles-init")
  hl.exec_cmd(o.launch("omarchy-hyprland-monitor-watch"))

  -- FORK: the Quickshell desktop is not built here (no Qt software rendering
  -- yet), so its wallpaper and idle duties fall to swaybg and swayidle.
  -- omarchy-launch-shell above starts the rest of the stand-in shell (waybar
  -- and mako).
  hl.exec_cmd(o.launch('swaybg -m fill -i "$HOME/.local/state/omarchy/current/background"'))
  hl.exec_cmd(o.launch(
    "swayidle -w timeout 300 omarchy-system-lock" ..
    " timeout 600 'hyprctl dispatch dpms off' resume 'hyprctl dispatch dpms on'" ..
    " before-sleep omarchy-system-lock"
  ))

  -- FORK: udiskie is not in the Lite package set (no preinstalled apps).

  -- Run post-boot hooks after startup config has loaded.
  hl.exec_cmd("sleep 2 && omarchy-hook post-boot")
end)
