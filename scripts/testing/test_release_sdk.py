"""Portable release SDK regression tests; no Xcode, credentials, or network."""
from contextlib import redirect_stderr, redirect_stdout
import importlib.util
import io
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts/release/validate-sdk.py"
SPEC = importlib.util.spec_from_file_location("validate_sdk", SCRIPT)
sdk = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(sdk)


class ReleaseSDKTests(unittest.TestCase):
    def app_info(self, **overrides):
        result = {"DTPlatformName": "iphoneos", "DTSDKName": "iphoneos26.0",
                  "DTPlatformVersion": "26.0", "DTXcode": "2600", "MinimumOSVersion": "17.0"}
        result.update(overrides)
        return result

    def test_accepts_minimum_toolchain(self):
        self.assertEqual(sdk.validate_versions("26.0", "26.0"), {"xcode": "26.0", "iosSDK": "26.0"})

    def test_accepts_later_numeric_versions(self):
        for xcode, ios in [("26.4.1", "26.5"), ("27.0", "27.0"), ("26", "26")]:
            with self.subTest(xcode=xcode, ios=ios):
                sdk.validate_versions(xcode, ios)

    def test_rejects_old_xcode_even_with_new_sdk(self):
        with self.assertRaisesRegex(ValueError, "Xcode is too old"):
            sdk.validate_versions("16.4", "26.0")

    def test_rejects_old_sdk_even_with_new_xcode(self):
        with self.assertRaisesRegex(ValueError, "iOS SDK is too old"):
            sdk.validate_versions("26.0", "18.5")

    def test_rejects_malformed_numeric_versions(self):
        for value in [None, True, 26, "", "26.beta", "26.0junk", "26.0\n", "-26", "26.0.0.1", "26.0;echo secret"]:
            with self.subTest(value=value), self.assertRaises(ValueError):
                sdk.version(value, "test")

    def test_current_toolchain_uses_physical_sdk_and_bounded_commands(self):
        responses = [subprocess.CompletedProcess([], 0, "Xcode 26.4.1\nBuild version 17F4\n"),
                     subprocess.CompletedProcess([], 0, "26.4\n")]
        with patch.object(sdk.subprocess, "run", side_effect=responses) as run:
            self.assertEqual(sdk.validate_current(), {"xcode": "26.4.1", "iosSDK": "26.4"})
        self.assertEqual(run.call_args_list[0].args[0], ["xcodebuild", "-version"])
        self.assertEqual(run.call_args_list[1].args[0], ["xcrun", "--sdk", "iphoneos", "--show-sdk-version"])
        for call in run.call_args_list:
            self.assertEqual(call.kwargs["timeout"], 30)
            self.assertTrue(call.kwargs["check"])
            self.assertNotIn("shell", call.kwargs)

    def test_current_toolchain_rejects_missing_or_ambiguous_version(self):
        for output in ["Command Line Tools", "Xcode 26.0\nXcode 27.0", "Xcode 26.0unexpected"]:
            with self.subTest(output=output), patch.object(sdk, "command_output", return_value=output):
                with self.assertRaisesRegex(ValueError, "unambiguous"):
                    sdk.validate_current()

    def test_command_failure_does_not_echo_arbitrary_output(self):
        error = subprocess.CalledProcessError(1, ["xcodebuild"], stderr="private-account-information")
        with patch.object(sdk.subprocess, "run", side_effect=error):
            with self.assertRaises(ValueError) as raised:
                sdk.validate_current()
        self.assertNotIn("private-account-information", str(raised.exception))

    def test_missing_tools_and_timeout_fail_closed(self):
        for error in [FileNotFoundError(), subprocess.TimeoutExpired(["xcodebuild"], 30)]:
            with self.subTest(error=error), patch.object(sdk.subprocess, "run", side_effect=error):
                with self.assertRaises(ValueError):
                    sdk.validate_current()

    def test_app_can_keep_ios_17_deployment_target(self):
        self.assertEqual(sdk.validate_app_info(self.app_info())["iosSDK"], "26.0")

    def test_app_accepts_binary_stamp_for_newer_xcode(self):
        self.assertEqual(sdk.validate_app_info(self.app_info(DTXcode="2641"))["xcodeBuildStamp"], "2641")

    def test_app_rejects_old_xcode_stamp(self):
        with self.assertRaisesRegex(ValueError, "Xcode is too old"):
            sdk.validate_app_info(self.app_info(DTXcode="1640"))

    def test_app_rejects_old_sdk_stamp(self):
        with self.assertRaisesRegex(ValueError, "iOS SDK is too old"):
            sdk.validate_app_info(self.app_info(DTSDKName="iphoneos18.5", DTPlatformVersion="18.5"))

    def test_app_rejects_simulator_and_other_platforms(self):
        for platform in ["iphonesimulator", "macosx", None, ""]:
            with self.subTest(platform=platform), self.assertRaises(ValueError):
                sdk.validate_app_info(self.app_info(DTPlatformName=platform))
        with self.assertRaises(ValueError):
            sdk.validate_app_info(self.app_info(DTSDKName="iphonesimulator26.0"))

    def test_app_rejects_missing_sdk_stamps(self):
        for key in ["DTPlatformName", "DTSDKName", "DTPlatformVersion", "DTXcode"]:
            info = self.app_info()
            del info[key]
            with self.subTest(key=key), self.assertRaises(ValueError):
                sdk.validate_app_info(info)

    def test_app_rejects_invalid_xcode_stamps(self):
        for value in [2600, True, "26", "26.0", "2600beta", "02600", ""]:
            with self.subTest(value=value), self.assertRaises(ValueError):
                sdk.validate_app_info(self.app_info(DTXcode=value))

    def test_app_rejects_disagreeing_sdk_stamps(self):
        with self.assertRaisesRegex(ValueError, "disagree"):
            sdk.validate_app_info(self.app_info(DTPlatformVersion="26.1"))

    def test_app_accepts_equivalent_zero_patch_versions(self):
        sdk.validate_app_info(self.app_info(DTPlatformVersion="26.0.0"))

    def test_app_rejects_non_dictionary_plist(self):
        for value in [[], None, "iphoneos26.0"]:
            with self.subTest(value=value), self.assertRaises(ValueError):
                sdk.validate_app_info(value)

    def test_cli_reads_xml_and_binary_without_launching_tools(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(sdk.subprocess, "run") as run:
            for fmt in [plistlib.FMT_XML, plistlib.FMT_BINARY]:
                path = Path(directory) / "Info.plist"
                path.write_bytes(plistlib.dumps(self.app_info(), fmt=fmt))
                with redirect_stdout(io.StringIO()):
                    self.assertEqual(sdk.main(["--app-info", str(path)]), 0)
            run.assert_not_called()

    def test_cli_returns_nonzero_for_corrupt_or_missing_plist(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "Info.plist"
            for content in [None, b"not a plist", b'<?xml version="1.0"?><plist><dict>']:
                if content is not None:
                    path.write_bytes(content)
                output = io.StringIO()
                with redirect_stderr(output):
                    self.assertEqual(sdk.main(["--app-info", str(path)]), 1)
                self.assertIn("Release SDK check failed", output.getvalue())
                self.assertIn("April 28, 2026", output.getvalue())

    def test_archive_rejects_old_sdk_before_outputs_or_signing(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for tool, output in [("xcodebuild", "Xcode 16.4\nBuild version 16F6"), ("xcrun", "26.0")]:
                path = root / tool
                path.write_text("#!/bin/sh\nprintf '%s\\n' '" + output + "'\n")
                path.chmod(0o700)
            archive = root / "must-not-exist" / "App.xcarchive"
            derived = root / "must-not-exist" / "DerivedData"
            env = dict(os.environ, PATH=str(root) + os.pathsep + os.environ.get("PATH", ""),
                       FILMY_ARCHIVE_PATH=str(archive), FILMY_DERIVED_DATA_PATH=str(derived))
            result = subprocess.run(["bash", str(ROOT / "scripts/release/archive-device.sh")],
                                    env=env, capture_output=True, text=True, timeout=15)
            self.assertEqual(result.returncode, 1, result.stderr)
            self.assertIn("Xcode is too old", result.stderr)
            self.assertFalse(archive.parent.exists())
            self.assertNotIn("XcodeGen", result.stderr)

    def test_archive_validation_checks_built_metadata_before_provisioning(self):
        text = (ROOT / "scripts/release/validate-archive.sh").read_text()
        call = 'python3 "${script_dir}/validate-sdk.py" --app-info "${info_plist}"'
        self.assertIn(call, text)
        self.assertLess(text.index(call), text.index("security cms"))

    def test_archive_help_is_available_without_xcode(self):
        result = subprocess.run(["bash", str(ROOT / "scripts/release/archive-device.sh"), "--help"],
                                capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Xcode 26+", result.stdout)

    def test_cli_requires_exactly_one_mode(self):
        for args in [[], ["--current", "--app-info", "Info.plist"]]:
            with self.subTest(args=args), redirect_stderr(io.StringIO()), self.assertRaises(SystemExit) as raised:
                sdk.main(args)
            self.assertEqual(raised.exception.code, 2)


if __name__ == "__main__":
    unittest.main()
