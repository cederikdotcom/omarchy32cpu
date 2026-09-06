"""Daily upstream merge queue. No merges, builds or deployments are performed."""
import argparse
import html
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
BEGIN = "<!-- upstream-monitor:begin -->"
END = "<!-- upstream-monitor:end -->"

def run(*args, check=True):
    return subprocess.run(args, cwd=ROOT, text=True, capture_output=True, check=check)

def git(*args):
    return run("git", *args).stdout.strip()

def splice(existing, block):
    start, stop = existing.find(BEGIN), existing.find(END)
    wrapped = BEGIN + "\n" + block + "\n" + END
    if start >= 0 and stop > start:
        return existing[:start] + wrapped + existing[stop + len(END):]
    return existing.rstrip() + ("\n\n" if existing.strip() else "") + wrapped + "\n"

def tip_of(issue):
    match = re.search(r"<!-- upstream-tip:([0-9a-f]{40}) -->", issue.get("body") or "")
    return match.group(1) if match else None

def choose(issues, marker, target, missing, ancestor):
    owned = [i for i in issues if "pull_request" not in i and marker in (i.get("body") or "")]
    integrated = [i for i in owned if i["state"] == "open" and tip_of(i) and ancestor(tip_of(i))]
    pending = [i for i in owned if i["state"] == "open" and i not in integrated]
    if len(pending) > 1:
        raise RuntimeError("Duplicate open merge issues: resolve explicitly before refreshing")
    if not missing:
        return integrated, "none", None
    if pending:
        return integrated, "update", pending[0]
    closed_same = [i for i in owned if i["state"] == "closed" and tip_of(i) == target]
    if closed_same:
        return integrated, "closed", closed_same[0]
    return integrated, "create", None

def ancestor(sha):
    result = run("git", "merge-base", "--is-ancestor", sha, "HEAD", check=False)
    if result.returncode not in (0, 1):
        raise RuntimeError("Cannot resolve previously tracked upstream commit " + sha)
    return result.returncode == 0

def body_block(config, branch, target, missing, clean, details):
    head = git("rev-parse", "HEAD")
    marker = "<!-- upstream-queue:" + config["repo"] + ":" + config["work_branch"] + ":" + branch + " -->"
    commits = git("log", "--format=%h %s", "--max-count=60", "HEAD.." + target)
    return "\n".join([
        marker, "<!-- upstream-tip:" + target + " -->",
        "## Upstream merge required", "",
        "- Repository: " + config["repo"] + "; target branch: " + config["work_branch"],
        "- Upstream: " + config["upstream"] + " / " + branch,
        "- Checked fork HEAD: `" + head + "`",
        "- Upstream target: `" + target + "`",
        "- Missing by ancestry: **" + str(missing) + " commits**.",
        "- Merge-tree check: **" + clean + "** (not a build or runtime test).",
        "", "### Incoming commits (up to 60)", "",
        "<pre>" + html.escape(commits) + "</pre>",
        "", "### Merge-tree diagnostics", "",
        "<pre>" + html.escape(details[:6000]) + "</pre>",
        "", "### Integration checklist", "",
        "- Review the incoming changes and resolve conflicts on a working branch.",
        "- Build and run focused tests; update the divergence registry and baseline only where justified.",
        "- Validate the affected CPU/i686 paths before any Mac deployment.",
        "- Merge the reviewed result and record validation evidence in a comment.",
        "",
        "This issue batches pending upstream changes; subsequent checks update it instead of opening daily duplicates.",
        "The monitor closes it when the recorded upstream target is an ancestor of the checked fork branch.",
        "That closure proves source integration only, not hardware acceptance. A subsequent batch gets a new issue.",
        "A manually closed issue for the same target stays closed; a newer target can open a new batch.",
        "Commit ancestry is not patch equivalence, especially for Hyprland release-branch versus main history.",
        "Nothing was merged or deployed automatically. Human notes outside these markers are preserved.",
    ])

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--publish", action="store_true", help="write merge queue issues (default read-only)")
    args = parser.parse_args()
    config = json.loads((ROOT / ".github/divergence/monitor.json").read_text())
    repo = config["repo"]
    if os.environ.get("GITHUB_REPOSITORY", repo) != repo:
        raise SystemExit("Refusing to write issues from a different repository")
    actual = git("rev-parse", "HEAD")
    expected = git("rev-parse", "origin/" + config["work_branch"])
    if actual != expected:
        raise SystemExit("Checkout does not match the monitored remote work branch")
    # gh writes always pin -R; upstream commit subjects are data, never shell code.
    pages = json.loads(run("gh", "api", "--paginate", "--slurp",
                           "repos/" + repo + "/issues?state=all&per_page=100").stdout)
    issues = [issue for page in pages for issue in page]
    summaries = []
    for branch in config["upstream_branches"]:
        git("fetch", "--no-tags", "https://github.com/" + config["upstream"] + ".git",
            "+refs/heads/" + branch + ":refs/remotes/upstream/" + branch)
        target = git("rev-parse", "refs/remotes/upstream/" + branch)
        missing = int(git("rev-list", "--count", "HEAD.." + target))
        marker = "<!-- upstream-queue:" + repo + ":" + config["work_branch"] + ":" + branch + " -->"
        completed, action, issue = choose(issues, marker, target, missing, ancestor)
        if missing:
            merge = run("git", "merge-tree", "--write-tree", "--name-only", "HEAD", target, check=False)
            if merge.returncode not in (0, 1):
                raise RuntimeError("Merge-tree failed: " + merge.stderr)
            clean = "clean" if merge.returncode == 0 else "conflicts"
            details = merge.stdout + merge.stderr
            block = body_block(config, branch, target, missing, clean, details)
        else:
            clean = "already integrated"
        summary = repo + " / " + branch + ": " + str(missing) + " missing; " + clean + "; queue=" + action
        print(summary, flush=True)
        summaries.append(summary)
        if not args.publish:
            continue
        for old in completed:
            run("gh", "issue", "close", str(old["number"]), "-R", repo, "--reason", "completed",
                "--comment", "Monitor: the recorded upstream target is now in the fork branch ancestry. Source integration detected; this is not a hardware-validation result.")
        if action not in ("create", "update"):
            continue
        title = "Merge upstream " + branch + " into " + config["work_branch"] + " (" + str(missing) + " commits)"
        body = splice((issue or {}).get("body") or "", block)
        if issue and body == issue["body"] and title == issue["title"]:
            continue
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "issue.md"
            path.write_text(body)
            command = ["gh", "issue", "create" if action == "create" else "edit"]
            if issue:
                command.append(str(issue["number"]))
            command += ["-R", repo, "--title", title, "--body-file", str(path)]
            print(run(*command).stdout.strip(), flush=True)
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as summary:
            summary.write("\n## Daily upstream merge queue\n\n" + "\n".join("- " + s for s in summaries) + "\n")

if __name__ == "__main__":
    main()
