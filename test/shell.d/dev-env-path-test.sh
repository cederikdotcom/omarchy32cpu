#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

run_bootstrap() {
  local shell_bin="$1"
  local bootstrap="$2"
  local home="$3"
  local path_value="$4"

  shell_bin=$(command -v "$shell_bin")
  HOME="$home" PATH="$path_value" "$shell_bin" -c '
    . "$1"
    printf "%s\n%s\n" "$OMARCHY_PATH" "$PATH"
  ' sh "$bootstrap"
}

assert_path_first() {
  local path_value="$1"
  local entry="$2"
  local description="$3"

  [[ ${path_value%%:*} == "$entry" ]] || fail "$description" "expected first PATH entry: $entry\nactual PATH: $path_value"
  pass "$description"
}

assert_path_present() {
  local path_value="$1"
  local entry="$2"
  local description="$3"

  case ":$path_value:" in
    *":$entry:"*) pass "$description" ;;
    *) fail "$description" "PATH does not contain $entry in $path_value" ;;
  esac
}

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

home="$tmpdir/home"
mkdir -p "$tmpdir/active/bin" "$tmpdir/unrelated/bin"

assert_path_absent() {
  local path_value="$1"
  local entry="$2"
  local description="$3"

  case ":$path_value:" in
    *":$entry:"*) fail "$description" "PATH unexpectedly contains $entry in $path_value" ;;
    *) pass "$description" ;;
  esac
}

# Test against a copy so the test controls /etc/omarchy.conf without mutating the
# host. The packaged-command probe is redirected the same way: this fork prepends
# on package-less installs, so whether the prepend happens depends on a path that
# exists on a real install and not on a checkout. Rewriting it here exercises both
# branches on any host, instead of letting the host decide which one runs.
bootstrap="$tmpdir/env-bootstrap"
packaged_command="$tmpdir/usr/bin/omarchy"
mkdir -p "$(dirname "$packaged_command")"
sed -e "s#/etc/omarchy.conf#$tmpdir/omarchy.conf#g" \
    -e "s#/usr/bin/omarchy#$packaged_command#g" \
    "$ROOT/default/bash/env-bootstrap" >"$bootstrap"

# Default mode, no omarchy package on disk. Upstream leaves PATH alone here,
# because its package symlinks omarchy-* into /usr/bin. This fork has no package
# yet (see the no-package-repo entry in .github/divergence/registry.json), so
# nothing would be on PATH at all and Hyprland keybindings could not dispatch a
# single omarchy command. It prepends instead.
printf 'export OMARCHY_PATH="/usr/share/omarchy"\n' >"$tmpdir/omarchy.conf"
mapfile -t default_result < <(run_bootstrap bash "$bootstrap" "$home" "$tmpdir/unrelated/bin:/usr/bin")
default_path=${default_result[1]}

[[ ${default_result[0]} == /usr/share/omarchy ]] || fail "env-bootstrap resolves default OMARCHY_PATH" "actual: ${default_result[0]}"
pass "env-bootstrap resolves default OMARCHY_PATH"
assert_path_present "$default_path" "$tmpdir/unrelated/bin" "env-bootstrap preserves PATH entries in default mode"
assert_path_present "$default_path" "$home/.local/share/mise/shims" "env-bootstrap appends mise shims"
assert_path_present "$default_path" "$home/.local/bin" "env-bootstrap appends ~/.local/bin"
assert_path_first "$default_path" "/usr/share/omarchy/bin" "env-bootstrap prepends the shipped bin when no omarchy package provides it"

# The same default mode once a package does provide the command. This is the
# no-op the fork's comment promises, and the branch that has to keep working for
# the day the fork ships PKGBUILDs: upstream's behaviour, restored by the probe
# rather than by editing this file again.
printf '#!/bin/sh\n' >"$packaged_command"
chmod +x "$packaged_command"
mapfile -t packaged_result < <(run_bootstrap bash "$bootstrap" "$home" "$tmpdir/unrelated/bin:/usr/bin")
packaged_path=${packaged_result[1]}
rm -f "$packaged_command"

assert_path_first "$packaged_path" "$tmpdir/unrelated/bin" "env-bootstrap appends user-level paths after existing entries"
assert_path_absent "$packaged_path" "/usr/share/omarchy/bin" "env-bootstrap leaves PATH alone when the omarchy package owns /usr/bin"
assert_path_present "$packaged_path" "$home/.local/bin" "env-bootstrap still appends user-level paths in packaged mode"

printf 'export OMARCHY_PATH="%s"\n' "$tmpdir/active" >"$tmpdir/omarchy.conf"
mapfile -t linked_result < <(run_bootstrap bash "$bootstrap" "$home" "$tmpdir/unrelated/bin:/usr/bin")
linked_path=${linked_result[1]}

[[ ${linked_result[0]} == "$tmpdir/active" ]] || fail "env-bootstrap resolves linked OMARCHY_PATH" "actual: ${linked_result[0]}"
pass "env-bootstrap resolves linked OMARCHY_PATH"
assert_path_first "$linked_path" "$tmpdir/active/bin" "env-bootstrap prepends active checkout bin in linked mode"
assert_path_present "$linked_path" "$tmpdir/unrelated/bin" "env-bootstrap preserves unrelated PATH entries in linked mode"

mapfile -t linked_duplicate_result < <(run_bootstrap bash "$bootstrap" "$home" "$tmpdir/active/bin:/usr/bin:$home/.local/share/mise/shims:$home/.local/bin")
linked_duplicate_path=${linked_duplicate_result[1]}
[[ $linked_duplicate_path == "$tmpdir/active/bin:/usr/bin:$home/.local/share/mise/shims:$home/.local/bin" ]] || fail "env-bootstrap does not duplicate PATH entries" "actual PATH: $linked_duplicate_path"
pass "env-bootstrap does not duplicate PATH entries"

# An empty PATH must not produce empty entries (a bare ":" means the cwd)
mapfile -t empty_path_result < <(run_bootstrap bash "$bootstrap" "$home" "")
empty_path=${empty_path_result[1]}
[[ $empty_path == "$tmpdir/active/bin:$home/.local/share/mise/shims:$home/.local/bin" ]] || fail "env-bootstrap builds a clean PATH from an empty one" "actual PATH: $empty_path"
pass "env-bootstrap builds a clean PATH from an empty one"

if command -v zsh >/dev/null 2>&1; then
  mapfile -t zsh_result < <(run_bootstrap zsh "$bootstrap" "$home" "$tmpdir/unrelated/bin:/usr/bin")
  zsh_path=${zsh_result[1]}
  assert_path_first "$zsh_path" "$tmpdir/active/bin" "env-bootstrap works when sourced by zsh"
  assert_path_present "$zsh_path" "$tmpdir/unrelated/bin" "env-bootstrap zsh mode preserves unrelated PATH entries"
fi
