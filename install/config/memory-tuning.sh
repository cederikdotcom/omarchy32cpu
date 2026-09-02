# Install the memory-management configuration.
#
# Upstream ships these files inside the omarchy pacman package, which drops
# them straight into /etc. This fork has no package, so nothing was putting
# them on disk: a fresh install came up with no zram device, no swap of any
# kind, stock oomd thresholds and stock vm reclaim tuning, while every document
# in the tree said otherwise. That is the wrong way round on the 2 GB machine
# this fork exists for, so the install stage seeds them here.

install -Dm0644 "$OMARCHY_PATH/default/systemd/zram-generator.conf.d/90-omarchy.conf" \
  /etc/systemd/zram-generator.conf.d/90-omarchy.conf

install -Dm0644 "$OMARCHY_PATH/etc/systemd/oomd.conf.d/10-omarchy.conf" \
  /etc/systemd/oomd.conf.d/10-omarchy.conf

# Kill candidacy is set on the user manager's app.slice, so only user apps are
# eligible and the compositor never is.
install -Dm0644 "$OMARCHY_PATH/default/systemd/user/app.slice.d/10-oomd.conf" \
  /etc/systemd/user/app.slice.d/10-oomd.conf

# Reclaim tuned for swap-on-zram, and zswap off in front of it.
install -Dm0644 "$OMARCHY_PATH/etc/sysctl.d/99-omarchy-sysctl.conf" \
  /etc/sysctl.d/99-omarchy-sysctl.conf
install -Dm0644 "$OMARCHY_PATH/etc/sysctl.d/90-omarchy-file-watchers.conf" \
  /etc/sysctl.d/90-omarchy-file-watchers.conf
install -Dm0644 "$OMARCHY_PATH/etc/tmpfiles.d/omarchy-zswap.conf" \
  /etc/tmpfiles.d/omarchy-zswap.conf
