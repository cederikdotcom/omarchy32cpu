# Detect the 2006 MacBook1,1 (A1181): fans need mbpfan, the iSight camera
# needs firmware extracted from the Apple driver by isight-firmware-tools,
# the ath5k Wi-Fi drops the link under powersave, and libinput does not list
# this model's 05ac:0217 one-button touchpad in its legacy Apple quirks.
product_name="$(cat /sys/class/dmi/id/product_name 2>/dev/null)"
if [[ $product_name == "MacBook1,1" ]]; then
  echo "Detected MacBook1,1 (A1181). Installing support items..."

  # Both packages come from the fork package repo (AUR upstream, not in the
  # archlinux32 repos), so skip gracefully until that repo carries them.
  if pacman -Si mbpfan &>/dev/null; then
    omarchy-pkg-add mbpfan
    systemctl enable mbpfan.service
  else
    echo "mbpfan not available in the configured repos; skipping fan control"
  fi

  if pacman -Si isight-firmware-tools &>/dev/null; then
    omarchy-pkg-add isight-firmware-tools
  else
    echo "isight-firmware-tools not available in the configured repos; skipping iSight firmware extraction"
  fi

  mkdir -p /etc/NetworkManager/conf.d
  cat > /etc/NetworkManager/conf.d/ath5k-no-powersave.conf <<'EOF'
# The A1181's ath5k radio drops the connection under Wi-Fi power save.
[connection]
wifi.powersave = 2
EOF

  # This pre-2008 touchpad has a physical button below the pad and advertises
  # BTN_LEFT without BTN_RIGHT. Without the model flag, libinput assumes the
  # kernel forgot INPUT_PROP_BUTTONPAD and suppresses button-only presses while
  # it waits for a finger position on what it incorrectly treats as a clickpad.
  mkdir -p /etc/libinput
  # libinput only loads local quirks from this exact reserved filename.
  local_quirks=/etc/libinput/local-overrides.quirks
  if ! grep -Fq '[Apple Touchpad OneButton MacBook1,1]' "$local_quirks" 2>/dev/null; then
    [[ ! -s $local_quirks ]] || printf '\n' >> "$local_quirks"
    cat >> "$local_quirks" <<'EOF'
[Apple Touchpad OneButton MacBook1,1]
MatchUdevType=touchpad
MatchBus=usb
MatchVendor=0x05AC
MatchProduct=0x0217
ModelAppleTouchpadOneButton=1
EOF
  fi
fi
