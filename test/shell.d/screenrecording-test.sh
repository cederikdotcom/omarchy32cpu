#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

stub_bin="$tmp_dir/bin"
mkdir -p "$stub_bin"

cat >"$stub_bin/v4l2-ctl" <<'SH'
#!/bin/bash

[[ ${OMARCHY_TEST_NO_WEBCAM:-false} == "true" ]] && exit 0

case "$1" in
--list-devices)
  printf '%s\n' "ipu6 (PCI:0000:00:05.0):"
  printf '\t%s\n' "/dev/video0"
  printf '\t%s\n' "/dev/video1"

  if [[ ${OMARCHY_TEST_RAW_WEBCAM:-false} != "true" ]]; then
    printf '\n%s\n' "Built-in Webcam: Integrated Camera"
    printf '\t%s\n' "/dev/video42"
    printf '\t%s\n' "/dev/video43"
    printf '\n%s\n' "USB Capture Card: External Camera"
    printf '\t%s\n' "/dev/video2"
  fi

  if [[ ${OMARCHY_TEST_DUAL_NODE_WEBCAM:-false} == "true" ]]; then
    printf '\n%s\n' "Dual Node Camera: ISP Wrapper"
    printf '\t%s\n' "/dev/video7"
    printf '\t%s\n' "/dev/video8"
    printf '\n%s\n' "Metadata Only: Sensor"
    printf '\t%s\n' "/dev/video9"
  fi
  ;;
--device)
  case "$2" in
  /dev/video0) device_capability="Video Output" ;;
  /dev/video1) device_capability="Metadata Capture" ;;
  /dev/video7 | /dev/video9) device_capability="Video Output" ;;
  *) device_capability="Video Capture" ;;
  esac

  printf '%s\n' \
    "Driver Info:" \
    $'\tCapabilities     : 0x84a00001' \
    $'\t\tVideo Capture' \
    $'\tDevice Caps      : 0x04200001' \
    $'\t\t'"$device_capability"
  ;;
esac
SH

cat >"$stub_bin/omarchy-menu-select" <<'SH'
#!/bin/bash

printf '%s\n' "$@" >"$OMARCHY_TEST_MENU_ARGS"
printf '%s\n' "$3"
SH

cat >"$stub_bin/omarchy-capture-screenrecording" <<'SH'
#!/bin/bash

printf '%s\n' "$@" >"$OMARCHY_TEST_RECORDER_ARGS"
SH

cat >"$stub_bin/omarchy-notification-send" <<'SH'
#!/bin/bash

printf '%s\n' "$@" >"$OMARCHY_TEST_NOTIFICATION_ARGS"
SH

