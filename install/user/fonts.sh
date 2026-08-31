# Install the Omarchy icon font for the user.
#
# Upstream ships it in the omarchy package, which lands it system-wide. This
# fork has no package, so seed it per user instead; without it the menu and the
# bar draw the private-use glyphs as tofu boxes.
if [[ -f $OMARCHY_PATH/default/fonts/omarchy/omarchy.ttf ]]; then
  mkdir -p ~/.local/share/fonts
  cp -f "$OMARCHY_PATH/default/fonts/omarchy/omarchy.ttf" ~/.local/share/fonts/
  fc-cache -f ~/.local/share/fonts >/dev/null
fi
