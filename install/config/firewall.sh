# Rerunning inside a chroot after UFW was enabled would load the deny rules
# into the shared live kernel and cut the host or installer off the network.
if systemd-detect-virt --chroot >/dev/null 2>&1 && grep -q '^ENABLED=yes' /etc/ufw/ufw.conf 2>/dev/null; then
  exit 0
fi

# Allow nothing in, everything out.
ufw default deny incoming
ufw default allow outgoing

# Allow ports for LocalSend.
ufw allow 53317/udp
ufw allow 53317/tcp


# Installs are followed by reboot, so configure UFW to start on the installed
# system instead of mutating the live install session's firewall.
sed -i 's/^ENABLED=.*/ENABLED=yes/' /etc/ufw/ufw.conf
systemctl enable ufw
