"""Merge queue lifecycle and safe failure regression tests."""
import subprocess
import unittest
from unittest.mock import patch
import monitor

MARK = "<!-- upstream-queue:owner/repo:cpu:main -->"
OLD = "a" * 40
NEW = "b" * 40

def issue(number=1, state="open", tip=OLD):
    return {"number": number, "state": state, "title": "Merge",
            "body": MARK + "\n<!-- upstream-tip:" + tip + " -->"}

class QueueTests(unittest.TestCase):
    def test_no_backlog_no_issue(self):
        self.assertEqual(monitor.choose([], MARK, NEW, 0, lambda _: False)[1], "none")

    def test_first_backlog_creates(self):
        self.assertEqual(monitor.choose([], MARK, NEW, 2, lambda _: False)[1], "create")

    def test_same_backlog_updates(self):
        old = issue()
        self.assertEqual(monitor.choose([old], MARK, OLD, 2, lambda _: False)[1:], ("update", old))

    def test_new_tip_extends_pending_batch(self):
        old = issue()
        self.assertEqual(monitor.choose([old], MARK, NEW, 3, lambda _: False)[1:], ("update", old))

    def test_integrated_batch_closes(self):
        old = issue()
        self.assertEqual(monitor.choose([old], MARK, OLD, 0, lambda _: True), ([old], "none", None))

    def test_integrated_then_new_batch(self):
        old = issue()
        self.assertEqual(monitor.choose([old], MARK, NEW, 2, lambda _: True), ([old], "create", None))

    def test_manual_close_is_respected(self):
        old = issue(state="closed")
        self.assertEqual(monitor.choose([old], MARK, OLD, 2, lambda _: False)[1], "closed")

    def test_new_tip_after_manual_close(self):
        self.assertEqual(monitor.choose([issue(state="closed")], MARK, NEW, 2, lambda _: False)[1], "create")

    def test_other_queue_ignored(self):
        self.assertEqual(monitor.choose([issue()], "different-marker", NEW, 2, lambda _: False)[1], "create")

    def test_pull_requests_ignored(self):
        old = issue()
        old["pull_request"] = {}
        self.assertEqual(monitor.choose([old], MARK, NEW, 2, lambda _: False)[1], "create")

    def test_duplicates_fail_loudly(self):
        with self.assertRaises(RuntimeError):
            monitor.choose([issue(1), issue(2)], MARK, NEW, 2, lambda _: False)

    def test_preserve_human_notes(self):
        original = "Before\n" + monitor.splice("", "old") + "\nAfter"
        updated = monitor.splice(original, "new")
        self.assertIn("Before", updated)
        self.assertIn("After", updated)
        self.assertNotIn("old", updated)
        self.assertEqual(updated, monitor.splice(updated, "new"))

    def test_bad_ancestry_check_fails(self):
        with patch.object(monitor, "run", return_value=subprocess.CompletedProcess([], 128, "", "missing")):
            with self.assertRaises(RuntimeError):
                monitor.ancestor(OLD)

    def test_issue_write_errors_are_not_swallowed(self):
        with patch.object(subprocess, "run", side_effect=subprocess.CalledProcessError(1, ["gh"])):
            with self.assertRaises(subprocess.CalledProcessError):
                monitor.run("gh", "issue", "create")

    def test_upstream_text_is_escaped(self):
        config = {"repo": "owner/repo", "work_branch": "cpu", "upstream": "up/repo"}
        with patch.object(monitor, "git", side_effect=[OLD, "<script>bad</script>"]):
            body = monitor.body_block(config, "main", NEW, 1, "conflicts", "</pre><img>")
        self.assertNotIn("<script>", body)
        self.assertNotIn("</pre><img>", body)
        self.assertIn("&lt;script&gt;", body)

if __name__ == "__main__":
    unittest.main()
