#!/bin/bash

# The divergence registry is only worth committing if it can be trusted to
# account for the whole diff, so this covers the two ways it could lie -
# a path no entry claims, and a path two entries claim - alongside the
# weighting arithmetic and the idempotence the workflow's issue writes need.

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command python3

REPORT="$ROOT/.github/divergence/report.py"
REGISTRY="$ROOT/.github/divergence/registry.json"
FIXTURES="$SHELL_TEST_DIR/fixtures/divergence"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

report() { # REGISTRY [args...]
  local registry="$1"
  shift
  python3 "$REPORT" --repo "$ROOT" --registry "$registry" \
    --numstat "$FIXTURES/numstat.txt" "$@"
}

# --- classification -------------------------------------------------------

json="$test_tmp/report.json"
report "$FIXTURES/registry.json" --format json >"$json"

python3 - "$json" <<'PYTHON' || fail "every fixture path lands in the entry that claims it"
import json, sys

report = json.load(open(sys.argv[1]))["report"]
groups = {g["id"]: g for g in report["groups"]}

expected = {
  "alpha": ["alpha/one.sh", "alpha/two.sh", "assets/logo.png"],
  "beta": ["beta/gone.sh"],
  "gamma": ["gamma/only.sh"],
  "delta": [],
}
for gid, paths in expected.items():
  if groups[gid]["paths"] != paths:
    print(f"{gid}: got {groups[gid]['paths']}, want {paths}", file=sys.stderr)
    sys.exit(1)
PYTHON
pass "classification assigns each path to the single entry whose pathspec matches"

# A pathspec that matches nothing is reported rather than dropped: it is how a
# divergence upstream has since adopted becomes visible.
python3 - "$json" <<'PYTHON' || fail "a pathspec matching nothing is reported as stale"
import json, sys

stale = json.load(open(sys.argv[1]))["stale_pathspecs"]
if stale != [{"id": "beta", "pathspec": "beta/never-matches.sh"}]:
  print(f"got {stale}", file=sys.stderr)
  sys.exit(1)
PYTHON
pass "a pathspec that matches no divergent path is surfaced as stale"

# --- the two ways the accounting could silently lose a path ---------------

set +e
output=$(report "$FIXTURES/registry-unclassified.json" --format json 2>&1)
status=$?
set -e
((status == 2)) || fail "an unclassified path fails the run" "exit $status"
grep -q 'unclassified paths' <<<"$output" || fail "the failure names the problem" "$output"
grep -q 'beta/gone.sh' <<<"$output" || fail "the failure names the unclassified path" "$output"
pass "a path no entry claims fails loudly instead of vanishing from the totals"

set +e
output=$(report "$FIXTURES/registry-overlap.json" --format json 2>&1)
status=$?
set -e
((status == 2)) || fail "an overlapping pathspec fails the run" "exit $status"
grep -q 'overlapping pathspecs' <<<"$output" || fail "the failure names the problem" "$output"
grep -q 'alpha/one.sh' <<<"$output" || fail "the failure names the doubly-claimed path" "$output"
pass "a path two entries claim fails loudly instead of being counted twice"

# --- weighting ------------------------------------------------------------

python3 - "$json" <<'PYTHON' || fail "weights measure files and line churn against the totals"
import json, sys

report = json.load(open(sys.argv[1]))["report"]
groups = {g["id"]: g for g in report["groups"]}

# 5 files, one of them binary; 15 + 3 + 40 + 14 = 72 changed lines.
assert report["total_files"] == 5, report["total_files"]
assert report["total_lines"] == 72, report["total_lines"]
assert report["total_binary_files"] == 1, report["total_binary_files"]

# A binary file weighs one file and no lines, and says so separately.
assert groups["alpha"]["files"] == 3, groups["alpha"]["files"]
assert groups["alpha"]["binary_files"] == 1, groups["alpha"]["binary_files"]
assert groups["alpha"]["lines"] == 18, groups["alpha"]["lines"]
assert groups["alpha"]["added"] == 13 and groups["alpha"]["deleted"] == 5

assert groups["alpha"]["files_pct"] == 60.0, groups["alpha"]["files_pct"]
assert groups["alpha"]["lines_pct"] == 25.0, groups["alpha"]["lines_pct"]
assert groups["beta"]["lines_pct"] == 55.6, groups["beta"]["lines_pct"]

# An entry that declares no paths weighs nothing and is not an error.
assert groups["delta"]["files"] == 0 and groups["delta"]["lines"] == 0

