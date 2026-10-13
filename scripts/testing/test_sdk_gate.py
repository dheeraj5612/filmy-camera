"""Portable SDK gate tests; no Xcode, otool, credentials, or network."""
import importlib.util
import io
from contextlib import redirect_stdout
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts/monetization/sdk_gate.py"
SPEC = importlib.util.spec_from_file_location("sdk_gate", SCRIPT)
gate = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(gate)


def run_gate(*args):
    return subprocess.run([sys.executable, str(SCRIPT), *args], capture_output=True, text=True, timeout=60)


class SDKGateTests(unittest.TestCase):
    def test_plist_split_is_current(self):
        result = run_gate("plist", "--check")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("plist: PASS", result.stdout)

    def test_sdk_imports_stay_behind_the_condition(self):
        result = run_gate("source")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("source: PASS", result.stdout)

    def test_free_plist_holds_none_of_the_monetized_keys(self):
        free = plistlib.loads(gate.FREE_PLIST.read_bytes())
        for key in gate.MONETIZED_EXTRA:
            self.assertNotIn(key, free)

    def make_app(self, root, extra=None):
        app = root / "FilmyCamera.app"
        app.mkdir()
        info = {"CFBundleExecutable": "FilmyCamera", "FilmyMonetizationEnabled": "NO", "FilmyAdsEnabled": "NO"}
        (app / "Info.plist").write_bytes(plistlib.dumps(info))
        (app / "FilmyCamera").write_bytes(b"plain executable bytes")
        if extra:
            extra(app)
        return app

    def scan(self, app, expect="free", otool=""):
        fake = subprocess.CompletedProcess([], 0, stdout=otool, stderr="")
        out = io.StringIO()
        with patch.object(gate.subprocess, "run", return_value=fake), redirect_stdout(out):
            code = gate.check_app(app, expect)
        return code, out.getvalue()

    def test_clean_free_app_passes(self):
        with tempfile.TemporaryDirectory() as tmp:
            code, out = self.scan(self.make_app(Path(tmp)))
        self.assertEqual(code, 0, out)
        self.assertIn("sdk-free: PASS", out)

    def test_free_app_with_resource_bundle_fails(self):
        with tempfile.TemporaryDirectory() as tmp:
            code, out = self.scan(self.make_app(Path(tmp), lambda app: (app / "Foo_Bar.bundle").mkdir()))
        self.assertEqual(code, 1)
        self.assertIn("sdk-free: FAIL", out)
        self.assertIn("resource bundle Foo_Bar.bundle", out)

    def test_free_app_with_sdk_plist_key_fails(self):
        def add_key(app):
            info = plistlib.loads((app / "Info.plist").read_bytes())
            info["GADApplicationIdentifier"] = "ca-app-pub-1111111111111111~2222222222"
            (app / "Info.plist").write_bytes(plistlib.dumps(info))
        with tempfile.TemporaryDirectory() as tmp:
            code, out = self.scan(self.make_app(Path(tmp), add_key))
        self.assertEqual(code, 1)
        self.assertIn("Info.plist key GADApplicationIdentifier", out)

    def test_free_app_with_sdk_strings_in_executable_fails(self):
        token = "GADMobileAds"
        def add_token(app):
            (app / "FilmyCamera").write_bytes(b"x" + token.encode() + b"y")
        with tempfile.TemporaryDirectory() as tmp:
            code, out = self.scan(self.make_app(Path(tmp), add_token))
        self.assertEqual(code, 1)
        self.assertIn("executable string", out)


    def assert_free_fails(self, extra, needle):
        with tempfile.TemporaryDirectory() as tmp:
            code, out = self.scan(self.make_app(Path(tmp), extra))
        self.assertEqual(code, 1, out)
        self.assertIn(needle, out)

    def test_free_app_with_embedded_framework_fails(self):
        def add(app):
            framework = app / "Frameworks" / "FirebaseCore.framework"
            framework.mkdir(parents=True)
            (framework / "FirebaseCore").write_bytes(b"FIRApp GIDSignIn GADMobileAds")
        self.assert_free_fails(add, "embedded Frameworks/FirebaseCore.framework")

    def test_free_app_with_unknown_framework_fails(self):
        self.assert_free_fails(lambda app: (app / "Frameworks" / "Other.framework").mkdir(parents=True),
                               "embedded Frameworks/Other.framework")

    def test_free_app_with_app_extension_fails(self):
        self.assert_free_fails(lambda app: (app / "PlugIns" / "X.appex").mkdir(parents=True),
                               "embedded PlugIns/X.appex")

    def test_free_app_with_loose_dylib_fails(self):
        self.assert_free_fails(lambda app: (app / "libfoo.dylib").write_bytes(b"GADMobileAds"),
                               "embedded libfoo.dylib")

    def test_free_app_allows_debug_and_preview_dylibs(self):
        def add(app):
            (app / "FilmyCamera.debug.dylib").write_bytes(b"plain")
            (app / "__preview.dylib").write_bytes(b"plain")
        with tempfile.TemporaryDirectory() as tmp:
            code, out = self.scan(self.make_app(Path(tmp), add))
        self.assertEqual(code, 0, out)

    def test_free_app_with_nested_privacy_manifest_fails(self):
        def add(app):
            (app / "Sub").mkdir()
            (app / "Sub" / "PrivacyInfo.xcprivacy").write_bytes(b"x")
        self.assert_free_fails(add, "privacy manifest Sub/PrivacyInfo.xcprivacy")

    def test_free_app_with_google_service_plist_fails(self):
        self.assert_free_fails(lambda app: (app / "GoogleService-Info.plist").write_bytes(b"x"),
                               "file GoogleService-Info.plist")

    def test_free_app_with_monetization_enabled_fails(self):
        def enable(app):
            info = plistlib.loads((app / "Info.plist").read_bytes())
            info["FilmyMonetizationEnabled"] = "YES"
            (app / "Info.plist").write_bytes(plistlib.dumps(info))
        self.assert_free_fails(enable, "Info.plist key FilmyMonetizationEnabled is not exactly NO")

    def test_free_app_with_missing_ads_flag_fails(self):
        def drop(app):
            info = plistlib.loads((app / "Info.plist").read_bytes())
            del info["FilmyAdsEnabled"]
            (app / "Info.plist").write_bytes(plistlib.dumps(info))
        self.assert_free_fails(drop, "Info.plist key FilmyAdsEnabled is not exactly NO")

    def test_free_app_with_token_in_debug_dylib_fails(self):
        self.assert_free_fails(lambda app: (app / "FilmyCamera.debug.dylib").write_bytes(b"..GIDSignIn.."),
                               "executable string GIDSignIn")

    def test_free_app_with_load_classes_section_fails(self):
        with tempfile.TemporaryDirectory() as tmp:
            code, out = self.scan(self.make_app(Path(tmp)), otool="Section sectname __objc_nlclslist")
        self.assertEqual(code, 1, out)
        self.assertIn("__objc_nlclslist", out)

    def monetized_app(self, root, drop_family=None, drop_key=None):
        def extra(app):
            info = plistlib.loads((app / "Info.plist").read_bytes())
            info["FilmyMonetizationEnabled"] = "YES"
            for key in gate.SDK_PLIST_KEYS:
                if key != drop_key:
                    info[key] = "x"
            (app / "Info.plist").write_bytes(plistlib.dumps(info))
            tokens = [values[0] for name, values in gate.SDK_FAMILIES.items() if name != drop_family]
            (app / "FilmyCamera").write_bytes(b" ".join(tokens))
        return self.make_app(root, extra)

    def test_monetized_app_passes(self):
        with tempfile.TemporaryDirectory() as tmp:
            code, out = self.scan(self.monetized_app(Path(tmp)), "monetized")
        self.assertEqual(code, 0, out)
        self.assertIn("sdk-linked: PASS", out)

    def test_monetized_app_missing_a_family_fails(self):
        for family in gate.MONETIZED_FAMILIES:
            with self.subTest(family=family), tempfile.TemporaryDirectory() as tmp:
                code, out = self.scan(self.monetized_app(Path(tmp), drop_family=family), "monetized")
            self.assertEqual(code, 1, out)
            self.assertIn("executable strings of " + family, out)

    def test_monetized_app_missing_a_plist_key_fails(self):
        for key in gate.SDK_PLIST_KEYS:
            with self.subTest(key=key), tempfile.TemporaryDirectory() as tmp:
                code, out = self.scan(self.monetized_app(Path(tmp), drop_key=key), "monetized")
            self.assertEqual(code, 1, out)
            self.assertIn("Info.plist key " + key, out)

    def test_auto_follows_the_built_plist(self):
        with tempfile.TemporaryDirectory() as tmp:
            code, out = self.scan(self.monetized_app(Path(tmp)), "auto")
        self.assertEqual(code, 0, out)
        self.assertIn("sdk-linked: PASS", out)
        with tempfile.TemporaryDirectory() as tmp:
            code, out = self.scan(self.make_app(Path(tmp)), "auto")
        self.assertEqual(code, 0, out)
        self.assertIn("sdk-free: PASS", out)
        with tempfile.TemporaryDirectory() as tmp:
            code, out = self.scan(self.make_app(Path(tmp), lambda app: (app / "libfoo.dylib").write_bytes(b"x")), "auto")
        self.assertEqual(code, 1, out)

    def source_problems_for(self, text):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "FilmyCamera").mkdir()
            (root / "FilmyCamera" / "A.swift").write_text(text, encoding="utf-8")
            with patch.object(gate, "ROOT", root):
                return gate.source_problems()

    def test_source_import_inside_condition_passes(self):
        self.assertEqual(self.source_problems_for("#if FILMY_MONETIZATION_SDKS\nimport GoogleMobileAds\n#endif\n"), [])

    def test_source_import_outside_condition_fails(self):
        problems = self.source_problems_for("import SwiftUI\nimport FirebaseCore\n")
        self.assertEqual(len(problems), 1, problems)
        self.assertIn("A.swift:2", problems[0])

    def test_source_import_in_else_branch_fails(self):
        problems = self.source_problems_for("#if FILMY_MONETIZATION_SDKS\n#else\nimport GoogleSignIn\n#endif\n")
        self.assertEqual(len(problems), 1, problems)

    def test_source_import_after_endif_fails(self):
        problems = self.source_problems_for("#if FILMY_MONETIZATION_SDKS\n#endif\n@preconcurrency import UserMessagingPlatform\n")
        self.assertEqual(len(problems), 1, problems)

    def test_source_import_under_other_condition_fails(self):
        problems = self.source_problems_for("#if DEBUG\nimport GoogleMobileAds\n#endif\n")
        self.assertEqual(len(problems), 1, problems)

    def plist_problems_for(self, free_extra=None, monetized="current", write=False):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "Config").mkdir()
            (root / "FilmyCamera").mkdir()
            free = {"CFBundleName": "Filmy"}
            free.update(free_extra or {})
            free_path = root / "FilmyCamera" / "Info.plist"
            monetized_path = root / "Config" / "Info.Monetized.plist"
            free_path.write_bytes(plistlib.dumps(free))
            with patch.object(gate, "ROOT", root), patch.object(gate, "FREE_PLIST", free_path), \
                    patch.object(gate, "MONETIZED_PLIST", monetized_path):
                if monetized == "current":
                    monetized_path.write_bytes(plistlib.dumps(gate.expected_monetized_plist()))
                elif monetized == "drifted":
                    drifted = gate.expected_monetized_plist()
                    drifted["CFBundleName"] = "Other"
                    monetized_path.write_bytes(plistlib.dumps(drifted))
                if write:
                    with patch.object(sys, "argv", ["sdk_gate.py", "plist", "--write"]), redirect_stdout(io.StringIO()):
                        code = gate.main()
                    self.assertEqual(code, 0)
                return gate.plist_problems()

    def test_plist_current_split_passes(self):
        self.assertEqual(self.plist_problems_for(), [])

    def test_plist_drifted_monetized_fails(self):
        problems = self.plist_problems_for(monetized="drifted")
        self.assertEqual(len(problems), 1, problems)
        self.assertIn("differs", problems[0])

    def test_plist_missing_monetized_fails(self):
        problems = self.plist_problems_for(monetized="missing")
        self.assertEqual(len(problems), 1, problems)
        self.assertIn("is missing", problems[0])

    def test_plist_write_repairs_a_drifted_file(self):
        self.assertEqual(self.plist_problems_for(monetized="drifted", write=True), [])
        self.assertEqual(self.plist_problems_for(monetized="missing", write=True), [])

    def test_free_plist_holding_a_monetized_key_fails(self):
        problems = self.plist_problems_for(free_extra={"GADApplicationIdentifier": "x"})
        self.assertTrue(any("must not hold GADApplicationIdentifier" in p for p in problems), problems)


if __name__ == "__main__":
    unittest.main()
