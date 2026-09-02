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
#
# The session command is written out literally rather than expanded from a
# variable: /etc/greetd/config.toml is root-owned and root executes what it
# names, so nothing the installing user controls may reach it.
mkdir -p /etc/greetd

cat >/etc/greetd/config.toml <<'EOF'
[terminal]
vt = 1

[default_session]
command = "tuigreet --cmd 'systemd-cat -t omarchy-session /usr/share/omarchy/bin/omarchy-hyprland-launch'"
user = "greeter"
EOF

if [[ -n ${OMARCHY_INSTALL_USER:-} ]]; then
  # omarchy:heredoc-expands paths=none -- OMARCHY_INSTALL_USER is the account name the installer just created, and the session command beside it is a literal absolute path under root-owned /usr/share/omarchy
  cat >>/etc/greetd/config.toml <<EOF

[initial_session]
command = "systemd-cat -t omarchy-session /usr/share/omarchy/bin/omarchy-hyprland-launch"
user = "$OMARCHY_INSTALL_USER"
EOF
fi