chmod +x "$stub_bin"/*

export PATH="$stub_bin:$ROOT/bin:$PATH"
# The resize helper anchors to a region file here, so keep it out of the real one
export XDG_RUNTIME_DIR="$tmp_dir"
export OMARCHY_TEST_MENU_ARGS="$tmp_dir/menu-args"
export OMARCHY_TEST_RECORDER_ARGS="$tmp_dir/recorder-args"
export OMARCHY_TEST_NOTIFICATION_ARGS="$tmp_dir/notification-args"

mapfile -t capture_devices < <(omarchy-capture-webcam-list)
expected_capture_devices=(
  "/dev/video42  Built-in Webcam: Integrated Camera"
  "/dev/video2  USB Capture Card: External Camera"
)

if [[ ${capture_devices[*]} != "${expected_capture_devices[*]}" ]]; then
  fail "webcam detection filters output-only devices and collapses each capture group" \
    "expected: ${expected_capture_devices[*]}\nactual:   ${capture_devices[*]}"
fi
pass "webcam detection filters output-only devices and collapses each capture group"

dual_node=$(OMARCHY_TEST_DUAL_NODE_WEBCAM=true omarchy-capture-webcam-list) ||
  fail "webcam listing exits zero when the trailing device is filtered"
pass "webcam listing exits zero when the trailing device is filtered"

expected_dual_node="/dev/video42  Built-in Webcam: Integrated Camera
/dev/video2  USB Capture Card: External Camera
/dev/video8  Dual Node Camera: ISP Wrapper"
[[ $dual_node == "$expected_dual_node" ]] ||
  fail "webcam detection falls through to a later capture-capable node in a group" "$dual_node"
pass "webcam detection falls through to a later capture-capable node in a group"

if "$ROOT/bin/omarchy-hw-webcam"; then
  pass "webcam hardware detection succeeds when a capture device is available"
else
  fail "webcam hardware detection succeeds when a capture device is available"
fi

if OMARCHY_TEST_RAW_WEBCAM=true "$ROOT/bin/omarchy-hw-webcam"; then
  fail "webcam hardware detection rejects output-only video devices"
else
  pass "webcam hardware detection rejects output-only video devices"
fi

if OMARCHY_TEST_NO_WEBCAM=true "$ROOT/bin/omarchy-hw-webcam"; then
  fail "webcam hardware detection fails when no video device is available"
else
  pass "webcam hardware detection fails when no video device is available"
fi

if OMARCHY_TEST_RAW_WEBCAM=true "$ROOT/bin/omarchy-capture-screenrecording-with-webcam"; then
  fail "screenrecording webcam picker rejects output-only video devices"
fi
grep -Fx 'No webcam devices found' "$OMARCHY_TEST_NOTIFICATION_ARGS" >/dev/null || \
  fail "screenrecording webcam picker reports no capture-capable device"
pass "screenrecording webcam picker rejects output-only video devices"

"$ROOT/bin/omarchy-capture-screenrecording-with-webcam"

expected_menu_args="$tmp_dir/expected-menu-args"
printf '%s\n' \
  "Select Webcam" \
  "/dev/video42  Built-in Webcam: Integrated Camera" \
  "/dev/video2  USB Capture Card: External Camera" \
  "--" \
  "--width" \
  "520" \
  "--maxheight" \
  "520" >"$expected_menu_args"

if ! cmp -s "$OMARCHY_TEST_MENU_ARGS" "$expected_menu_args"; then
  fail "screenrecording webcam picker passes each webcam as a menu option" "$(diff -u "$expected_menu_args" "$OMARCHY_TEST_MENU_ARGS")"
fi
pass "screenrecording webcam picker passes each webcam as a menu option"

expected_recorder_args="$tmp_dir/expected-recorder-args"
printf '%s\n' \
  "--with-desktop-audio" \
  "--with-microphone-audio" \
  "--with-webcam" \
  "--webcam-device=/dev/video2" >"$expected_recorder_args"

if ! cmp -s "$OMARCHY_TEST_RECORDER_ARGS" "$expected_recorder_args"; then
  fail "screenrecording webcam picker starts recording with selected device" "$(diff -u "$expected_recorder_args" "$OMARCHY_TEST_RECORDER_ARGS")"
fi
pass "screenrecording webcam picker starts recording with selected device"

first_webcam=$(omarchy-capture-webcam-list | sed -n '1s/[[:space:]].*//p')
[[ $first_webcam == "/dev/video42" ]] || fail "screenrecording auto-detection selects the first capture device"
grep -F 'WEBCAM_DEVICE=$(omarchy-capture-webcam-list' "$ROOT/bin/omarchy-capture-screenrecording" >/dev/null || \
  fail "screenrecording auto-detection uses capture-capable webcams"
pass "screenrecording auto-detection uses the first capture-capable webcam"


# The overlay is resized over sway IPC: the window comes from the tree by its
# fixed WebcamOverlay title, the monitor from the output rect containing the
# window center. Rects are logical, so the ladder math needs no scale factor.
cat >"$stub_bin/swaymsg" <<'SH'
#!/bin/bash

if [[ ${1:-} == "-t" && ${2:-} == "get_tree" ]]; then
  printf '{"type":"root","nodes":[{"type":"floating_con","pid":9,"id":33,"name":"%s","rect":{"x":%s,"y":%s,"width":%s,"height":%s}}]}\n' \
    "${OMARCHY_TEST_CLIENT_TITLE:-WebcamOverlay}" \
    "${OMARCHY_TEST_CLIENT_X:-2342}" \
    "${OMARCHY_TEST_CLIENT_Y:-460}" \
    "${OMARCHY_TEST_CLIENT_WIDTH:-178}" \
    "${OMARCHY_TEST_CLIENT_HEIGHT:-200}"
elif [[ ${1:-} == "-t" && ${2:-} == "get_outputs" ]]; then
  printf '[{"name":"DP-2","active":true,"focused":true,"rect":{"x":1280,"y":-100,"width":%s,"height":%s}}]\n' \
    "${OMARCHY_TEST_MONITOR_WIDTH:-1280}" \
    "${OMARCHY_TEST_MONITOR_HEIGHT:-800}"
else
  printf '%s\n' "$*" >>"$OMARCHY_TEST_SWAYMSG_ARGS"
fi
SH
chmod +x "$stub_bin/swaymsg"

export OMARCHY_TEST_SWAYMSG_ARGS="$tmp_dir/swaymsg-args"

"$ROOT/bin/omarchy-capture-webcam-resize" smaller

expected_swaymsg_args="$tmp_dir/expected-swaymsg-args"
printf '%s\n' \
  '[con_id=33] resize set 128 px 144 px' \
  '[con_id=33] move absolute position 2392 516' >"$expected_swaymsg_args"

if ! cmp -s "$OMARCHY_TEST_SWAYMSG_ARGS" "$expected_swaymsg_args"; then
  fail "webcam resize preserves its aspect ratio and corner anchor" "$(diff -u "$expected_swaymsg_args" "$OMARCHY_TEST_SWAYMSG_ARGS")"
