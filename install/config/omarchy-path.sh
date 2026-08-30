# The omarchy package normally ships /etc/profile.d/omarchy.sh; this fork has
# no package yet, so install it here for login shells and SSH sessions.
cat >/etc/profile.d/omarchy.sh <<'PROFILE'
[ -r /usr/share/omarchy/default/bash/env-bootstrap ] && . /usr/share/omarchy/default/bash/env-bootstrap
PROFILE
chmod 0644 /etc/profile.d/omarchy.sh