assert sum(g["files"] for g in report["groups"]) == report["total_files"]
assert sum(g["lines"] for g in report["groups"]) == report["total_lines"]

# Heaviest first, so the table is read top-down.
assert [g["id"] for g in report["groups"]] == ["beta", "alpha", "gamma", "delta"]
PYTHON
pass "each entry's weight is its share of the divergent files and of the line churn"

report "$FIXTURES/registry.json" --format table >"$test_tmp/table.md"
grep -q '| \*\*total\*\* | | | \*\*5\*\* | 100% | \*\*72\*\* | 100% |' "$test_tmp/table.md" ||
  fail "the table carries the totals the percentages are taken against" "$(cat "$test_tmp/table.md")"
pass "the rendered table states the totals the percentages divide"

# --- issue bodies: idempotence and human content --------------------------

report "$FIXTURES/registry.json" --issue-body alpha >"$test_tmp/body-1.md"
report "$FIXTURES/registry.json" --issue-body alpha --existing-body "$test_tmp/body-1.md" \
  >"$test_tmp/body-2.md"
cmp -s "$test_tmp/body-1.md" "$test_tmp/body-2.md" ||
  fail "re-rendering an unchanged entry into its own body changes nothing" \
    "$(diff "$test_tmp/body-1.md" "$test_tmp/body-2.md" || true)"
pass "an unchanged entry renders byte-identically, so the workflow can skip the write"

grep -q '<!-- omarchy-divergence:begin id=alpha -->' "$test_tmp/body-1.md" ||
  fail "the generated block is delimited by a marker the next run can find"
grep -q '25.0%' "$test_tmp/body-1.md" || fail "the issue body carries the entry's weight"
pass "the issue body carries its own marker and its measured weight"

cat >"$test_tmp/human.md" <<'BODY'
## Goal

Something a person wrote and expects to keep.

<!-- omarchy-divergence:begin id=alpha -->
stale generated content from an older run
<!-- omarchy-divergence:end id=alpha -->

## Acceptance

A closing section, also written by a person.
BODY

report "$FIXTURES/registry.json" --issue-body alpha --existing-body "$test_tmp/human.md" \
  >"$test_tmp/merged.md"
grep -q 'Something a person wrote and expects to keep.' "$test_tmp/merged.md" ||
  fail "splicing preserves human content above the marker"
grep -q 'A closing section, also written by a person.' "$test_tmp/merged.md" ||
  fail "splicing preserves human content below the marker"
! grep -q 'stale generated content' "$test_tmp/merged.md" ||
  fail "splicing replaces the previous generated block rather than stacking a new one"
(( $(grep -c 'omarchy-divergence:begin id=alpha' "$test_tmp/merged.md") == 1 )) ||
  fail "splicing leaves exactly one generated block"
pass "splicing rewrites only the marked block and keeps everything a human wrote"

# A body with no marker yet gains one without losing what was there.
printf '## Goal\n\nNo marker here yet.\n' >"$test_tmp/unmarked.md"
report "$FIXTURES/registry.json" --issue-body alpha --existing-body "$test_tmp/unmarked.md" \
  >"$test_tmp/appended.md"
grep -q 'No marker here yet.' "$test_tmp/appended.md" ||
  fail "a first run appends to the existing body instead of replacing it"
grep -q 'omarchy-divergence:begin id=alpha' "$test_tmp/appended.md" ||
  fail "a first run adds the marker"
pass "a first run appends the block to an existing issue without overwriting it"

# An entry that owns no paths by design says so; one that expects paths and has
# none says the opposite, because those are different problems.
report "$FIXTURES/registry.json" --issue-body delta | grep -q 'by design' ||
  fail "an entry that declares no paths reports its zero weight as deliberate"
pass "a deliberately path-less entry reports zero weight without claiming an error"

# --- table cells cannot be forged by upstream path names ------------------

printf '1\t1\talpha/pipe|name.sh\n' >"$test_tmp/hostile.txt"
python3 "$REPORT" --repo "$ROOT" --registry "$FIXTURES/registry.json" \
  --numstat "$test_tmp/hostile.txt" --issue-body alpha | grep -q 'pipe\\|name.sh' ||
  fail "a pipe in an upstream path is escaped rather than forging a table column"
pass "path text from upstream is escaped before it reaches a Markdown cell"

# --- --worktree sees uncommitted work ------------------------------------

