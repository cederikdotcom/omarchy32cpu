# Install Sound Open Firmware for Intel audio DSPs. The sof-audio-pci-intel-*
# driver family requires this firmware; without it PipeWire exposes only a
# Dummy Output sink. The i945's ICH7 audio (8086:27a2 chipset graphics) is
# plain snd_hda_intel and needs no SOF.

if omarchy-hw-intel-sof && ! lspci -n | grep -q "8086:27a2"; then
  omarchy-pkg-add sof-firmware
fi
