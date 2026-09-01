hl.on("hyprland.start", function()
  -- Slow app launch fix -- set systemd vars before starting session services.
  hl.exec_cmd("systemctl --user import-environment $(env | cut -d'=' -f 1)")
  hl.exec_cmd("dbus-update-activation-environment --systemd --all")

  hl.exec_cmd("omarchy-launch-shell")
  hl.exec_cmd("omarchy-provision-first-run")
  hl.exec_cmd("omarchy-powerprofiles-init")
  hl.exec_cmd(o.launch("omarchy-hyprland-monitor-watch"))

  -- FORK: udiskie is not in the Lite package set (no preinstalled apps).
  -- Everything else upstream starts here is back: omarchy-launch-shell above
  -- runs Quickshell, whose own plugins own the wallpaper, the idle timeout and
  -- the lock screen, so the swaybg/swayidle stand-ins are gone.

  -- Run post-boot hooks after startup config has loaded.
  hl.exec_cmd("sleep 2 && omarchy-hook post-boot")
end)
