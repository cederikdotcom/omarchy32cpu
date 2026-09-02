"""Render the Omarchy CPU divergence registry against a live upstream diff.

Reads .github/divergence/registry.json, diffs WORK_BRANCH against the current
upstream default branch, assigns every divergent path to exactly one registry
group, and renders the weighting as Markdown (job summary, issue bodies) or
JSON.

Accounting is fail-loud on purpose. A path no group claims, or a path two
groups claim, exits non-zero instead of quietly dropping out of the totals:
a registry that silently under-counts is worse than no registry.

Run with --help for the interface. Invoked as `python3` rather than being
executable, because AGENTS.md fixes bin/ shebangs to /bin/bash.
"""

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

MARKER_BEGIN = "<!-- omarchy-divergence:begin id={id} -->"
MARKER_END = "<!-- omarchy-divergence:end id={id} -->"

# Every status a group may declare. Kept closed so a typo cannot invent a
# status that renders but means nothing.
STATUSES = {
    "permanent",      # this fork will always differ here
    "substitute",     # upstream behaviour kept through a different component
    "deferred",       # upstream component works, deliberately not installed
    "porting",        # active work to close the gap
    "upstreamable",   # a change that should go back to upstream
    "resolved",       # divergence gone; the entry documents the history
}


class AccountingError(Exception):
    """Raised when the registry cannot account for the observed diff."""


def spec_to_regex(spec):
    """Translate a registry pathspec into an anchored regex.

    - a trailing "/" matches everything beneath that directory
    - "**" matches across directory separators
    - "*" matches within one path segment
    """
    if spec.endswith("/"):
        return re.compile(re.escape(spec) + ".*$")

    out = []
    i = 0
    while i < len(spec):
        if spec.startswith("**", i):
            out.append(".*")
            i += 2
        elif spec[i] == "*":
            out.append("[^/]*")
            i += 1
        elif spec[i] == "?":
            out.append("[^/]")
            i += 1
        else:
            out.append(re.escape(spec[i]))
            i += 1
    return re.compile("".join(out) + "$")


def load_registry(path):
    data = json.loads(Path(path).read_text())
    groups = data.get("groups")
    if not groups:
        raise AccountingError(f"{path} declares no groups")

    seen = set()
    for group in groups:
        for field in ("id", "title", "handling", "rationale", "status"):
            if not group.get(field):
                raise AccountingError(f"group {group.get('id', '?')!r} is missing {field!r}")
        if group["id"] in seen:
            raise AccountingError(f"duplicate group id {group['id']!r}")
        seen.add(group["id"])
        if group["status"] not in STATUSES:
            raise AccountingError(
                f"group {group['id']!r} has unknown status {group['status']!r}; "
                f"expected one of {sorted(STATUSES)}"
            )
        group.setdefault("pathspecs", [])
        group.setdefault("expect_paths", True)
        group.setdefault("shared_with", [])
        group.setdefault("issue", None)
        group["_matchers"] = [(spec, spec_to_regex(spec)) for spec in group["pathspecs"]]
    return data


