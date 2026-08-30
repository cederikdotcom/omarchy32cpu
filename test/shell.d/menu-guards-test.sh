#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command jq

# Omarchy CPU's fuzzel menu evaluates each row's when:/checked: guard with a
# plain bash -c, so a guard has to be a working shell expression on its own.
# The batch guardScript prelude went with the Quickshell menu.

menu_json() {
  sed -e 's|^[[:space:]]*//.*$||' "$ROOT/default/omarchy/omarchy-menu.jsonc" |
    sed -z -e 's/,[[:space:]]*}/}/g' -e 's/,[[:space:]]*\]/\]/g'
}

# Update > Extra Themes runs omarchy-theme-update, which pulls the themes that
# came from a git clone and skips everything else, so the guard has to answer
# for the same set: a row that appears over a symlinked theme or a worktree's
# `.git` file opens a terminal that prints nothing and closes. Both sides ask
# omarchy-theme-extras today; the shapes below are what would tell us if one
# of them stopped.
themes_guard=$(menu_json | jq -r '."update.themes".when // ""')
[[ -n $themes_guard ]] || fail "the shipped menu still guards Update > Extra Themes"
pass "the shipped menu still guards Update > Extra Themes"

stub_dir=$(mktemp -d)
trap 'rm -rf "$stub_dir"' EXIT

cat >"$stub_dir/git" <<'STUB'
#!/bin/bash
: "${GIT_CALLS:=/dev/null}"
{ printf '<%s>' "$@"; printf '\n'; } >>"$GIT_CALLS"
STUB
chmod +x "$stub_dir/git"

# The updater names each theme it pulls, so what it printed is what the row
# would have been for. Run the guard the way the menu does, and say which
# shapes are meant to show it rather than only that the two agree: they read
# the same command now, and agreement alone would hold even if both went
# wrong together.
assert_themes_guard_agrees() {
  local description="$1" home="$2" expected="$3"
  local guarded=0 updated=0

  HOME="$home" PATH="$ROOT/bin:$PATH" bash -e -c "{ $themes_guard; } >/dev/null 2>&1" || guarded=$?
  [[ -n $(HOME="$home" PATH="$ROOT/bin:$stub_dir:$PATH" "$ROOT/bin/omarchy-theme-update" 2>/dev/null) ]] || updated=1
  ((guarded == expected)) || fail "$description" "$home: guard=$guarded expected=$expected"
  ((updated == expected)) || fail "$description" "$home: update=$updated expected=$expected"
}

themes_home=$(mktemp -d)
trap 'rm -rf "$stub_dir" "$themes_home"' EXIT

# A theme copied by hand has nothing to pull, a symlinked one is someone's
# working copy, and a `.git` file is a worktree living elsewhere.
mkdir -p "$themes_home/missing"
mkdir -p "$themes_home/empty/.config/omarchy/themes"
mkdir -p "$themes_home/copied/.config/omarchy/themes/handmade"
mkdir -p "$themes_home/cloned/.config/omarchy/themes/tokyo-night/.git"
mkdir -p "$themes_home/linked/.config/omarchy/themes" "$themes_home/checkout/.git"
ln -s "$themes_home/checkout" "$themes_home/linked/.config/omarchy/themes/in-progress"
mkdir -p "$themes_home/worktree/.config/omarchy/themes/branch"
printf 'gitdir: /elsewhere\n' >"$themes_home/worktree/.config/omarchy/themes/branch/.git"

for shape in missing:1 empty:1 copied:1 cloned:0 linked:1 worktree:1; do
  assert_themes_guard_agrees \
    "Extra Themes shows exactly when omarchy-theme-update has something to pull" \
    "$themes_home/${shape%:*}" "${shape#*:}"
done
pass "Extra Themes shows exactly when omarchy-theme-update has something to pull"

# Which themes get pulled, not just that something did: a name with a space in
# it is the one that goes missing the moment a path is split rather than passed
# whole, and it would still print an Updating: line on its way to the wrong
# directory.
many="$themes_home/many/.config/omarchy/themes"
mkdir -p "$many/tokyo night/.git" "$many/zen/.git" "$many/handmade"
ln -s "$themes_home/checkout" "$many/in-progress"

listed=$(HOME="$themes_home/many" LC_ALL=C "$ROOT/bin/omarchy-theme-extras")
[[ $listed == "$many/tokyo night"$'\n'"$many/zen" ]] ||
  fail "omarchy-theme-extras lists every clone and nothing else" "got: $listed"
pass "omarchy-theme-extras lists every clone and nothing else"

git_calls=$(mktemp)
trap 'rm -rf "$stub_dir" "$themes_home" "$git_calls"' EXIT
HOME="$themes_home/many" LC_ALL=C GIT_CALLS="$git_calls" PATH="$ROOT/bin:$stub_dir:$PATH" \
  "$ROOT/bin/omarchy-theme-update" >/dev/null 2>&1
pulled=$(<"$git_calls")
[[ $pulled == "<-C><$many/tokyo night><pull>"$'\n'"<-C><$many/zen><pull>" ]] ||
  fail "omarchy-theme-update pulls each clone by its whole path" "got: $pulled"
pass "omarchy-theme-update pulls each clone by its whole path"

# Every guard the shipped menu carries has to be a self-contained expression
# the per-row bash -c can run: no batch-substituted readers, no leftovers from
# the Quickshell guard prelude.
while IFS= read -r guard; do
  [[ -n $guard ]] || continue
  bash -n -c "$guard" 2>/dev/null || fail "shipped menu guards parse as shell" "$guard"
  [[ $guard != *__omarchy_read_* ]] || fail "shipped menu guards carry no guard-prelude leftovers" "$guard"
done < <(menu_json | jq -r 'to_entries[].value | (.when // ""), (.checked // "")')
pass "shipped menu guards are self-contained shell expressions"
