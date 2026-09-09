"""Exercise the release plist emitter without signing or contacting Apple."""
from pathlib import Path
import plistlib
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class ReleaseExportOptionsTests(unittest.TestCase):
    def test_export_preserves_validated_archive_version_and_build(self):
        script = (ROOT / "scripts/release/prepare-upload.sh").read_text()
        # Execute only the production emitter. Sourcing the complete command
        # would run signing preflight and its export/upload dispatch.
        emitter = re.search(r"^write_export_options\(\) \{\n.*?^\}", script, re.M | re.S)
        self.assertIsNotNone(emitter, "The production export-options emitter must exist")
        command = 'team_id="$1"\n' + emitter.group() + '\nwrite_export_options "$2"\n'
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "Export Options.plist"
            subprocess.run(
                ["bash", "-eu", "-c", command, "export-options-test", "TEST123456", str(output)],
                check=True, capture_output=True, text=True, timeout=10,
            )
            with output.open("rb") as handle:
                options = plistlib.load(handle)

        self.assertIs(options.get("manageAppVersionAndBuildNumber"), False,
                      "Xcode must preserve the version and build validated in the archive")
        self.assertEqual(options["method"], "app-store-connect")
        self.assertEqual(options["signingStyle"], "automatic")
        self.assertEqual(options["teamID"], "TEST123456")
        self.assertIs(options["uploadSymbols"], True)


if __name__ == "__main__":
    unittest.main()
