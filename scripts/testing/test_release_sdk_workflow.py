"""Keep modern distribution compilation separate from signed release actions."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class ReleaseSDKWorkflowTests(unittest.TestCase):
    def setUp(self):
        text = (ROOT / ".github/workflows/release-sdk-build.yml").read_text()
        self.assertEqual(text.count("\n  release-sdk-build:\n"), 1)
        self.workflow = text
        self.job = text.split("\n  release-sdk-build:\n", 1)[1]

    def test_distribution_lane_has_explicit_supported_xcode(self):
        self.assertIn("runs-on: macos-15", self.job)
        self.assertIn("DEVELOPER_DIR: /Applications/Xcode_26.3.app/Contents/Developer", self.job)
        self.assertIn("grep -Fxq 'Xcode 26.3'", self.job)
        self.assertIn("timeout-minutes: 15", self.job)

    def test_distribution_lane_checks_selected_and_built_sdk(self):
        self.assertIn("validate-sdk.py --current", self.job)
        self.assertIn("validate-sdk.py --app-info", self.job)
        self.assertIn("Release-iphoneos/FilmyCamera.app/Info.plist", self.job)

    def test_distribution_lane_compiles_release_and_device_tests_without_signing(self):
        self.assertIn("-configuration Release -destination 'generic/platform=iOS'", self.job)
        self.assertIn("CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build", self.job)
        self.assertIn("scripts/testing/run.py device-build", self.job)
        self.assertNotIn("prepare-upload.sh", self.job)
        self.assertNotIn("archive-device.sh", self.job)
        self.assertNotIn("-allowProvisioningUpdates", self.job)
        self.assertNotIn("continue-on-error", self.job)

    def test_distribution_lane_is_checked_for_app_and_release_changes(self):
        self.assertIn("pull_request: {}", self.workflow)
        self.assertIn('"FilmyCamera/**"', self.workflow)
        self.assertIn('"scripts/release/**"', self.workflow)
        self.assertIn("github.event.pull_request.number || github.run_id", self.workflow)
        self.assertIn("cancel-in-progress: ${{ github.event_name == 'pull_request' }}", self.workflow)
        self.assertIn("persist-credentials: false", self.job)

    def test_distribution_lane_retains_evidence_even_when_compilation_fails(self):
        self.assertIn("git rev-parse HEAD", self.job)
        self.assertIn("source-sha.txt", self.job)
        self.assertIn("release-build.log", self.job)
        self.assertIn("if: always()", self.job)
        self.assertIn("name: filmycamera-release-sdk-${{ github.run_id }}", self.job)
        self.assertIn("set -euo pipefail", self.job)


if __name__ == "__main__":
    unittest.main()
