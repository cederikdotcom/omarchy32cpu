#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

require_command python3

# The default bindings now live in default/sway/config as plain bindsym /
# bindcode lines. Print one normalized line per binding: signature, chord as
# written, action. The signature expands $mod, sorts modifiers, and resolves
# bindcode numbers to the keysym they produce, so "bindcode $mod+10" and
# "bindsym $mod+1" collide the way they do on a real keyboard. Mode blocks
# (e.g. the resize mode) are separate binding contexts and get a prefix.
list_bindings() {
  python3 - "$1" <<'PY'
import re
import sys

# X11 keycodes are evdev codes plus 8. Only the rows Omarchy binds by code
# need naming; anything else keeps its code: form and still compares exactly.
keycode_keysyms = {
    "10": "1", "11": "2", "12": "3", "13": "4", "14": "5",
    "15": "6", "16": "7", "17": "8", "18": "9", "19": "0",
    "20": "MINUS", "21": "EQUAL",
    "34": "BRACKETLEFT", "35": "BRACKETRIGHT",
    "47": "SEMICOLON", "48": "APOSTROPHE", "49": "GRAVE", "51": "BACKSLASH",
    "59": "COMMA", "60": "PERIOD", "61": "SLASH",
}

mod = "MOD4"
mode = ""
for raw in open(sys.argv[1]):
    line = raw.strip()
    m = re.match(r'^set\s+\$mod\s+(\S+)$', line)
    if m:
        mod = m.group(1).upper()
        continue
    m = re.match(r'^mode\s+"([^"]+)"', line)
    if m:
        mode = m.group(1)
        continue
    if line == "}":
        mode = ""
        continue
    m = re.match(r'^(bindsym|bindcode)\s+(.*)$', line)
    if not m:
        continue
    kind, rest = m.groups()
    tokens = rest.split()
    release = False
    while tokens and tokens[0].startswith("--"):
        if tokens[0] == "--release":
            release = True
        tokens.pop(0)
    if not tokens:
        continue
    chord = tokens[0]
    action = " ".join(tokens[1:])
    parts = [p for p in chord.split("+") if p]
    parts = [mod if p == "$mod" else p.upper() for p in parts]
    key = parts.pop()
    if kind == "bindcode":
        key = keycode_keysyms.get(key, "CODE:" + key)
    signature = "+".join(sorted(parts) + [key])
    if mode:
        signature = mode + ":" + signature
    if release:
        signature += " (release)"
    print("\t".join([signature, chord, action]))
PY
}

duplicate_signatures() {
  cut -f1 | sort | uniq -d
}

sway_config="$ROOT/default/sway/config"

bindings=$(list_bindings "$sway_config")
[[ -n $bindings ]] || fail "default bindings load for the conflict check"

grep -Fq $'MOD4+RETURN\t$mod+Return\texec omarchy-launch-terminal' <<<"$bindings" ||
  fail "conflict check sees the essential bindings"
pass "conflict check covers the default binding set"

duplicates=$(duplicate_signatures <<<"$bindings")

while read -r signature; do
  [[ -n $signature ]] || continue
  fail "no two default bindings claim the same chord" \
    "$(awk -F'\t' -v signature="$signature" '$1 == signature { print $2 " -> " $3 }' <<<"$bindings")"
done <<<"$duplicates"
pass "no two default bindings claim the same chord"

# Guard the guard: the checker has to catch an injected collision, or the
# check above passes by simply not looking.
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

probe_config="$tmpdir/config"

cp "$sway_config" "$probe_config"
printf 'bindcode $mod+10 exec conflict-probe\n' >>"$probe_config"
probe=$(list_bindings "$probe_config" | duplicate_signatures)
grep -Fqx 'MOD4+1' <<<"$probe" ||
  fail "the conflict check catches a keycode colliding with a bound keysym"

# Modifier order is cosmetic; sway binds the same chord either way.
cp "$sway_config" "$probe_config"
printf 'bindsym $mod+Alt+Shift+Right exec conflict-probe\n' >>"$probe_config"
probe=$(list_bindings "$probe_config" | duplicate_signatures)
grep -Fqx 'ALT+MOD4+SHIFT+RIGHT' <<<"$probe" ||
  fail "the conflict check ignores modifier order"
pass "the conflict check catches collisions across keycodes and modifier order"

# A mode block is its own binding context, not a collision with the default
# context.
cp "$sway_config" "$probe_config"
printf 'mode "probe" {\n  bindsym $mod+Return exec conflict-probe\n}\n' >>"$probe_config"
probe=$(list_bindings "$probe_config" | duplicate_signatures)
[[ -z $probe ]] ||
  fail "mode-local bindings do not read as conflicts with the default context" "$probe"
pass "mode-local bindings keep their own binding context"
