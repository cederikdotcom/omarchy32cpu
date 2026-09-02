# Divergence registry

This fork replaces a bootloader, a greeter, a renderer, a session manager and most of a package set. Recorded one file at a time, that is 150 unrelated differences and nobody can say which of them matter. Recorded as prose, it goes stale the first time upstream moves.

The registry is the third option: a small set of **semantic divergence entries**, each with a stable id, a GitHub issue, the pathspecs it owns, how the divergence is handled, why it exists, and a status. A script assigns every divergent path to exactly one entry and measures what share of the total each entry accounts for, so "how far from upstream are we, and where does the weight sit" has a checkable answer rather than a remembered one.

## The pieces

- [`.github/divergence/registry.json`](../.github/divergence/registry.json) - the registry itself. Machine-readable, and the only place an entry is defined.
- [`.github/divergence/report.py`](../.github/divergence/report.py) - diffs the work branch against upstream's current default branch, classifies, weighs, and renders Markdown or JSON.
- [`.github/workflows/upstream-sync.yml`](../.github/workflows/upstream-sync.yml) - runs the report on every scheduled and manual sync, writes the table into the job summary, and refreshes each linked issue.
- [`test/shell.d/divergence-registry-test.sh`](../test/shell.d/divergence-registry-test.sh) - covers classification, the two failure modes, the weighting arithmetic, and issue-body idempotence.

## Entry schema

| Field | Meaning |
|---|---|
| `id` | Stable slug. Appears in the issue markers, so it does not change once an issue is linked. |
| `issue` | The GitHub issue tracking this divergence, or `null` until one exists. |
| `title` | One line, human-facing. |
| `status` | `permanent`, `substitute`, `deferred`, `porting`, `upstreamable`, or `resolved`. |
| `pathspecs` | The paths this entry owns. A trailing `/` matches a whole subtree; `*` matches within a segment, `**` across them. |
| `expect_paths` | Set `false` for an entry that knowingly owns no files because its work lives outside this tree. Any other entry matching nothing is reported as stale. |
| `handling` | What this fork actually does instead of what upstream does. |
| `rationale` | Why. This is the field that stops a decision being re-argued from memory. |
| `shared_with` | Other entries whose reasoning also touches these files. Documentation only - the path is still counted once. |

## The two rules that make the numbers mean something

**Every divergent path is claimed by exactly one entry.** A path no entry claims fails the run. A path two entries claim fails the run. Neither is a warning, because the failure mode being guarded against is arithmetic that still looks plausible after a path quietly stops being counted.

Where one file diverges for more than one reason - `default/omarchy/omarchy-menu.jsonc` is rewired by three separate entries - it is owned by the entry that explains the larger share of its changed lines, and the others name it in `shared_with`.

**A pathspec that matches nothing is reported, not ignored.** It means upstream took the change, or the file moved. Both are registry edits.

## Running it

```bash
git fetch upstream                                              # the default branch, whatever it is called
python3 .github/divergence/report.py --base upstream/quattro    # full Markdown report
python3 .github/divergence/report.py --base upstream/quattro --format table
python3 .github/divergence/report.py --base upstream/quattro --format json
```

**Before you commit**, add `--worktree`:

```bash
python3 .github/divergence/report.py --base upstream/quattro --worktree
```

A ref-to-ref comparison cannot see a path you have not committed yet, so without this a forgotten pathspec first surfaces in CI. `--worktree` diffs against the files on disk and folds in untracked files (honouring `.gitignore`), which is the commonest way a fork-only file goes unregistered. It exits 2 and names the path, exactly as the sync job would.

`--issue-body <id>` renders the block that goes into that entry's issue; with `--existing-body <file>` it splices into the current body, replacing only what sits between the entry's markers and leaving everything a person wrote intact.

The block carries no timestamp, so a run against an unchanged upstream renders byte-identically and the workflow skips the write.

## When you change something

- Adding a fork-only file, or forking one upstream owns, means adding it to an entry's `pathspecs`. Run the `--worktree` check above before committing; the sync job fails loudly if you do not, which is the point.
- Closing a gap - upstream adopts a change, or the fork drops a substitute - means the pathspec stops matching. Move the entry to `resolved` and close its issue, rather than leaving a stale claim.
- The weights move on every commit to the work branch, not only when upstream moves. That is why the report runs on every invocation of the sync workflow instead of only when we are behind.

## What it does not measure

File count and line churn are proxies for effort, not for risk. `quattro-upgrade-tool` is a quarter of the line churn and carries no risk at all - it is one deleted script that can never run here - while `render-cpu` owns a modest slice of the tree and represents the fork's entire reason to exist, most of which lives in out-of-repo compositor patches that this table cannot see. `shell-qt-software` is in the registry at exactly 0% for the same reason.

Read the table for where the *merge conflicts* will come from. Read the `status` and `rationale` fields for where the *work* is.
