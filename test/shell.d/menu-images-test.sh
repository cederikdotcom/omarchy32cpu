#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

# Omarchy CPU's image selector is a fuzzel list of image names: no thumbnail
# cache, no locks. The calling contract stays: the selection's full path is
# printed (bare name with --print-name), cancel prints nothing and exits 0,
# and the old thumbnail-cache flags are accepted as no-ops.

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

images="$tmp/images"
extra="$tmp/extra"
stub_bin="$tmp/bin"
mkdir -p "$images" "$extra" "$stub_bin"

# fuzzel --dmenu --index: record the offered rows, answer with a fixed index
# (or cancel).
cat >"$stub_bin/fuzzel" <<'EOF'
#!/bin/bash

cat >"${FUZZEL_ROWS_FILE:-/dev/null}"
[[ ${FUZZEL_CANCEL:-0} == "1" ]] && exit 2
printf '%s\n' "${FUZZEL_INDEX:-0}"
EOF
chmod +x "$stub_bin/fuzzel"

for name in alpha beta gamma; do
  printf 'image-%s' "$name" >"$images/$name.png"
done

run_menu() {
  PATH="$stub_bin:$PATH" "$ROOT/bin/omarchy-menu-images" "$@"
}

# Thumbnail-cache flags are accepted no-ops: exit 0, no output, no cache dirs.
cache_out=$(XDG_CACHE_HOME="$tmp/cache" run_menu --cache-only "$images") ||
  fail "cache-only run exits cleanly"
[[ -z $cache_out ]] || fail "cache-only run prints nothing" "$cache_out"
[[ ! -e $tmp/cache/omarchy ]] || fail "cache-only run creates no cache"
XDG_CACHE_HOME="$tmp/cache" run_menu --preload --lazy-thumbnails "$images" >/dev/null <<<"" ||
  fail "legacy thumbnail flags are still accepted"
pass "legacy thumbnail-cache flags are accepted as no-ops"

# The selection maps back to the full path by row index.
selection=$(FUZZEL_ROWS_FILE="$tmp/rows" FUZZEL_INDEX=1 run_menu "$images")
[[ $selection == "$images/beta.png" ]] ||
  fail "image menu prints the full path of the selected row" "$selection"
printf '%s\n' alpha beta gamma | cmp -s - "$tmp/rows" ||
  fail "image menu offers bare names without extensions" "$(cat "$tmp/rows")"
pass "image menu maps the chosen row back to its image path"

# --print-name answers with the bare name instead of the path.
selection=$(FUZZEL_INDEX=2 run_menu --print-name "$images")
[[ $selection == "gamma" ]] ||
  fail "image menu prints the bare name with --print-name" "$selection"
pass "image menu prints the bare name with --print-name"

# The current selection is offered first, so plain Enter keeps it.
selection=$(FUZZEL_ROWS_FILE="$tmp/rows" FUZZEL_INDEX=0 run_menu --selected "$images/beta.png" "$images")
[[ $selection == "$images/beta.png" ]] ||
  fail "image menu keeps the current selection on Enter" "$selection"
[[ $(head -n 1 "$tmp/rows") == "beta" ]] ||
  fail "image menu lists the current selection first" "$(cat "$tmp/rows")"
pass "image menu lists the current selection first"

# Cancel prints nothing and exits 0, so callers see "no change".
selection=$(FUZZEL_CANCEL=1 run_menu "$images") ||
  fail "a cancelled image menu exits cleanly"
[[ -z $selection ]] || fail "a cancelled image menu prints nothing" "$selection"
pass "a cancelled image menu prints nothing and exits cleanly"

# Duplicate names across directories stay unambiguous through index mapping
# (paths sort globally, so $extra/alpha.png lands ahead of $images/alpha.png).
printf 'other-alpha' >"$extra/alpha.png"
selection=$(FUZZEL_ROWS_FILE="$tmp/rows" FUZZEL_INDEX=0 run_menu "$images" "$extra")
[[ $selection == "$extra/alpha.png" ]] ||
  fail "duplicate names across directories resolve by index" "$selection"
[[ $(grep -cx alpha "$tmp/rows") == 2 ]] ||
  fail "both same-named images are offered" "$(cat "$tmp/rows")"
pass "duplicate image names across directories stay unambiguous"

# No image directory is a usage error; an empty one reports no images.
run_menu >/dev/null 2>&1 && fail "image menu requires an image directory"
mkdir -p "$tmp/empty"
run_menu "$tmp/empty" >/dev/null 2>&1 && fail "an imageless directory is an error"
pass "image menu rejects empty input"
