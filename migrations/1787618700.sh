echo "Store Hyprland input-device names as data instead of generated Lua"

# omarchy-toggle-input-device used to interpolate hyprctl device names into
# hyprctl eval and a generated Lua file. Those names come from USB descriptors,
# so recover the plain device name as data and delete the generated Lua. A name
# that could have broken out of the old Lua string literal is discarded, not
# trusted. The old script wrote to ~/.local/state regardless of XDG_STATE_HOME.
# Omarchy CPU keeps the recovered names under toggles/sway, where the current
# omarchy-toggle-input-device and the sway session re-apply read them.
toggles_dir="$HOME/.local/state/omarchy/toggles/hypr"
sway_toggles_dir="$HOME/.local/state/omarchy/toggles/sway"

reapply=0

for kind in touchpad touchscreen; do
  state_file="$toggles_dir/$kind-disabled.lua"
  name_file="$sway_toggles_dir/$kind-disabled-name"

  # An upstream install that already ran this migration under Hyprland left
  # the recovered name in the hypr dir; carry it over.
  if [[ -f $toggles_dir/$kind-disabled-name ]]; then
    if [[ -f $name_file ]]; then
      rm -f "$toggles_dir/$kind-disabled-name"
    else
      mkdir -p "$sway_toggles_dir"
      mv "$toggles_dir/$kind-disabled-name" "$name_file"
    fi
  fi

  [[ -f $state_file ]] || continue

  if [[ ! -f $name_file && -r $state_file ]]; then
    old=$(<"$state_file")
    pattern='^hl\.device\(\{ name = "([^"\\[:cntrl:]]+)", enabled = false \}\)$'
    if [[ $old =~ $pattern ]]; then
      mkdir -p "$sway_toggles_dir"
      printf '%s\n' "${BASH_REMATCH[1]}" >"$name_file"
    fi
  fi

  rm -f "$state_file"

  if [[ -f $name_file ]]; then
    reapply=1
  fi
done

# The disable only lives in sway state now, and the session that ran this
# migration has not applied it: reload so the exec_always re-apply in the
# default sway config picks the name file up, or the device the user switched
# off stays on until their next login.
if (( reapply )); then
  swaymsg reload >/dev/null 2>&1 || true
fi