fi
pass "webcam resize preserves its aspect ratio and corner anchor"

: >"$OMARCHY_TEST_SWAYMSG_ARGS"
OMARCHY_TEST_MONITOR_WIDTH=1920 \
  OMARCHY_TEST_MONITOR_HEIGHT=1080 \
  OMARCHY_TEST_CLIENT_WIDTH=128 \
  OMARCHY_TEST_CLIENT_HEIGHT=144 \
  "$ROOT/bin/omarchy-capture-webcam-resize" reset

printf '%s\n' \
  '[con_id=33] resize set 240 px 270 px' \
  '[con_id=33] move absolute position 2920 670' >"$expected_swaymsg_args"

if ! cmp -s "$OMARCHY_TEST_SWAYMSG_ARGS" "$expected_swaymsg_args"; then
  fail "webcam default size adapts to monitor resolution" "$(diff -u "$expected_swaymsg_args" "$OMARCHY_TEST_SWAYMSG_ARGS")"
fi
pass "webcam default size adapts to monitor resolution"

: >"$OMARCHY_TEST_SWAYMSG_ARGS"
OMARCHY_TEST_CLIENT_TITLE="Other Window" "$ROOT/bin/omarchy-capture-webcam-resize" larger

if [[ -s $OMARCHY_TEST_SWAYMSG_ARGS ]]; then
  fail "webcam resize ignores other windows" "$(cat "$OMARCHY_TEST_SWAYMSG_ARGS")"
fi
pass "webcam resize ignores other windows"

region_file="$XDG_RUNTIME_DIR/omarchy-screenrecord-region"

: >"$OMARCHY_TEST_SWAYMSG_ARGS"
echo "800x600+100+100" >"$region_file"
"$ROOT/bin/omarchy-capture-webcam-resize" reset

printf '%s\n' \
  '[con_id=33] resize set 133 px 150 px' \
  '[con_id=33] move absolute position 727 510' >"$expected_swaymsg_args"

if ! cmp -s "$OMARCHY_TEST_SWAYMSG_ARGS" "$expected_swaymsg_args"; then
  fail "webcam anchors to the recorded region" "$(diff -u "$expected_swaymsg_args" "$OMARCHY_TEST_SWAYMSG_ARGS")"
fi
pass "webcam anchors to the recorded region"

printf '%s\n' \
  '[con_id=33] resize set 178 px 200 px' \
  '[con_id=33] move absolute position 2342 460' >"$expected_swaymsg_args"

for region in "not-a-region" ""; do
  : >"$OMARCHY_TEST_SWAYMSG_ARGS"
  printf '%s' "$region" >"$region_file"
  "$ROOT/bin/omarchy-capture-webcam-resize" reset

  if ! cmp -s "$OMARCHY_TEST_SWAYMSG_ARGS" "$expected_swaymsg_args"; then
    fail "webcam falls back to the monitor for an unusable region" "$(diff -u "$expected_swaymsg_args" "$OMARCHY_TEST_SWAYMSG_ARGS")"
  fi
done
pass "webcam falls back to the monitor for an unusable region"

# A region too narrow for presets scaled from its height shrinks the whole
# ladder, so the three sizes stay distinct and each one fits inside the margins
: >"$OMARCHY_TEST_SWAYMSG_ARGS"
echo "200x1200+0+0" >"$region_file"
for size in small medium large; do
  "$ROOT/bin/omarchy-capture-webcam-resize" "$size"
done

printf '%s\n' \
  '[con_id=33] resize set 64 px 72 px' \
  '[con_id=33] move absolute position 96 1088' \
  '[con_id=33] resize set 89 px 100 px' \
  '[con_id=33] move absolute position 71 1060' \
  '[con_id=33] resize set 120 px 135 px' \
  '[con_id=33] move absolute position 40 1025' >"$expected_swaymsg_args"

if ! cmp -s "$OMARCHY_TEST_SWAYMSG_ARGS" "$expected_swaymsg_args"; then
  fail "webcam sizes stay distinct and inside a narrow region" "$(diff -u "$expected_swaymsg_args" "$OMARCHY_TEST_SWAYMSG_ARGS")"
fi
pass "webcam sizes stay distinct and inside a narrow region"

rm -f "$region_file"

# The Hyprland webcam-overlay window rules and the SUPER+ALT bracket hotkeys
# were dropped with the Lite scope; the recorder waits for the map and calls
# omarchy-capture-webcam-resize itself, so the size-specific app id remains the
# only contract to pin.
grep -F -- '--wayland-app-id="WebcamOverlay-$WEBCAM_SIZE"' \
  "$ROOT/bin/omarchy-capture-screenrecording" >/dev/null || fail "webcam uses a dedicated size-specific app id"
pass "webcam uses a dedicated size-specific app id"
