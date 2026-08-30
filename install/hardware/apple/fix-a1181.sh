# Detect the 2006 MacBook1,1 (A1181): fans need mbpfan, the iSight camera
# needs firmware extracted from the Apple driver by isight-firmware-tools,
# and the ath5k Wi-Fi drops the link under powersave.
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
fi
