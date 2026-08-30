# /etc/pam.d/system-auth is upstream-owned and the changes are insertions,
# not full-file overrides, so they stay scripted. greetd uses system-auth
# through its packaged /etc/pam.d/greetd, so no greeter-specific file needs
# the faillock treatment.
sed -i 's|^\(auth\s\+required\s\+pam_faillock.so\)\s\+preauth.*$|\1 preauth silent deny=10 unlock_time=120|' \
           /etc/pam.d/system-auth
sed -i 's|^\(auth\s\+\[default=die\]\s\+pam_faillock.so\)\s\+authfail.*$|\1 authfail deny=10 unlock_time=120|' \
           /etc/pam.d/system-auth
