"""Guard workflow scheduling so documentation cannot erase app-build evidence."""
from pathlib import Path
import re
import unittest


class LaunchConcurrencyTests(unittest.TestCase):
    def setUp(self):
        root = Path(__file__).resolve().parents[2]
        workflow = (root / ".github/workflows/ios-build.yml").read_text()
        match = re.search(r"^concurrency:\n((?:[ \t]+.*\n|\n)+)", workflow, re.MULTILINE)
        self.assertIsNotNone(match, "The workflow must declare an explicit concurrency policy")
        self.block = match.group(1)

    def test_non_pr_runs_have_unique_groups_including_pending_runs(self):
        # cancel-in-progress: false alone is insufficient: a new run can
        # replace a pending run in the same group before it ever starts.
        self.assertIn("github.event.pull_request.number || github.run_id", self.block)
        self.assertNotIn("|| github.ref", self.block)

    def test_only_superseded_pr_runs_are_cancelled(self):
        self.assertRegex(
            self.block,
            r"cancel-in-progress:\s*\$\{\{\s*github.event_name == 'pull_request'\s*\}\}",
        )

    def test_all_pr_revisions_share_the_same_group(self):
        self.assertRegex(
            self.block,
            r"group:\s*ios-build-\$\{\{\s*github.event.pull_request.number \|\| github.run_id\s*\}\}",
        )


if __name__ == "__main__":
    unittest.main()
