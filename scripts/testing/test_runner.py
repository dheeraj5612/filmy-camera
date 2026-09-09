"""Portable checks for suite routing and test-evidence failure handling."""
import contextlib
import io
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import run


class SuiteRoutingTests(unittest.TestCase):
    def test_every_declared_test_has_an_explicit_lane(self):
        tests = run.inventory()
        self.assertTrue(tests)
        self.assertEqual(len(tests), len(set(tests)))

    def test_routine_ci_includes_all_deterministic_tests_and_no_opt_ins(self):
        tests = run.inventory()
        selected = [test for _, identifiers in run.phases("ci", tests) for test in identifiers]
        self.assertCountEqual(selected, [test for test, group in tests.items()
                                         if group in {"unit", "integration", "e2e", "simulator-e2e", "photos-e2e"}])
        self.assertEqual(len(selected), len(set(selected)), "CI should not rerun tests across phases")
        self.assertFalse(any("/testPhysical" in test for test in selected))

    def test_simulator_only_ui_cases_run_in_e2e_and_ci_but_not_on_device(self):
        tests = run.inventory()
        expected = {
            "FilmyCameraUITests/FilmyCameraUITests/testSimulatorFallbackExposesReadableStateWithoutPreviewAction",
            "FilmyCameraUITests/FilmyCameraUITests/testViewfinderFirstChromePreviewKeepsCameraQuiet",
        }
        self.assertEqual({test for test, group in tests.items() if group == "simulator-e2e"}, expected)
        e2e = set(run.phases("e2e", tests)[0][1])
        ci = {test for _, selected in run.phases("ci", tests) for test in selected}
        device = set(run.phases("device", tests)[0][1])
        self.assertTrue(expected <= e2e)
        self.assertTrue(expected <= ci)
        self.assertTrue(expected.isdisjoint(device))
        self.assertTrue(
            {test for test, group in tests.items() if group == "e2e"} <= device,
            "The physical lane must retain every platform-independent UI acceptance",
        )

    def test_unknown_and_stale_tests_fail_inventory(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "FilmyCameraTests").mkdir()
            source = root / "FilmyCameraTests/Example.swift"
            source.write_text("final class Example: XCTestCase {\n func testNewCase() {}\n}\n")
            manifest = root / "suites.json"
            manifest.write_text(json.dumps({"classes": {}, "overrides": {}}))
            with self.assertRaisesRegex(ValueError, "Unclassified"):
                run.inventory(root, manifest)
            manifest.write_text(json.dumps({"classes": {"FilmyCameraTests/Example": "unit"},
                "overrides": {"FilmyCameraTests/Example/testRemoved": "unit"}}))
            with self.assertRaisesRegex(ValueError, "Stale"):
                run.inventory(root, manifest)
            # Aggregate commands are not leaf groups: accepting "ci" here
            # would silently omit this class from every selected CI phase.
            manifest.write_text(json.dumps({"classes": {"FilmyCameraTests/Example": "ci"}, "overrides": {}}))
            with self.assertRaisesRegex(ValueError, "Unclassified"):
                run.inventory(root, manifest)
            manifest.write_text(json.dumps({
                "classes": {"FilmyCameraTests/Example": "simulator-e2e"}, "overrides": {}
            }))
            with self.assertRaisesRegex(ValueError, "explicit method override"):
                run.inventory(root, manifest)

    def test_nested_helper_class_does_not_steal_test_ownership(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "FilmyCameraTests").mkdir()
            (root / "FilmyCameraTests/Example.swift").write_text(
                "final class Example: XCTestCase {\n private class Sink: NSObject {}\n func testCallback() {}\n}\n")
            manifest = root / "suites.json"
            manifest.write_text(json.dumps({"classes": {"FilmyCameraTests/Example": "unit"}, "overrides": {}}))
            self.assertEqual(run.inventory(root, manifest), {"FilmyCameraTests/Example/testCallback": "unit"})

    def test_inherited_opt_ins_cannot_enable_photos_or_benchmarks_in_ci(self):
        env = run.test_environment("core", {
            "TEST_RUNNER_FILMY_RUN_PHOTOS_WRITE": "1", "FILMY_RUN_PERF": "1", "PATH": "/test/bin"})
        self.assertEqual(env, {"PATH": "/test/bin"})
        self.assertEqual(run.test_environment("photos-e2e", {}),
                         {"TEST_RUNNER_FILMY_RUN_SEEDED_PHOTOS_E2E": "1"})
        self.assertEqual(
            run.test_environment("store-media", {
                "FILMY_STORE_PRIOR_SAVES": "4",
                "TEST_RUNNER_FILMY_STORE_PRIOR_SAVES": "7",
                "FILMY_RUN_STORE_MEDIA": "1",
            }),
            {
                "TEST_RUNNER_FILMY_RUN_STORE_MEDIA": "1",
                "TEST_RUNNER_FILMY_STORE_PRIOR_SAVES": "0",
            },
        )

    def test_device_writes_fail_before_any_process_without_opt_in(self):
        with patch.object(run.subprocess, "Popen") as process:
            with self.assertRaisesRegex(ValueError, "allow-photos-writes"):
                run.main(["device", "--destination", "platform=iOS,id=example"])
            process.assert_not_called()

    def test_simulator_and_device_lanes_reject_wrong_platform(self):
        for lane, destination in [("e2e", "platform=iOS,id=example"),
                                  ("photos-e2e", "platform=iOS,id=example"),
                                  ("performance", "platform=iOS Simulator,id=example"),
                                  ("device", "platform=iOS Simulator,id=example")]:
            with self.subTest(lane=lane), self.assertRaises(ValueError):
                run.validate_destination(lane, destination, True)

    def test_dry_run_has_no_build_or_simulator_side_effects(self):
        with patch.object(run.subprocess, "Popen") as process, patch.object(run, "simctl") as simctl:
            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                self.assertEqual(run.main(["ci", "--destination", "platform=iOS Simulator,id=example", "--dry-run"]), 0)
            self.assertEqual(len(json.loads(output.getvalue())["phases"]), 3)
            process.assert_not_called()
            simctl.assert_not_called()

    def test_photos_setup_failure_deletes_only_its_own_simulator(self):
        def fake_simctl(*args, timeout=run.SIMCTL_DEFAULT_TIMEOUT_SECONDS):
            if args[0] == "list":
                return json.dumps({"devices": {"runtime": [{"udid": "reference", "deviceTypeIdentifier": "type"}]}})
            if args[0] == "create":
                return "owned"
            if args[0] == "addmedia":
                raise RuntimeError("fixture seeding failed")
            return ""
        with patch.object(run, "simctl", side_effect=fake_simctl), patch.object(run, "destroy_simulator") as destroy:
            with self.assertRaises(RuntimeError):
                run.create_photos_simulator("platform=iOS Simulator,id=reference")
            destroy.assert_called_once_with("owned")

    def test_photos_media_timeout_is_bounded_and_deletes_only_owned_simulator(self):
        calls = []

        def fake_simctl(*args, timeout=run.SIMCTL_DEFAULT_TIMEOUT_SECONDS):
            calls.append((args, timeout))
            if args[0] == "list":
                return json.dumps({"devices": {"runtime": [{
                    "udid": "reference", "deviceTypeIdentifier": "type"
                }]}})
            if args[0] == "create":
                return "owned"
            if args[0] == "addmedia":
                raise ValueError(
                    f"simctl addmedia timed out after {timeout} seconds"
                )
            return ""

        with patch.object(run, "simctl", side_effect=fake_simctl), \
                patch.object(run, "destroy_simulator") as destroy:
            with self.assertRaisesRegex(ValueError, "addmedia timed out after 300 seconds"):
                run.create_photos_simulator("platform=iOS Simulator,id=reference")

        self.assertIn(
            (("boot", "owned"), run.SIMULATOR_BOOT_TIMEOUT_SECONDS),
            calls,
        )
        self.assertIn(
            (("bootstatus", "owned", "-b"), run.SIMULATOR_BOOT_TIMEOUT_SECONDS),
            calls,
        )
        self.assertIn(
            (
                ("addmedia", "owned", str(
                    run.ROOT / "docs/app-store/screenshots/demo-source/cafe-original.png"
                )),
                run.SIMULATOR_MEDIA_TIMEOUT_SECONDS,
            ),
            calls,
        )
        destroy.assert_called_once_with("owned")
        self.assertFalse(any("reference" in args[1:] for args, _ in calls if args[0] != "list"))

    def test_cleanup_timeout_still_attempts_bounded_owned_delete(self):
        shutdown_timeout = subprocess.TimeoutExpired(
            ["xcrun", "simctl", "shutdown", "owned"],
            run.SIMULATOR_SHUTDOWN_TIMEOUT_SECONDS,
        )
        with patch.object(
            run.subprocess,
            "run",
            side_effect=[shutdown_timeout, subprocess.CompletedProcess([], 0)],
        ) as process, contextlib.redirect_stderr(io.StringIO()):
            run.destroy_simulator("owned")

        self.assertEqual(process.call_count, 2)
        shutdown_call, delete_call = process.call_args_list
        self.assertEqual(shutdown_call.args[0][-1], "owned")
        self.assertEqual(
            shutdown_call.kwargs["timeout"], run.SIMULATOR_SHUTDOWN_TIMEOUT_SECONDS
        )
        self.assertEqual(delete_call.args[0][-1], "owned")
        self.assertEqual(delete_call.kwargs["timeout"], run.SIMULATOR_DELETE_TIMEOUT_SECONDS)

    def test_test_failure_is_not_masked_by_owned_cleanup_timeout(self):
        with patch.object(run, "create_photos_simulator", return_value="owned"), \
                patch.object(
                    run,
                    "destroy_simulator",
                    side_effect=ValueError("cleanup timed out"),
                ), contextlib.redirect_stderr(io.StringIO()):
            with self.assertRaisesRegex(RuntimeError, "system picker failed"):
                with run.isolated_photos_destination(
                    "photos-e2e", "platform=iOS Simulator,id=reference"
                ):
                    raise RuntimeError("system picker failed")

    def test_failed_phase_exit_code_and_summary_survive_cleanup_timeout(self):
        test_id = "FilmyCameraUITests/Example/testPhotos"

        def command_output(command, **_):
            if command[:2] == ["xcodebuild", "-version"]:
                return "Xcode test"
            if command[:3] == ["git", "rev-parse", "HEAD"]:
                return "head\n"
            if command[:3] == ["git", "status", "--porcelain"]:
                return ""
            self.fail(f"Unexpected command: {command}")

        with tempfile.TemporaryDirectory() as directory, \
                patch.object(run, "inventory", return_value={test_id: "photos-e2e"}), \
                patch.object(run, "build_input_digest", return_value="digest"), \
                patch.object(run, "validate_build_stamp"), \
                patch.object(run, "create_photos_simulator", return_value="owned"), \
                patch.object(run, "destroy_simulator", side_effect=ValueError("cleanup timed out")), \
                patch.object(run, "run_logged", return_value=65), \
                patch.object(run, "summarize_result", return_value={
                    "status": "failed", "passed": 0, "failed": 1,
                    "skipped": 0, "exitCode": 65,
                }), patch.object(run.subprocess, "check_output", side_effect=command_output), \
                contextlib.redirect_stdout(io.StringIO()), \
                contextlib.redirect_stderr(io.StringIO()):
            output = Path(directory) / "results"
            code = run.main([
                "photos-e2e",
                "--destination", "platform=iOS Simulator,id=reference",
                "--derived-data", str(Path(directory) / "derived"),
                "--output-dir", str(output),
                "--skip-build",
            ])

            self.assertEqual(code, 65)
            summary = json.loads(
                (output / "filmycamera-photos-e2e-summary.json").read_text()
            )
            self.assertEqual(summary["status"], "failed")
            self.assertEqual(summary["exitCode"], 65)

    def test_photos_methods_run_once_in_isolated_invocations_and_aggregate(self):
        tests = {
            f"FilmyCameraUITests/NormalPhotoFlowTests/testCase{index}": "photos-e2e"
            for index in range(1, 4)
        }
        summaries = [
            {"status": "passed", "passed": 1, "failed": 0, "skipped": 0},
            {"status": "failed", "passed": 0, "failed": 1, "skipped": 0,
             "testFailures": [{"message": "picker unavailable"}]},
            {"status": "passed", "passed": 1, "failed": 0, "skipped": 0},
        ]

        def command_output(command, **_):
            if command[:2] == ["xcodebuild", "-version"]:
                return "Xcode test"
            if command[:3] == ["git", "rev-parse", "HEAD"]:
                return "head\n"
            if command[:3] == ["git", "status", "--porcelain"]:
                return ""
            self.fail(f"Unexpected command: {command}")

        with tempfile.TemporaryDirectory() as directory, \
                patch.object(run, "inventory", return_value=tests), \
                patch.object(run, "build_input_digest", return_value="digest"), \
                patch.object(run, "validate_build_stamp"), \
                patch.object(run, "create_photos_simulator", return_value="owned"), \
                patch.object(run, "destroy_simulator") as destroy, \
                patch.object(run, "run_logged", side_effect=[0, 65, 0]) as execute, \
                patch.object(run, "summarize_result", side_effect=summaries), \
                patch.object(run.subprocess, "check_call") as merge, \
                patch.object(run.subprocess, "check_output", side_effect=command_output), \
                contextlib.redirect_stdout(io.StringIO()):
            output = Path(directory) / "results"
            code = run.main([
                "photos-e2e",
                "--destination", "platform=iOS Simulator,id=reference",
                "--derived-data", str(Path(directory) / "derived"),
                "--output-dir", str(output),
                "--skip-build",
            ])

            self.assertEqual(code, 65)
            self.assertEqual(execute.call_count, 3)
            selected = []
            for call in execute.call_args_list:
                command = call.args[0]
                selectors = [argument for argument in command if argument.startswith("-only-testing:")]
                self.assertEqual(len(selectors), 1)
                selected.append(selectors[0].removeprefix("-only-testing:"))
                self.assertEqual(command[-1], "test-without-building")
                self.assertIn("platform=iOS Simulator,id=owned", command)
            self.assertCountEqual(selected, tests)

            merge_command = merge.call_args.args[0]
            self.assertEqual(merge_command[:4], [
                "xcrun", "xcresulttool", "merge", "--output-path"
            ])
            self.assertEqual(len(merge_command[5:]), 3)
            destroy.assert_called_once_with("owned")

            summary = json.loads(
                (output / "filmycamera-photos-e2e-summary.json").read_text()
            )
            self.assertEqual(summary["status"], "failed")
            self.assertEqual(summary["exitCode"], 65)
            self.assertEqual(
                (summary["passed"], summary["failed"], summary["skipped"]),
                (2, 1, 0),
            )
            self.assertEqual(len(summary["caseResults"]), 3)
            self.assertEqual(len({case["resultBundle"] for case in summary["caseResults"]}), 3)
            self.assertEqual(summary["mergedResultBundle"], "FilmyCameraPhotosE2E.xcresult")

    def test_photos_merge_failure_keeps_raw_case_evidence_authoritative(self):
        selectors = ["Target/Case/testOne", "Target/Case/testTwo"]
        passed = {"status": "passed", "passed": 1, "failed": 0, "skipped": 0}
        with tempfile.TemporaryDirectory() as directory, \
                patch.object(run, "run_logged", return_value=0) as execute, \
                patch.object(run, "summarize_result", side_effect=[passed.copy(), passed.copy()]), \
                patch.object(
                    run.subprocess,
                    "check_call",
                    side_effect=subprocess.CalledProcessError(1, ["xcresulttool", "merge"]),
                ):
            output = Path(directory)
            summary, code = run.run_isolated_photos_methods(
                ["xcodebuild"], selectors, output / "FilmyCameraPhotosE2E.xcresult",
                output, {},
            )

        self.assertEqual(execute.call_count, 2)
        self.assertEqual(code, 1)
        self.assertEqual(summary["status"], "failed")
        self.assertIsNone(summary["mergedResultBundle"])
        self.assertEqual(
            [case["resultBundle"] for case in summary["caseResults"]],
            [
                "FilmyCameraPhotosE2E-01-testOne.xcresult",
                "FilmyCameraPhotosE2E-02-testTwo.xcresult",
            ],
        )

    def test_photos_and_store_media_destroy_their_owned_simulator_on_exit(self):
        for phase in ("photos-e2e", "store-media"):
            with self.subTest(phase=phase), \
                    patch.object(run, "create_photos_simulator", return_value="owned") as create, \
                    patch.object(run, "destroy_simulator") as destroy:
                with self.assertRaisesRegex(RuntimeError, "test stopped"):
                    with run.isolated_photos_destination(
                        phase, "platform=iOS Simulator,id=reference"
                    ) as destination:
                        self.assertEqual(destination, "platform=iOS Simulator,id=owned")
                        raise RuntimeError("test stopped")
                create.assert_called_once_with("platform=iOS Simulator,id=reference")
                destroy.assert_called_once_with("owned")

        with patch.object(run, "create_photos_simulator") as create:
            with run.isolated_photos_destination(
                "e2e", "platform=iOS Simulator,id=reference"
            ) as destination:
                self.assertEqual(destination, "platform=iOS Simulator,id=reference")
            create.assert_not_called()