# The whole point of the flag: comparing two refs cannot see a path that is not
# committed yet, so without this a forgotten pathspec first surfaces in CI. Built
# as a throwaway repo rather than by writing into this one, which is shared.
scratch_repo="$test_tmp/scratch"
mkdir -p "$scratch_repo"
git -C "$scratch_repo" init -q
git -C "$scratch_repo" config user.email test@example.com
git -C "$scratch_repo" config user.name "divergence test"
mkdir -p "$scratch_repo/alpha"
printf 'base\n' >"$scratch_repo/alpha/one.sh"
git -C "$scratch_repo" add -A
git -C "$scratch_repo" commit -qm base
base_sha=$(git -C "$scratch_repo" rev-parse HEAD)

# An uncommitted file no entry claims.
printf 'new\n' >"$scratch_repo/unclaimed.sh"

set +e
output=$(python3 "$REPORT" --repo "$scratch_repo" --registry "$FIXTURES/registry.json" \
  --base "$base_sha" --worktree --format json 2>&1)
status=$?
set -e
((status == 2)) || fail "--worktree fails on an uncommitted path no entry claims" "exit $status"
grep -q 'unclaimed.sh' <<<"$output" || fail "the failure names the uncommitted path" "$output"

# The same tree, compared between refs, cannot see it at all.
python3 "$REPORT" --repo "$scratch_repo" --registry "$FIXTURES/registry.json" \
  --base "$base_sha" --head HEAD --format json >/dev/null ||
  fail "a ref-to-ref comparison is blind to the uncommitted path, as expected"
pass "--worktree catches an unregistered path before the commit, where a ref comparison cannot"

# Claim it, and the same run passes and counts it.
python3 - "$FIXTURES/registry.json" "$test_tmp/claimed.json" <<'PYTHON'
import json, sys

registry = json.load(open(sys.argv[1]))
registry["groups"][0]["pathspecs"].append("unclaimed.sh")
json.dump(registry, open(sys.argv[2], "w"))
PYTHON

python3 "$REPORT" --repo "$scratch_repo" --registry "$test_tmp/claimed.json" \
  --base "$base_sha" --worktree --format json >"$test_tmp/worktree.json" ||
  fail "--worktree passes once the path is claimed"

python3 - "$test_tmp/worktree.json" <<'PYTHON' || fail "--worktree counts the uncommitted path and labels the head honestly"
import json, sys

data = json.load(open(sys.argv[1]))
groups = {g["id"]: g for g in data["report"]["groups"]}
assert "unclaimed.sh" in groups["alpha"]["paths"], groups["alpha"]["paths"]
# The working tree is not a commit, so it must not be labelled with one.
assert data["context"]["head_sha"] == "uncommitted", data["context"]["head_sha"]
assert data["context"]["head_label"] == "working tree", data["context"]["head_label"]
PYTHON
pass "--worktree counts uncommitted paths and never labels the tree with a commit sha"

# --- the committed registry ----------------------------------------------

python3 - "$REGISTRY" <<'PYTHON' || fail "the committed registry is well formed"
import json, sys

registry = json.load(open(sys.argv[1]))
groups = registry["groups"]

ids = [g["id"] for g in groups]
assert len(ids) == len(set(ids)), "duplicate entry id"

issues = [g["issue"] for g in groups if g.get("issue")]
assert len(issues) == len(set(issues)), "two entries claim the same issue"

for group in groups:
  for field in ("id", "title", "handling", "rationale", "status"):
    assert group.get(field), f"{group.get('id')} is missing {field}"
  # An entry with no pathspecs has to say that is deliberate, or the report
  # cannot tell "carried outside the tree" from "pathspecs went stale".
  if not group.get("pathspecs"):
    assert group.get("expect_paths") is False, f"{group['id']} declares no pathspecs"
  for other in group.get("shared_with", []):
    assert other in ids, f"{group['id']} shares with unknown entry {other}"
PYTHON
pass "the committed registry has unique entries, one issue each, and no dangling references"

# The live check only means something where upstream is fetched; a checkout
# without it should not turn this file red.
upstream_ref=${OMARCHY_DIVERGENCE_BASE:-upstream/quattro}
if git -C "$ROOT" rev-parse --verify --quiet "$upstream_ref" >/dev/null; then
  set +e
  output=$(python3 "$REPORT" --repo "$ROOT" --base "$upstream_ref" --format json 2>&1)
  status=$?
  set -e
  ((status == 0)) ||
    fail "the committed registry accounts for every path that diverges from $upstream_ref" "$output"
  pass "the committed registry classifies the live diff against $upstream_ref completely"
else
  pass "no $upstream_ref ref here; skipping the live divergence classification"
fi
