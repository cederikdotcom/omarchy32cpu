# Install the Wayland session entry. Upstream ships this in the omarchy
# package; this fork has no package, so the installer places it, the same way
# install/config/omarchy-path.sh places /etc/profile.d/omarchy.sh.
#
# greetd starts the session from an absolute path in its own config, so the
# desktop file is not what a normal boot uses. It matters when someone picks a
# session in the greeter: the fork's Hyprland build installs its own
# hyprland.desktop and hyprland-uwsm.desktop under /usr/local/share, and both
# start the compositor WITHOUT HYPRLAND_RENDERER=pixman. On a machine with no
# GPU that is a black screen. Shipping the Omarchy entry gives the greeter a
# session that works.
install -d /usr/share/wayland-sessions
install -m 0644 "$OMARCHY_PATH/default/wayland-sessions/omarchy.desktop" \
  /usr/share/wayland-sessions/omarchy.desktop