class EvidenceTests(unittest.TestCase):
    def test_stale_source_or_toolchain_cannot_reuse_test_products(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "stamp.json"
            path.write_text(json.dumps({"inputDigest": "current", "coverage": False, "toolchain": "Xcode"}))
            run.validate_build_stamp(path, "current", False, "Xcode")
            for digest, coverage, toolchain in (("changed", False, "Xcode"),
                                               ("current", True, "Xcode"),
                                               ("current", False, "new Xcode")):
                with self.subTest(digest=digest, coverage=coverage, toolchain=toolchain), self.assertRaisesRegex(ValueError, "stale"):
                    run.validate_build_stamp(path, digest, coverage, toolchain)

    def test_unverified_build_cannot_be_reused(self):
        with tempfile.TemporaryDirectory() as directory, self.assertRaisesRegex(ValueError, "No verified"):
            run.validate_build_stamp(Path(directory) / "absent", "current", False, "Xcode")

    def test_build_digest_tracks_source_resources_and_target_membership(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "FilmyCameraTests").mkdir()
            (root / "FilmyCamera.xcodeproj").mkdir()
            previous = run.build_input_digest(root)
            for relative, value in (("FilmyCameraTests/New.swift", "func testNew() {}"),
                                    ("FilmyCameraTests/fixture.jpg", "image"),
                                    ("FilmyCamera.xcodeproj/project.pbxproj", "target membership"),
                                    ("FilmyCameraTests/New.swift", "func testChanged() {}")):
                (root / relative).write_text(value)
                current = run.build_input_digest(root)
                self.assertNotEqual(current, previous)
                previous = current

    def test_missing_result_bundle_cannot_pass(self):
        with tempfile.TemporaryDirectory() as directory:
            self.assertEqual(run.summarize_result(Path(directory) / "absent", 0)["status"], "failed")

    def test_zero_tests_cannot_pass_despite_successful_xcode_exit(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(run.subprocess, "check_output", return_value='{"passedTests":0}'):
            self.assertEqual(run.summarize_result(Path(directory), 0)["status"], "failed")

    def test_skipped_prerequisite_is_failure_in_routine_ci(self):
        summary = {"status": "passed", "passed": 1, "failed": 0, "skipped": 1}
        run.require_complete_run("photos-e2e", ["one", "two"], summary)
        self.assertEqual(summary["status"], "failed")

    def test_stale_build_missing_new_tests_is_failure(self):
        summary = {"status": "passed", "passed": 1, "failed": 0, "skipped": 0}
        run.require_complete_run("core", ["old", "new"], summary)
        self.assertEqual(summary["status"], "failed")
        self.assertIn("target membership", summary["reason"])

    def test_known_hardware_limitations_remain_explicit_skips(self):
        summary = {"status": "passed", "passed": 1, "failed": 0, "skipped": 1}
        run.require_complete_run("device", ["one", "two"], summary)
        self.assertEqual(summary["skipped"], 1)
        self.assertEqual(summary["status"], "passed")

    def test_missing_opt_in_tests_cannot_pass_as_supported_subset(self):
        for lane in ("device", "performance", "lens", "add-only", "capture-sheet", "fixtures", "store-media"):
            with self.subTest(lane=lane):
                summary = {"status": "passed", "passed": 1, "failed": 0, "skipped": 0}
                run.require_complete_run(lane, ["one", "two"], summary)
                self.assertEqual(summary["status"], "failed")


if __name__ == "__main__":
    unittest.main()
