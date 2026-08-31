# Install the greetd config: tuigreet is the default greeter, and the install
# user gets an initial_session straight into Hyprland so the first boot lands
# on the desktop. Deferred-provisioning installs create the user at first boot,
# so they get only the greeter.
mkdir -p /etc/greetd

cat >/etc/greetd/config.toml <<EOF
[terminal]
vt = 1

[default_session]
command = "tuigreet --cmd /usr/share/omarchy/bin/omarchy-hyprland-launch"
user = "greeter"
EOF

if [[ -n ${OMARCHY_INSTALL_USER:-} ]]; then
  cat >>/etc/greetd/config.toml <<EOF

[initial_session]
command = "/usr/share/omarchy/bin/omarchy-hyprland-launch"
user = "$OMARCHY_INSTALL_USER"
EOF
fi
