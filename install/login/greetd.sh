# Install the greetd config: tuigreet is the default greeter, and the install
# user gets an initial_session straight into Hyprland so the first boot lands
# on the desktop. Deferred-provisioning installs create the user at first boot,
# so they get only the greeter.
#
# Both sessions run through systemd-cat. Hyprland's runtime log file is empty
# by default (debug:disable_logs), and greetd sends the session's own stdout
# and stderr nowhere, so a compositor that dies at login used to leave no
# evidence at all: the machine simply returned to the greeter. Tagged into the
# journal, the same failure reads back with
#
#   journalctl -b -t omarchy-session
#
# which is where "malloc(): invalid size (unsorted)" and the crash-report path
# appear. systemd-cat execs its argument, so no extra process survives and the
# session is still Hyprland itself. The shell already does this
# (bin/omarchy-launch-shell tags itself omarchy-shell); this makes the pair
# symmetric.
mkdir -p /etc/greetd

session_cmd="systemd-cat -t omarchy-session /usr/share/omarchy/bin/omarchy-hyprland-launch"

cat >/etc/greetd/config.toml <<EOF
[terminal]
vt = 1

[default_session]
command = "tuigreet --cmd '$session_cmd'"
user = "greeter"
EOF

if [[ -n ${OMARCHY_INSTALL_USER:-} ]]; then
  cat >>/etc/greetd/config.toml <<EOF

[initial_session]
command = "$session_cmd"
user = "$OMARCHY_INSTALL_USER"
EOF
fi
