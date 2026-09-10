"""Portable App Review contract regressions. No network, Xcode, or credentials."""
from contextlib import redirect_stderr, redirect_stdout
import copy
import importlib.util
import io
from pathlib import Path
import plistlib
import struct
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("app_review", ROOT / "scripts/release/validate-app-review.py")
review = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(review)


class AppReviewPreflightTests(unittest.TestCase):
    def setUp(self):
        self.info, self.manifest, self.urls = review.validate_source(ROOT)
        self.metadata = (ROOT / "docs/app-store/metadata-en-US.md").read_text()

    def test_repository_matches_reviewed_contract(self):
        review.validate_source(ROOT)

    def test_tracking_requires_boolean_false(self):
        for value in (True, 0, "false", None):
            with self.subTest(value=value), self.assertRaisesRegex(ValueError, "Tracking"):
                review.validate_manifest(dict(self.manifest, NSPrivacyTracking=value))

    def test_missing_or_new_manifest_fields_fail_closed(self):
        for key in self.manifest:
            data = dict(self.manifest)
            del data[key]
            with self.subTest(key=key), self.assertRaises(ValueError):
                review.validate_manifest(data)
        with self.assertRaises(ValueError):
            review.validate_manifest(dict(self.manifest, unexpected=True))

    def test_collected_data_and_tracking_domains_require_review(self):
        for key in ("NSPrivacyTrackingDomains", "NSPrivacyCollectedDataTypes"):
            for value in (None, {}, "", ["tracking.example"]):
                with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                    review.validate_manifest(dict(self.manifest, **{key: value}))

    def test_every_required_reason_is_required(self):
        for index in range(3):
            data = copy.deepcopy(self.manifest)
            del data["NSPrivacyAccessedAPITypes"][index]
            with self.subTest(index=index), self.assertRaisesRegex(ValueError, "Missing required-reason"):
                review.validate_manifest(data)

    def test_duplicate_categories_and_codes_are_rejected(self):
        data = copy.deepcopy(self.manifest)
        data["NSPrivacyAccessedAPITypes"].append(data["NSPrivacyAccessedAPITypes"][0])
        with self.assertRaisesRegex(ValueError, "Duplicate"):
            review.validate_manifest(data)
        data = copy.deepcopy(self.manifest)
        reasons = data["NSPrivacyAccessedAPITypes"][0]["NSPrivacyAccessedAPITypeReasons"]
        reasons.append(reasons[0])
        with self.assertRaises(ValueError):
            review.validate_manifest(data)

    def test_reason_codes_cannot_be_arbitrary_or_wrong_types(self):
        for value in ([], ["INVALID.1"], "CA92.1", [None], [1]):
            data = copy.deepcopy(self.manifest)
            data["NSPrivacyAccessedAPITypes"][0]["NSPrivacyAccessedAPITypeReasons"] = value
            with self.subTest(value=value), self.assertRaises(ValueError):
                review.validate_manifest(data)

    def test_duplicate_xml_keys_are_rejected_before_plistlib_overwrites_them(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "PrivacyInfo.xcprivacy"
            path.write_text('<plist version="1.0"><dict><key>tracking</key><true/><key>tracking</key><false/></dict></plist>')
            with self.assertRaisesRegex(ValueError, "Duplicate plist key"):
                review.load_plist(path)

    def test_binary_plists_and_xml_plists_are_supported(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "Info.plist"
            for format in (plistlib.FMT_XML, plistlib.FMT_BINARY):
                path.write_bytes(plistlib.dumps(self.info, fmt=format))
                self.assertEqual(review.load_plist(path), self.info)

    def test_new_permissions_or_capabilities_require_a_review(self):
        for key, value in (("NSMicrophoneUsageDescription", "Record an audio track"),
                           ("NSUserTrackingUsageDescription", "Personalize advertisements"),
                           ("NSAppTransportSecurity", {"NSAllowsArbitraryLoads": True}),
                           ("UIBackgroundModes", ["audio"])):
            with self.subTest(key=key), self.assertRaises(ValueError):
                review.validate_info(dict(self.info, **{key: value}))

    def test_purpose_copy_matches_xcodegen_spec(self):
        spec = (ROOT / "project.yml").read_text()
        key = "NSCameraUsageDescription"
        with self.assertRaisesRegex(ValueError, "disagree"):
            review.validate_info(self.info, spec.replace(self.info[key], "Different camera purpose text"))

    def test_permission_copy_is_meaningful_and_not_a_build_variable(self):
        for text in ("", "Camera", "$(CAMERA_PURPOSE_DESCRIPTION)", None):
            with self.subTest(text=text), self.assertRaises(ValueError):
                review.validate_info(dict(self.info, NSCameraUsageDescription=text))

    def test_keyword_limit_counts_utf8_bytes_not_just_characters(self):
        existing = review.section(self.metadata, "Keywords")
        replacement = "`" + "é" * 51 + "`"
        with self.assertRaisesRegex(ValueError, "100 UTF-8 bytes"):
            review.validate_metadata(self.metadata.replace(existing, replacement))

    def test_description_and_review_notes_limits_are_enforced(self):
        for heading, replacement in (("Description", "x" * 4001), ("App Review notes", "é" * 2001)):
            text = self.metadata.replace(review.section(self.metadata, heading), replacement)
            with self.subTest(heading=heading), self.assertRaisesRegex(ValueError, "4000"):
                review.validate_metadata(text)

    def test_ambiguous_metadata_fields_are_rejected(self):
        with self.assertRaisesRegex(ValueError, "ambiguous"):
            review.validate_metadata(self.metadata + "\n- **App name:** Different app\n")

    def test_urls_cannot_downgrade_redirect_or_embed_credentials(self):
        for url in ("http://dheeraj5612.github.io/support.html", "https://example.org/privacy",
                    "https://secret@github.com/owner/repo", "https://github.com/?secret=value",
                    "https://localhost/", "https://github.com:8443/", "https://github.com/#secret"):
            with self.subTest(url=url), self.assertRaises(ValueError):
                review.validate_url(url)
        with self.assertRaises(ValueError):
            review.ReviewedHTTPSRedirectHandler().redirect_request(None, None, 302, "Found", {}, "http://github.com/")

    def make_app(self, root, **overrides):
        app = root / "FilmyCamera.app"
        app.mkdir()
        info = dict(self.info, CFBundleIdentifier="com.dheeraj.filmycamera", CFBundleExecutable="FilmyCamera",
                    CFBundleShortVersionString="1.0.0", CFBundleVersion="13", DTPlatformName="iphoneos",
                    DTSDKName="iphoneos26.2", DTPlatformVersion="26.2", DTXcode="2630")
        info.update(overrides)
        (app / "Info.plist").write_bytes(plistlib.dumps(info, fmt=plistlib.FMT_BINARY))
        (app / "PrivacyInfo.xcprivacy").write_bytes(plistlib.dumps(self.manifest))
        # Only a fixture for the metadata and marker scanner, not a real build.
        (app / "FilmyCamera").write_bytes(b"\xcf\xfa\xed\xfe" + b"release-fixture")
        return app

    def test_built_artifact_checks_sdk_and_manifest(self):
        with tempfile.TemporaryDirectory() as directory:
            app = self.make_app(Path(directory))
            self.assertEqual(review.validate_built_app(app, self.info, self.manifest, ROOT)["iosSDK"], "26.2")

    def test_old_sdk_is_not_accepted_as_distribution_ready(self):
        with tempfile.TemporaryDirectory() as directory:
            app = self.make_app(Path(directory), DTSDKName="iphoneos18.5", DTPlatformVersion="18.5", DTXcode="1640")
            with self.assertRaisesRegex(ValueError, "too old"):
                review.validate_built_app(app, self.info, self.manifest, ROOT)

    def test_each_debug_launch_marker_is_rejected_from_binary(self):
        with tempfile.TemporaryDirectory() as directory:
            app = self.make_app(Path(directory))
            for marker in review.TEST_MARKERS:
                (app / "FilmyCamera").write_bytes(b"\xcf\xfa\xed\xfe" + marker)
                with self.subTest(marker=marker), self.assertRaisesRegex(ValueError, "Test-only"):
                    review.validate_built_app(app, self.info, self.manifest, ROOT)

    def test_missing_or_stale_bundled_manifest_fails(self):
        with tempfile.TemporaryDirectory() as directory:
            app = self.make_app(Path(directory))
            (app / "PrivacyInfo.xcprivacy").unlink()
            with self.assertRaises(OSError):
                review.validate_built_app(app, self.info, self.manifest, ROOT)
            stale = copy.deepcopy(self.manifest)
            stale["NSPrivacyAccessedAPITypes"].pop()
            (app / "PrivacyInfo.xcprivacy").write_bytes(plistlib.dumps(stale))
            with self.assertRaises(ValueError):
                review.validate_built_app(app, self.info, self.manifest, ROOT)

    def test_unresolved_versions_and_unsafe_executable_paths_fail(self):
        for key, value in (("CFBundleVersion", "$(CURRENT_PROJECT_VERSION)"), ("CFBundleExecutable", "../outside"),
                           ("CFBundleIdentifier", "com.example.debug")):
            with tempfile.TemporaryDirectory() as directory:
                app = self.make_app(Path(directory), **{key: value})
                with self.subTest(key=key), self.assertRaises(ValueError):
                    review.validate_built_app(app, self.info, self.manifest, ROOT)

    def test_new_framework_requires_explicit_privacy_review(self):
        with tempfile.TemporaryDirectory() as directory:
            app = self.make_app(Path(directory))
            (app / "Frameworks/Telemetry.framework").mkdir(parents=True)
            with self.assertRaisesRegex(ValueError, "framework"):
                review.validate_built_app(app, self.info, self.manifest, ROOT)

    def test_default_preflight_performs_no_network_io(self):
        with patch.object(review, "check_live_urls") as live, redirect_stdout(io.StringIO()):
            self.assertEqual(review.main(["--root", str(ROOT)]), 0)
            live.assert_not_called()

    def test_cli_fails_cleanly_for_missing_or_malformed_plists(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for content in (None, b"not a plist"):
                if content is not None:
                    (root / "FilmyCamera").mkdir()
                    (root / "FilmyCamera/Info.plist").write_bytes(content)
                with redirect_stderr(io.StringIO()) as output:
                    self.assertEqual(review.main(["--root", str(root)]), 1)
                self.assertIn("preflight failed", output.getvalue())

    def test_live_page_checks_use_bounded_requests_and_actual_app_content(self):
        class Response(io.BytesIO):
            status = 200

            def geturl(self):
                return "https://dheeraj5612.github.io/filmycam-legal/support.html"

        from email.message import Message
        response = Response(b'<html>Filmy support <a href="mailto:support@example.com">Contact</a></html>')
        response.headers = Message()
        response.headers["Content-Type"] = "text/html"
        with patch.object(review, "build_opener") as build:
            build.return_value.open.return_value = response
            report = review.check_live_urls({"Support URL": self.urls["Support URL"]})
        self.assertEqual(report["Support URL"]["httpStatus"], 200)
        self.assertEqual(build.return_value.open.call_args.kwargs["timeout"], 15)

    def test_live_page_failure_cannot_be_reported_as_success(self):
        with patch.object(review, "build_opener") as build:
            build.return_value.open.side_effect = TimeoutError("untrusted server detail")
            with self.assertRaisesRegex(ValueError, "could not be verified") as raised:
                review.check_live_urls(self.urls)
        self.assertNotIn("untrusted server detail", str(raised.exception))


if __name__ == "__main__":
    unittest.main()
