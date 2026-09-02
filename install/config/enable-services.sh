# Enable services only. Installs are followed by reboot, so don't start/reload
# daemons mid-install. UFW and hardware-gated services stay in their own scripts.
systemctl enable systemd-resolved.service
systemctl enable NetworkManager.service
# Don't let network-online.target hold up graphical.target waiting for
# DHCP/Wi-Fi association. Nothing in the session needs to block on the network.
# Mirrors the systemd-networkd-wait-online mask in install/hardware/network.sh.
systemctl mask NetworkManager-wait-online.service
# greetd + tuigreet, not sddm: SDDM's greeter needs a GL context and there is
# no GPU on this target. Upstream also enables cups, avahi, docker.socket,
# linux-modules-cleanup and power-profiles-daemon here; none of their packages
# are in this fork's package set, so enabling them would fail the install.
# docs/RELEASE-NOTES.md carries the per-package reasoning.
systemctl enable greetd.service
# Kill one runaway app scope instead of letting reclaim thrashing take the
# whole session down. [Install] pulls in systemd-oomd.socket via Also=, which
# is what the user manager reports app.slice candidacy over.
systemctl enable systemd-oomd.service
