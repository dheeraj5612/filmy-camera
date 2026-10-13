import importlib.util
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[2]


def load_script():
    spec = importlib.util.spec_from_file_location("validate_ui_polish", ROOT / "scripts/validate-ui-polish.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class UIPolishSkipTests(unittest.TestCase):
    def run_main(self, argv):
        module = load_script()
        with mock.patch.object(module, "swiftc_command", return_value=("swiftc", [])), \
                mock.patch.object(module.subprocess, "run"), \
                mock.patch.object(module, "host_xctest_available", return_value=False), \
                mock.patch.object(module.sys, "argv", ["validate-ui-polish.py", *argv]):
            try:
                module.main()
            except SystemExit as exit_info:
                return exit_info.code
        return 0

    def test_unavailable_host_xctest_exits_77_without_allow_skip(self):
        self.assertEqual(self.run_main([]), 77)

    def test_allow_skip_accepts_unavailable_host_xctest(self):
        self.assertIn(self.run_main(["--allow-skip"]), (0, None))


if __name__ == "__main__":
    unittest.main()
