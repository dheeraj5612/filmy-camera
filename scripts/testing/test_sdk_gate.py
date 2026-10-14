"""Portable SDK gate tests; no Xcode, otool, credentials, or network."""
import importlib.util
import io
import os
from contextlib import redirect_stdout
from pathlib import Path
import plistlib
import shutil
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

    class OtoolFake:
        """Stands in for subprocess.run: picks stdout by cmd[1] ("-l" sections, "-L" links), optionally by image name."""

        def __init__(self, sections="", links=None, by_image=None):
            self.sections = sections
            self.links = sections if links is None else links
            self.by_image = by_image or {}
            self.calls = []

        def __call__(self, cmd, **kwargs):
            image = Path(cmd[2])
            self.calls.append((cmd[1], image))
            default = self.sections if cmd[1] == "-l" else self.links
            return subprocess.CompletedProcess(cmd, 0, stdout=self.by_image.get((cmd[1], image.name), default), stderr="")

    def scan(self, app, expect="free", otool="", links=None, by_image=None, fake=None):
        fake = fake or self.OtoolFake(otool, links, by_image)
        out = io.StringIO()
        with patch.object(gate.subprocess, "run", fake), redirect_stdout(out):
            code = gate.check_app(app, expect)
        self.fake = fake
        return code, out.getvalue()

    def run_main(self, app, *flags):
        out = io.StringIO()
        with patch.object(sys, "argv", ["sdk_gate.py", "app", *flags, str(app)]), \
                patch.object(gate.subprocess, "run", self.OtoolFake()), redirect_stdout(out):
            code = gate.main()
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
        for key in gate.FREE_ABSENT_KEYS:
            def add_key(app):
                info = plistlib.loads((app / "Info.plist").read_bytes())
                info[key] = "x"
                (app / "Info.plist").write_bytes(plistlib.dumps(info))
            with self.subTest(key=key), tempfile.TemporaryDirectory() as tmp:
                code, out = self.scan(self.make_app(Path(tmp), add_key))
                self.assertEqual(code, 1)
                self.assertIn(f"Info.plist key {key}", out)

    def test_free_app_with_sdk_strings_in_executable_fails(self):
        for family, tokens in gate.SDK_FAMILIES.items():
            for token in tokens:
                def add_token(app):
                    (app / "FilmyCamera").write_bytes(b"x" + token + b"y")
                with self.subTest(family=family, token=token), tempfile.TemporaryDirectory() as tmp:
                    code, out = self.scan(self.make_app(Path(tmp), add_token))
                    self.assertEqual(code, 1)
                    self.assertIn(f"executable string {token.decode()}", out)

    def test_free_app_with_nested_resource_bundle_fails(self):
        self.assert_free_fails(lambda app: (app / "Sub" / "Deep_Res.bundle").mkdir(parents=True),
                               "resource bundle Deep_Res.bundle")

    def test_nested_debug_and_preview_dylibs_fail(self):
        for name in ("FilmyCamera.debug.dylib", "__preview.dylib"):
            with self.subTest(name=name):
                self.assert_free_fails(lambda app: (app / "Sub").mkdir() or (app / "Sub" / name).write_bytes(b"x"),
                                       f"embedded Sub/{name}")

    def test_token_only_in_preview_dylib_fails_with_both_dylibs_present(self):
        def add(app):
            (app / "FilmyCamera.debug.dylib").write_bytes(b"plain")
            (app / "__preview.dylib").write_bytes(b"..GADMobileAds..")
        self.assert_free_fails(add, "executable string GADMobileAds")

    def test_load_classes_section_only_in_allowed_dylib_fails(self):
        def add(app):
            (app / "FilmyCamera.debug.dylib").write_bytes(b"plain")
            (app / "__preview.dylib").write_bytes(b"plain")
        for name in ("FilmyCamera.debug.dylib", "__preview.dylib"):
            with self.subTest(name=name), tempfile.TemporaryDirectory() as tmp:
                code, out = self.scan(self.make_app(Path(tmp), add),
                                      by_image={("-l", name): "Section sectname __objc_nlclslist"})
                self.assertEqual(code, 1, out)
                self.assertIn("__objc_nlclslist", out)

    def test_lookalike_preview_dylib_name_is_embedded(self):
        self.assert_free_fails(lambda app: (app / "libfoo__preview.dylib").write_bytes(b"x"),
                               "embedded libfoo__preview.dylib")

    def test_non_string_bundle_executable_fails_closed(self):
        def bad(app):
            (app / "Info.plist").write_bytes(plistlib.dumps({"CFBundleExecutable": 7}))
        with tempfile.TemporaryDirectory() as tmp:
            code, out = self.scan(self.make_app(Path(tmp), bad))
        self.assertEqual(code, 1, out)
        self.assertIn("sdk-gate: FAIL cannot read", out)

    @unittest.skipIf(os.name == "nt", "needs a POSIX sh stub")
    def test_failing_real_otool_process_fails_closed(self):
        # "all" fails every call; "-l" and "-L" fail one flag only, so each call site must check its own exit status.
        stubs = {"all": "exit 1", "-l": '[ "$1" = "-l" ] && exit 1; exit 0', "-L": '[ "$1" = "-L" ] && exit 1; exit 0'}
        for name, body in stubs.items():
            with self.subTest(failing=name), tempfile.TemporaryDirectory() as tmp, \
                    tempfile.TemporaryDirectory() as bin_dir:
                stub = Path(bin_dir) / "otool"
                stub.write_text("#!/bin/sh\n" + body + "\n")
                stub.chmod(0o755)
                app = self.make_app(Path(tmp))
                out = io.StringIO()
                with patch.dict(os.environ, {"PATH": bin_dir + os.pathsep + os.environ.get("PATH", "")}), \
                        redirect_stdout(out):
                    code = gate.check_app(app, "free")
                self.assertEqual(code, 1, out.getvalue())
                self.assertIn("cannot read", out.getvalue())

    def test_free_app_with_token_in_preview_dylib_fails(self):
        self.assert_free_fails(lambda app: (app / "__preview.dylib").write_bytes(b"..GADMobileAds.."),
                               "executable string GADMobileAds")

    def test_main_app_modes(self):
        with tempfile.TemporaryDirectory() as tmp:
            free = self.make_app(Path(tmp) / "a") if (Path(tmp) / "a").mkdir() is None else None
            mon = self.monetized_app(Path(tmp) / "b") if (Path(tmp) / "b").mkdir() is None else None
            cases = (
                (free, ("--expect", "free"), 0, "sdk-free: PASS"),
                (mon, ("--expect", "free"), 1, "sdk-free: FAIL"),
                (mon, ("--expect", "monetized"), 0, "sdk-linked: PASS"),
                (free, ("--expect", "monetized"), 1, "sdk-linked: FAIL missing"),
                (free, ("--expect", "auto"), 0, "sdk-free: PASS"),
                (mon, ("--expect", "auto"), 0, "sdk-linked: PASS"),
                (mon, (), 0, "sdk-linked: PASS"),
            )
            for app, flags, want, line in cases:
                with self.subTest(app=app.parent.name, flags=flags):
                    code, out = self.run_main(app, *flags)
                    self.assertEqual(code, want, out)
                    self.assertIn(line, out)

    def test_unreadable_app_fails_closed(self):
        def drop_executable_key(app):
            (app / "Info.plist").write_bytes(plistlib.dumps({"FilmyMonetizationEnabled": "NO"}))
        cases = {
            "missing Info.plist": lambda app: (app / "Info.plist").unlink(),
            "missing CFBundleExecutable": drop_executable_key,
            "missing executable": lambda app: (app / "FilmyCamera").unlink(),
            "garbage Info.plist": lambda app: (app / "Info.plist").write_bytes(b"<plist"),
            "non-dict Info.plist": lambda app: (app / "Info.plist").write_bytes(plistlib.dumps([1])),
        }
        for name, break_app in cases.items():
            for expect in ("free", "monetized", "auto"):
                with self.subTest(case=name, expect=expect), tempfile.TemporaryDirectory() as tmp:
                    app = self.make_app(Path(tmp), break_app)
                    code, out = self.run_main(app, "--expect", expect)
                    self.assertEqual(code, 1, out)
                    self.assertIn(f"sdk-gate: FAIL cannot read {app}:", out)
                    self.assertNotIn("PASS", out)

    def test_nonexistent_app_fails_closed(self):
        with tempfile.TemporaryDirectory() as tmp:
            code, out = self.run_main(Path(tmp) / "Nope.app", "--expect", "free")
        self.assertEqual(code, 1, out)
        self.assertIn("sdk-gate: FAIL cannot read", out)

    def test_otool_failure_fails_closed(self):
        error = subprocess.CalledProcessError(1, ["otool"])
        with tempfile.TemporaryDirectory() as tmp:
            app = self.make_app(Path(tmp))
            out = io.StringIO()
            with patch.object(gate.subprocess, "run", side_effect=error), redirect_stdout(out):
                code = gate.check_app(app, "free")
        self.assertEqual(code, 1)
        self.assertIn("sdk-gate: FAIL cannot read", out.getvalue())


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

    def monetized_app(self, root, drop_family=None, drop_key=None, drop_framework=None, info_extra=None):
        def extra(app):
            for name in gate.SDK_FRAMEWORKS:
                if name != drop_framework:
                    (app / "Frameworks" / f"{name}.framework").mkdir(parents=True)
            info = plistlib.loads((app / "Info.plist").read_bytes())
            info["FilmyMonetizationEnabled"] = "YES"
            for key in gate.SDK_PLIST_KEYS:
                if key != drop_key:
                    info[key] = "x"
            info.update(info_extra or {})
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

    def link_line(self, name):
        return f"\t@rpath/{name}.framework/{name} (compatibility version 1.0.0)\n"

    def test_otool_runs_l_and_L_on_executable_and_allowed_dylib(self):
        def add(app):
            (app / "FilmyCamera.debug.dylib").write_bytes(b"plain")
            (app / "__preview.dylib").write_bytes(b"plain")
        with tempfile.TemporaryDirectory() as tmp:
            app = self.make_app(Path(tmp), add)
            code, out = self.scan(app)
            calls = set(self.fake.calls)
            self.assertEqual(code, 0, out)
            for image in (app / "FilmyCamera", app / "FilmyCamera.debug.dylib", app / "__preview.dylib"):
                self.assertIn(("-l", image), calls)
                self.assertIn(("-L", image), calls)

    def test_monetized_framework_linked_only_by_debug_dylib_is_required(self):
        def add(app):
            (app / "FilmyCamera.debug.dylib").write_bytes(b"plain")
        with tempfile.TemporaryDirectory() as tmp:
            app = self.monetized_app(Path(tmp))
            add(app)
            shutil.rmtree(app / "Frameworks")
            code, out = self.scan(app, "monetized", by_image={
                ("-L", "FilmyCamera.debug.dylib"): self.link_line("GoogleMobileAds")})
        self.assertEqual(code, 1, out)
        self.assertIn("Frameworks/GoogleMobileAds.framework", out)
        self.assertNotIn("Frameworks/UserMessagingPlatform.framework", out)

    def test_monetized_frameworks_linked_on_different_images_are_all_required(self):
        with tempfile.TemporaryDirectory() as tmp:
            app = self.monetized_app(Path(tmp))
            (app / "FilmyCamera.debug.dylib").write_bytes(b"plain")
            shutil.rmtree(app / "Frameworks")
            code, out = self.scan(app, "monetized", by_image={
                ("-L", "FilmyCamera"): self.link_line("GoogleMobileAds"),
                ("-L", "FilmyCamera.debug.dylib"): self.link_line("UserMessagingPlatform")})
        self.assertEqual(code, 1, out)
        self.assertIn("Frameworks/GoogleMobileAds.framework", out)
        self.assertIn("Frameworks/UserMessagingPlatform.framework", out)

    def test_monetized_lookalike_framework_link_is_not_counted(self):
        with tempfile.TemporaryDirectory() as tmp:
            app = self.monetized_app(Path(tmp))
            shutil.rmtree(app / "Frameworks")
            for line in (self.link_line("GoogleMobileAdsX"), "\t@rpath/GoogleMobileAds.framework/GoogleMobileAdsX (x)\n"):
                with self.subTest(line=line):
                    code, out = self.scan(app, "monetized", otool=line)
                    self.assertEqual(code, 0, out)
                    self.assertIn("sdk-linked: PASS", out)

    def test_monetized_app_missing_a_linked_framework_fails(self):
        linked = "".join(f"\t@rpath/{n}.framework/{n} (compatibility version 1.0.0)\n" for n in gate.SDK_FRAMEWORKS)
        for name in gate.SDK_FRAMEWORKS:
            with self.subTest(name=name), tempfile.TemporaryDirectory() as tmp:
                code, out = self.scan(self.monetized_app(Path(tmp), drop_framework=name), "monetized", otool=linked)
                self.assertEqual(code, 1, out)
                self.assertIn(f"Frameworks/{name}.framework", out)

    def test_monetized_app_with_statically_linked_sdk_needs_no_framework_dir(self):
        with tempfile.TemporaryDirectory() as tmp:
            app = self.monetized_app(Path(tmp))
            shutil.rmtree(app / "Frameworks")
            code, out = self.scan(app, "monetized", otool="\t/usr/lib/libSystem.B.dylib\n")
        self.assertEqual(code, 0, out)
        self.assertIn("sdk-linked: PASS", out)

    def test_monetized_app_with_unresolved_build_setting_fails(self):
        with tempfile.TemporaryDirectory() as tmp:
            app = self.monetized_app(Path(tmp), info_extra={"GADApplicationIdentifier": "$(FILMY_ADMOB_APP_ID)"})
            code, out = self.scan(app, "monetized")
        self.assertEqual(code, 1, out)
        self.assertIn("GADApplicationIdentifier] holds an unresolved build setting", out)

    def test_monetized_app_with_nested_unresolved_build_setting_fails(self):
        nested = {"CFBundleURLTypes": [{"CFBundleURLSchemes": ["$(FILMY_GOOGLE_REVERSED_CLIENT_ID)"]}]}
        with tempfile.TemporaryDirectory() as tmp:
            code, out = self.scan(self.monetized_app(Path(tmp), info_extra=nested), "monetized")
        self.assertEqual(code, 1, out)
        self.assertIn("CFBundleURLSchemes", out)

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

    def test_source_import_forms_outside_condition_fail(self):
        forms = ("@_spi(Internal) import FirebaseCore", "@preconcurrency import GoogleSignIn",
                 "@testable import GoogleMobileAds", "@_exported import UserMessagingPlatform",
                 "@_implementationOnly import FirebaseAuth", "@_spi(X) @preconcurrency import FirebaseCore",
                 "public import GoogleMobileAds", "internal import GoogleSignIn", "package import FirebaseCore",
                 "private import FirebaseAuth", "fileprivate import GoogleUserMessagingPlatform",
                 "@_exported public import FirebaseCore", "import struct GoogleMobileAds.GADRequest",
                 "import class FirebaseCore.FirebaseApp", "import enum FirebaseAuth.AuthErrorCode",
                 "import protocol GoogleSignIn.GIDX", "import typealias FirebaseCore.X", "import func FirebaseCore.f",
                 "import var FirebaseCore.v", "import let FirebaseCore.l", "import FirebaseCore.Sub",
                 "import AppAuth", "import GTMAppAuth", "import GTMSessionFetcher", "import GoogleUtilities",
                 "import GoogleAppMeasurement", "import FBLPromises", "import FirebaseAuthInterop",
                 "import GoogleSignInSwift", "import AppCheckCore", "import RecaptchaInterop", "import PromisesObjC",
                 "import GoogleDataTransport", "import GoogleAdsOnDeviceConversion", "import nanopb",
                 "\timport   FirebaseCore  // trailing")
        for form in forms:
            with self.subTest(form=form):
                problems = self.source_problems_for(f"import SwiftUI\n{form}\n")
                self.assertEqual(len(problems), 1, problems)
                self.assertIn("A.swift:2", problems[0])
                self.assertEqual(self.source_problems_for(f"#if FILMY_MONETIZATION_SDKS\n{form}\n#endif\n"), [])

    def test_source_non_sdk_imports_pass_and_prefix_match_is_strict(self):
        for line in ("import Foundation", "import SwiftUI", "import GoogleMapsLike", "import FBLPromise",
                     "import UserNotifications", "import Nanopb", "import Promise", "import AppChec", "import struct Foundation.Date", "// import FirebaseCore"):
            with self.subTest(line=line):
                self.assertEqual(self.source_problems_for(line + "\n"), [])
        # Intentional false positive: a non-SDK name sharing an SDK prefix is flagged.
        self.assertEqual(len(self.source_problems_for("import AppAuthorizationKit\n")), 1)

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

    def test_plist_integer_one_does_not_equal_boolean_true(self):
        self.assertFalse(gate.plists_equal({"flag": 1}, {"flag": True}))
        self.assertTrue(gate.plists_equal({"flag": True, "a": 1}, {"a": 1, "flag": True}))

    def test_plist_monetized_boolean_key_holding_integer_fails(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            free_path = root / "Info.plist"
            monetized_path = root / "Info.Monetized.plist"
            free_path.write_bytes(plistlib.dumps({"CFBundleName": "Filmy"}))
            with patch.object(gate, "ROOT", root), patch.object(gate, "FREE_PLIST", free_path), \
                    patch.object(gate, "MONETIZED_PLIST", monetized_path):
                drifted = gate.expected_monetized_plist()
                drifted["GADDelayAppMeasurementInit"] = 1
                monetized_path.write_bytes(plistlib.dumps(drifted))
                problems = gate.plist_problems()
        self.assertEqual(len(problems), 1, problems)
        self.assertIn("differs", problems[0])

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
