#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

export PATH="$ROOT/bin:$PATH"

require_command jq

# Strip JSONC decoration (full-line // comments, trailing commas) the same way
# omarchy-menu does before handing the result to jq.
jsonc_to_json() {
  sed -e 's|^[[:space:]]*//.*$||' "$1" |
    sed -z -e 's/,[[:space:]]*}/}/g' -e 's/,[[:space:]]*\]/\]/g'
}

jq empty "$ROOT/config/omarchy/shell.json"
pass "default shell.json is valid JSON"

# omarchy-shell-config still normalizes user config against this file, so the
# versioned shape has to hold even though waybar renders the bar now.
jq -e '.version == 1 and (.bar.layout.left | type == "array") and (.bar.layout.center | type == "array") and (.bar.layout.right | type == "array")' "$ROOT/config/omarchy/shell.json" >/dev/null
pass "default shell.json has versioned bar layout"

jsonc_to_json "$ROOT/config/waybar/config.jsonc" | jq empty ||
  fail "waybar config.jsonc parses as JSON after comment stripping"
pass "default waybar config is valid JSONC"

jsonc_to_json "$ROOT/default/omarchy/omarchy-menu.jsonc" | jq -e 'type == "object" and length > 0' >/dev/null ||
  fail "omarchy-menu.jsonc parses to a non-empty object"
pass "default menu definition is valid JSONC"

jq empty "$ROOT/default/omarchy/emojis.json"
pass "default emoji catalog is valid JSON"

# The Hyprland stack: the user config bootstraps the package defaults, the
# session launcher is what the wayland session starts, and mako/waybar ship
# styles for the shim shell that stands in for Quickshell.
grep -Fq 'default/hypr/bootstrap.lua' "$ROOT/config/hypr/hyprland.lua" ||
  fail "user hyprland.lua loads the Omarchy bootstrap first"
grep -Fq 'require("default.hypr.omarchy")' "$ROOT/config/hypr/hyprland.lua" ||
  fail "user hyprland.lua loads the Omarchy defaults"
[[ -s $ROOT/default/hypr/omarchy.lua ]] || fail "default hypr config is shipped"
grep -Fqx 'Exec=omarchy-hyprland-launch' "$ROOT/default/wayland-sessions/omarchy.desktop" ||
  fail "wayland session starts the Omarchy Hyprland launcher"
[[ -s $ROOT/config/mako/config ]] || fail "mako notification config is shipped"
[[ -s $ROOT/config/waybar/style.css ]] || fail "waybar stylesheet is shipped"
pass "Hyprland session stack configs are shipped and wired"

# The launcher owns the two things the pixman renderer cannot work without.
for var in 'HYPRLAND_RENDERER=pixman' 'AQ_FORCE_ALLOCATOR=dumb'; do
  grep -Fq "export $var" "$ROOT/bin/omarchy-hyprland-launch" ||
    fail "session launcher exports $var"
done
pass "session launcher selects the pixman CPU renderer"

# Themes render the CPU desktop from templates: hyprland, waybar, mako, swaylock.
for tpl in hyprland.lua.tpl waybar.css.tpl mako.ini.tpl swaylock.args.tpl; do
  [[ -s $ROOT/default/themed/$tpl ]] || fail "theme template exists: $tpl"
done
pass "CPU desktop theme templates are shipped"

# The packaged mkinitcpio drop-in must survive sourcing under set -u and
# produce a bootable hook list.
hooks=$(bash -uc "source '$ROOT/etc/mkinitcpio.conf.d/omarchy_hooks.conf' && echo \"\${HOOKS[*]}\"")
for hook in base udev block filesystems fsck; do
  [[ " $hooks " == *" $hook "* ]] || fail "mkinitcpio HOOKS keeps $hook" "actual: $hooks"
done
pass "packaged mkinitcpio hooks parse and stay bootable"

# Package-owned defaults live outside config/ (config/ is copied into ~/.config
# wholesale by refresh commands; system files must not ride along).
package_defaults=(
  "default/environment.d/10-omarchy-fcitx.conf environment.d/fcitx.conf"
  "default/fontconfig/conf.avail/50-omarchy.conf fontconfig/fonts.conf"
  "default/xdg-terminal-exec/hyprland-xdg-terminals.list xdg-terminals.list"
  "default/applications/mimeapps.list mimeapps.list"
  "etc/fastfetch/config.jsonc fastfetch/config.jsonc"
  "default/systemd/user/bt-agent.service systemd/user/bt-agent.service"
  "default/systemd/user/omarchy-sleep-lock.service systemd/user/omarchy-sleep-lock.service"
  "default/systemd/user/omarchy-recover-internal-monitor.service systemd/user/omarchy-recover-internal-monitor.service"
  "default/systemd/user/omarchy-migrate-notify.service systemd/user/omarchy-migrate-notify.service"
  "default/systemd/user/omarchy-tailscale-receive.service systemd/user/omarchy-tailscale-receive.service"
  "default/systemd/user/omarchy-fcitx5.service systemd/user/omarchy-fcitx5.service"
  "default/systemd/user/omarchy-crash-watch.service systemd/user/omarchy-crash-watch.service"
  "default/systemd/zram-generator.conf.d/90-omarchy.conf systemd/zram-generator.conf.d/90-omarchy.conf"
  "default/fonts/omarchy/omarchy.ttf omarchy.ttf"
  "default/snapper/root snapper/root"
  "default/libalpm/hooks/00-omarchy-update-guard.hook libalpm/hooks/00-omarchy-update-guard.hook"
)

errors=()
for entry in "${package_defaults[@]}"; do
  source_path=${entry%% *}
  legacy_path=${entry#* }
  [[ -e $ROOT/$source_path ]] || errors+=("missing package default source: $source_path")
  [[ ! -e $ROOT/config/$legacy_path ]] || errors+=("legacy path still in config/: $legacy_path")
done
((${#errors[@]} == 0)) || fail "package-owned defaults live outside config" "$(printf '%s\n' "${errors[@]}")"
pass "package-owned defaults live outside config"

# The one shipped alpm hook must point at scripts that exist.
grep -Fq 'Exec = /usr/bin/omarchy-update-pacman-guard' "$ROOT/default/libalpm/hooks/00-omarchy-update-guard.hook" &&
  [[ -x $ROOT/bin/omarchy-update-pacman-guard ]] ||
  fail "update guard alpm hook points at a shipped script"
pass "update guard alpm hook points at a shipped script"

if grep -RIl 'upgrade-to-quattro\|Omarchy 4\.0 is upgraded' "$ROOT/migrations" >/dev/null; then
  fail "4.0 upgrade is not modeled as a migration"
fi
pass "4.0 upgrade is handled outside the migration runner"
