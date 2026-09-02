# Configure pacman after package installation completes. Offline target package
# installs use the live ISO's offline pacman.conf until this final restore.
#
# The shipped configs are archlinux32: they set Architecture = i686 and point
# at mirror.archlinux32.org. On any other architecture that would repoint
# pacman at repos it cannot use, so leave the installer's own pacman.conf and
# mirrorlist alone there (official Arch x86_64 needs no override anyway).
#
# Ask the target's own package database, not `uname -m`: this runs in a chroot
# and the installer's kernel may well be 64-bit while the root being built is
# i686, in which case uname reports the wrong answer and the archlinux32
# configs never land.
target_arch=$(pacman -Qi pacman 2>/dev/null | awk -F': *' '/^Architecture/ { print $2; exit }')
[[ -n $target_arch ]] || target_arch=$(uname -m)

if [[ $target_arch == i?86 ]]; then
  cp -f "$OMARCHY_PATH/default/pacman/pacman-${OMARCHY_MIRROR:-stable}.conf" /etc/pacman.conf
  cp -f "$OMARCHY_PATH/default/pacman/mirrorlist-${OMARCHY_MIRROR:-stable}" /etc/pacman.d/mirrorlist
else
  echo "Target is $target_arch, not i686: keeping the existing /etc/pacman.conf and mirrorlist."
fi

# omarchy-settings skips this override until cups-browsed is actually present
# to avoid pacman creating cups-browsed.conf.pacnew during ISO package install.
if [[ -f $OMARCHY_PATH/etc-overrides/cups-cups-browsed.conf && -d /etc/cups ]]; then
  cp -f "$OMARCHY_PATH/etc-overrides/cups-cups-browsed.conf" /etc/cups/cups-browsed.conf
  rm -f /etc/cups/cups-browsed.conf.pacnew
fi

source "$OMARCHY_INSTALL/hardware/pacman.sh"
