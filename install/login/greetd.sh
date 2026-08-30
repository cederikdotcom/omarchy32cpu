# Install the greetd config: tuigreet is the default greeter, and the install
# user gets an initial_session straight into sway so the first boot lands on
# the desktop. Deferred-provisioning installs create the user at first boot,
# so they get only the greeter.
mkdir -p /etc/greetd

cat >/etc/greetd/config.toml <<EOF
[terminal]
vt = 1

[default_session]
command = "tuigreet --cmd sway"
user = "greeter"
EOF

if [[ -n ${OMARCHY_INSTALL_USER:-} ]]; then
  cat >>/etc/greetd/config.toml <<EOF

[initial_session]
command = "env WLR_RENDERER=pixman WLR_LIBINPUT_NO_DEVICES= dbus-run-session sway"
user = "$OMARCHY_INSTALL_USER"
EOF
fi