def git(repo, *args):
    result = subprocess.run(
        ["git", "-C", str(repo), *args],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        raise AccountingError(f"git {' '.join(args)} failed: {result.stderr.strip()}")
    return result.stdout


def read_numstat(args):
    """Return the raw `git diff --numstat` text for base..head.

    Two-dot: the whole tree difference, not just our side of a merge base.
    A fork's accounting question is "how far is the tree from upstream's",
    which three-dot would understate after upstream is merged in.

    With --worktree the head is omitted, so git diffs the base against the
    files on disk. That is what makes the accounting checkable *before* a
    commit: comparing two refs cannot see a path you have not committed yet,
    so a forgotten pathspec would otherwise only surface in CI.
    """
    if args.numstat:
        return Path(args.numstat).read_text()
    if not args.base:
        raise AccountingError("--base is required unless --numstat is given")
    if args.worktree:
        # `git diff` reports tracked changes only, so on its own this would miss
        # a brand-new file -- the commonest way to add fork-only code, and the
        # exact case the pre-commit check exists for. Untracked files are
        # measured separately and folded in.
        tracked = git(args.repo, "diff", "--numstat", args.base, "--")
        return tracked + untracked_numstat(args.repo)
    return git(args.repo, "diff", "--numstat", args.base, args.head, "--")


def untracked_numstat(repo):
    """numstat lines for files git does not track yet, honouring .gitignore.

    Counted as pure additions, because that is what they are against any base.
    Binary detection follows git's own heuristic closely enough for a weight:
    a NUL byte early in the file means no line count, reported as "-" so it
    lands in the binary column rather than inflating the churn.
    """
    listing = git(repo, "ls-files", "--others", "--exclude-standard", "-z")
    lines = []
    for name in listing.split("\0"):
        if not name:
            continue
        blob = (Path(repo) / name).read_bytes()
        if b"\0" in blob[:8000]:
            lines.append(f"-\t-\t{name}")
        else:
            lines.append(f"{blob.count(b'\n') + (1 if blob and not blob.endswith(b'\n') else 0)}\t0\t{name}")
    return "\n".join(lines) + ("\n" if lines else "")


def parse_numstat(text):
    """Parse numstat into [{path, added, deleted, binary}] entries.

    Binary files report "-" for both counts. They still weigh one file each,
    and are counted separately so a churn number is never read as if it
    covered them.
    """
    entries = []
    for line in text.splitlines():
        if not line.strip():
            continue
        parts = line.split("\t")
        if len(parts) < 3:
            raise AccountingError(f"unparseable numstat line: {line!r}")
        added, deleted, path = parts[0], parts[1], parts[-1]
        binary = added == "-" or deleted == "-"
        entries.append(
            {
                "path": path,
                "added": 0 if binary else int(added),
                "deleted": 0 if binary else int(deleted),
                "binary": binary,
            }
        )
    return entries


def classify(entries, registry):
    """Assign each entry to exactly one group. Raises on any ambiguity."""
    groups = registry["groups"]
    buckets = {group["id"]: [] for group in groups}
    matched_specs = set()
    unclassified = []
    overlaps = []

    for entry in entries:
        hits = []
        for group in groups:
            for spec, pattern in group["_matchers"]:
                if pattern.match(entry["path"]):
                    hits.append((group["id"], spec))
                    matched_specs.add((group["id"], spec))
                    break
        if not hits:
            unclassified.append(entry["path"])
        elif len(hits) > 1:
            overlaps.append((entry["path"], hits))
        else:
            buckets[hits[0][0]].append(entry)

    problems = []
    if unclassified:
        problems.append(
            "unclassified paths (no registry group claims them):\n"
            + "\n".join(f"  {path}" for path in sorted(unclassified))
        )
    if overlaps:
        problems.append(
            "overlapping pathspecs (more than one group claims the path):\n"
            + "\n".join(
                f"  {path}: " + ", ".join(f"{gid} via {spec}" for gid, spec in hits)
                for path, hits in sorted(overlaps)
            )
        )
    if problems:
        raise AccountingError("\n\n".join(problems))

    # A group that declares pathspecs and matches nothing is not an error --
    # upstream may have adopted the change -- but it is the single most
    # actionable thing the report can say, so it is surfaced, not swallowed.
    stale_specs = []
    for group in groups:
        for spec, _ in group["_matchers"]:
            if (group["id"], spec) not in matched_specs:
                stale_specs.append((group["id"], spec))

    return buckets, stale_specs


def weigh(buckets, registry, entries):
    total_files = len(entries)
    total_lines = sum(e["added"] + e["deleted"] for e in entries)
    total_binary = sum(1 for e in entries if e["binary"])

    rows = []
    for group in registry["groups"]:
        bucket = buckets[group["id"]]
        files = len(bucket)
        lines = sum(e["added"] + e["deleted"] for e in bucket)
        rows.append(
            {
                "id": group["id"],
                "issue": group["issue"],
                "title": group["title"],
                "status": group["status"],
                "handling": group["handling"],
                "rationale": group["rationale"],
                "shared_with": group["shared_with"],
                "expect_paths": group["expect_paths"],
                "files": files,
                "added": sum(e["added"] for e in bucket),
                "deleted": sum(e["deleted"] for e in bucket),
                "lines": lines,
                "binary_files": sum(1 for e in bucket if e["binary"]),
                "files_pct": pct(files, total_files),
                "lines_pct": pct(lines, total_lines),
                "paths": sorted(e["path"] for e in bucket),
            }
        )

    # Heaviest first: the table is read to find where the weight sits.
    rows.sort(key=lambda row: (-row["lines"], -row["files"], row["id"]))
    return {
        "total_files": total_files,
        "total_lines": total_lines,
        "total_binary_files": total_binary,
        "total_added": sum(e["added"] for e in entries),
        "total_deleted": sum(e["deleted"] for e in entries),
        "groups": rows,
    }


def pct(part, whole):
    if whole == 0:
        return 0.0
    return round(part * 100.0 / whole, 1)


def cell(text):
    """Make a string safe inside a Markdown table cell.

    Path and title text reaches the report from upstream's tree, so it is
    treated as data: pipes are escaped so a crafted filename cannot forge
    extra columns, and newlines are folded so it cannot forge extra rows.
    """
    return str(text).replace("|", "\\|").replace("\n", " ").strip()


def issue_ref(issue):
    return f"#{issue}" if issue else "_none_"


def render_table(report):
    lines = [
        "| Divergence | Issue | Status | Files | % files | Lines | % lines |",
        "|---|---|---|---|---:|---:|---:|",
    ]
    for row in report["groups"]:
        lines.append(
            "| {title} (`{id}`) | {issue} | {status} | {files} | {files_pct}% | "
            "{lines} | {lines_pct}% |".format(
                title=cell(row["title"]),
                id=cell(row["id"]),
                issue=issue_ref(row["issue"]),
                status=cell(row["status"]),
                files=row["files"],
                files_pct=row["files_pct"],
                lines=row["lines"],
                lines_pct=row["lines_pct"],
            )
        )
    lines.append(
        "| **total** | | | **{files}** | 100% | **{lines}** | 100% |".format(
            files=report["total_files"], lines=report["total_lines"]
        )
    )
    return "\n".join(lines)


def render_group_block(row, context):
    """The per-issue body block. Deliberately carries no timestamp.

    Everything here is a function of (registry, upstream ref, diff). Two runs
    over an unchanged upstream therefore produce byte-identical text, the
    workflow's comparison sees no change, and the issue is left alone.
    """
    lines = [
        f"### Divergence accounting: `{row['id']}`",
        "",
        f"- **Handling**: {row['handling']}",
        f"- **Status**: {row['status']}",
        f"- **Weight**: {row['files']} of {context['total_files']} divergent files "
        f"({row['files_pct']}%), {row['lines']} of {context['total_lines']} changed lines "
        f"({row['lines_pct']}%) — +{row['added']} / -{row['deleted']}"
        + (f", {row['binary_files']} binary" if row["binary_files"] else ""),
        f"- **Measured against**: `{context['base_label']}` at `{context['base_sha']}` "
        f"vs `{context['head_label']}` at `{context['head_sha']}`",
    ]
    if row["shared_with"]:
        lines.append(
            "- **Shares files with**: "
            + ", ".join(f"`{gid}`" for gid in row["shared_with"])
            + " (each path is still counted once, here)"
        )
    lines += ["", f"**Why it diverges.** {row['rationale']}", ""]

    if row["paths"]:
        lines += ["<details><summary>Paths counted under this entry</summary>", ""]
        lines += [f"- `{cell(path)}`" for path in row["paths"]]
        lines += ["", "</details>"]
    elif row["expect_paths"]:
        lines.append(
            "**No divergent paths matched.** The registry expects this entry to own "
            "files and it currently owns none — either upstream adopted the change or "
            "the pathspecs are stale. Close the entry or fix its pathspecs."
        )
    else:
        lines.append(
            "**No divergent paths, by design.** This entry's work is carried outside "
            "the tree (out-of-repo builds and packaging), so it contributes 0% of the "
            "file-level divergence while remaining open."
        )

    lines += [
        "",
        "_Maintained by `.github/workflows/upstream-sync.yml`. Edit freely outside the "
        "markers; anything between them is regenerated on every sync run._",
    ]
    return "\n".join(lines)


def splice(existing, block, group_id):
    """Replace the marked block in `existing`, preserving everything else."""
    begin = MARKER_BEGIN.format(id=group_id)
    end = MARKER_END.format(id=group_id)
    payload = f"{begin}\n{block}\n{end}"

    start = existing.find(begin)
    stop = existing.find(end)
    if start != -1 and stop != -1 and stop > start:
        return existing[:start] + payload + existing[stop + len(end):]
    if not existing.strip():
        return payload + "\n"
    return existing.rstrip("\n") + "\n\n" + payload + "\n"


def render_markdown(report, context, stale_specs):
    lines = [
        "## Divergence from upstream",
        "",
        f"`{context['head_label']}` (`{context['head_sha']}`) against "
        f"`{context['base_label']}` (`{context['base_sha']}`): "
        f"**{report['total_files']} divergent files**, "
        f"**{report['total_lines']} changed lines** "
        f"(+{report['total_added']} / -{report['total_deleted']}"
        + (f", {report['total_binary_files']} binary files carry no line count"
           if report["total_binary_files"] else "")
        + ").",
        "",
        "Every divergent path is claimed by exactly one entry below; the percentages "
        "therefore sum to the whole, and an unclaimed or double-claimed path fails "
        "this job rather than disappearing from the totals.",
        "",
        render_table(report),
        "",
    ]

    if stale_specs:
        lines += [
            "### Pathspecs that matched nothing",
            "",
            "These entries claim paths that no longer diverge. Either upstream took the "
            "change, or the pathspec is stale — both are registry edits, not silent drift.",
            "",
        ]
        lines += [f"- `{gid}`: `{cell(spec)}`" for gid, spec in stale_specs]
        lines.append("")

    lines += ["### Entries", ""]
    for row in report["groups"]:
        lines += [
            f"#### {row['title']} (`{row['id']}`) — {issue_ref(row['issue'])}",
            "",
            f"- Status: {row['status']}",
            f"- Weight: {row['files']} files ({row['files_pct']}%), "
            f"{row['lines']} lines ({row['lines_pct']}%)",
            f"- Handling: {row['handling']}",
            f"- Why: {row['rationale']}",
            "",
        ]
    return "\n".join(lines)


def resolve_sha(repo, ref):
    if not ref:
        return "unknown"
    try:
        return git(repo, "rev-parse", "--short", ref).strip()
    except AccountingError:
        return "unknown"


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--registry", default=None, help="path to registry.json")
    parser.add_argument("--repo", default=".", help="git repository to inspect")
    parser.add_argument("--base", default=None, help="upstream ref to compare against")
    parser.add_argument("--head", default="HEAD", help="work ref (default HEAD)")
    parser.add_argument("--numstat", default=None,
                        help="read git diff --numstat output from a file instead of running git")
    parser.add_argument("--worktree", action="store_true",
                        help="compare against the files on disk, including uncommitted changes, "
                             "so a missing pathspec is caught before the commit rather than in CI")
    parser.add_argument("--base-label", default=None, help="label for the base ref in output")
    parser.add_argument("--head-label", default=None, help="label for the head ref in output")
    parser.add_argument("--format", choices=("markdown", "json", "table"), default="markdown")
    parser.add_argument("--issue-body", metavar="ID",
                        help="render only the marked issue block for one group id")
    parser.add_argument("--existing-body", metavar="FILE",
                        help="with --issue-body: splice into this body, preserving human content")
    parser.add_argument("--out", metavar="FILE", help="write to FILE instead of stdout")
    args = parser.parse_args(argv)

    repo = Path(args.repo)
    registry_path = args.registry or repo / ".github/divergence/registry.json"

    try:
        registry = load_registry(registry_path)
        entries = parse_numstat(read_numstat(args))
        buckets, stale_specs = classify(entries, registry)
    except AccountingError as error:
        print(f"divergence registry: {error}", file=sys.stderr)
        return 2

    report = weigh(buckets, registry, entries)
    if args.numstat:
        head_sha = "n/a"
    elif args.worktree:
        # Deliberately not a SHA: the working tree is not a commit, and
        # labelling it with HEAD's SHA in an issue body would be a lie.
        head_sha = "uncommitted"
    else:
        head_sha = resolve_sha(repo, args.head)
    context = {
        "total_files": report["total_files"],
        "total_lines": report["total_lines"],
        "base_label": args.base_label or args.base or "upstream",
        "head_label": args.head_label or ("working tree" if args.worktree else args.head),
        "base_sha": resolve_sha(repo, args.base) if not args.numstat else "n/a",
        "head_sha": head_sha,
    }

    if args.issue_body:
        row = next((r for r in report["groups"] if r["id"] == args.issue_body), None)
        if row is None:
            print(f"divergence registry: no group {args.issue_body!r}", file=sys.stderr)
            return 2
        block = render_group_block(row, context)
        existing = Path(args.existing_body).read_text() if args.existing_body else ""
        output = splice(existing, block, row["id"])
    elif args.format == "json":
        output = json.dumps(
            {"context": context, "report": report,
             "stale_pathspecs": [{"id": gid, "pathspec": spec} for gid, spec in stale_specs]},
            indent=2, sort_keys=True,
        ) + "\n"
    elif args.format == "table":
        output = render_table(report) + "\n"
    else:
        output = render_markdown(report, context, stale_specs) + "\n"

    if args.out:
        Path(args.out).write_text(output)
    else:
        sys.stdout.write(output)
    return 0


if __name__ == "__main__":
    sys.exit(main())
