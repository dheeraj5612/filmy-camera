#!/usr/bin/env python3
"""Run explicit XCTest lanes with shared build products and compact evidence.

No third-party Python packages. Photos E2Es create/delete only their own fresh
simulator; physical Photos writes require an explicit command-line opt-in.
"""
import argparse
from collections import Counter
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time
import uuid

ROOT = Path(__file__).resolve().parents[2]
MANIFEST = Path(__file__).with_name("suites.json")
LANES = {
    "unit": ["unit"], "integration": ["integration"],
    "core": ["unit", "integration"], "e2e": ["e2e", "simulator-e2e"],
    "photos-e2e": ["photos-e2e"],
    "ci": ["unit", "integration", "e2e", "simulator-e2e", "photos-e2e"],
    "device": ["device", "e2e"], "performance": ["performance"],
    "fixtures": ["fixtures"], "lens": ["lens"], "add-only": ["add-only"],
    "capture-sheet": ["capture-sheet"], "store-media": ["store-media"],
    "build": [], "device-build": []
}
GROUPS = {group for groups in LANES.values() for group in groups}
PHYSICAL = {"device", "lens", "add-only", "capture-sheet", "performance"}
PHOTOS_WRITES = {"device", "add-only"}
ENVIRONMENT = {
    "photos-e2e": {"FILMY_RUN_SEEDED_PHOTOS_E2E": "1"},
    "device": {"FILMY_RUN_PHOTOS_WRITE": "1", "FILMY_RUN_ROLL_QA": "1"},
    "performance": {"FILMY_RUN_PERF": "1"},
    "lens": {"FILMY_RUN_LENS_ACCEPTANCE": "1"},
    "add-only": {"FILMY_RUN_PHOTOS_WRITE": "1", "FILMY_RUN_ADD_ONLY_CACHE_QA": "1"},
    "capture-sheet": {"FILMY_RUN_CAPTURE_SHEET": "1"},
    "store-media": {"FILMY_RUN_STORE_MEDIA": "1"}
}


def inventory(root=ROOT, manifest_path=MANIFEST):
    manifest = json.loads(manifest_path.read_text())
    found = {}
    used_classes = set()
    for target in ("FilmyCameraTests", "FilmyCameraUITests"):
        for path in sorted((root / target).rglob("*.swift")):
            current_class = None
            for line in path.read_text().splitlines():
                match = re.search(r"\bclass\s+(\w+)\s*:\s*XCTestCase\b", line)
                if match and not line.lstrip().startswith("//"):
                    current_class = match.group(1)
                match = re.match(r"\s*func\s+(test\w+)\s*\(", line)
                if not match:
                    continue
                class_id = f"{target}/{current_class}"
                test_id = f"{class_id}/{match.group(1)}"
                if test_id in found:
                    raise ValueError(f"Duplicate test identifier: {test_id}")
                group = manifest["overrides"].get(test_id, manifest["classes"].get(class_id))
                if group not in GROUPS:
                    raise ValueError(f"Unclassified test: {test_id}; update {manifest_path}")
                if group == "simulator-e2e" and manifest["overrides"].get(test_id) != group:
                    raise ValueError(
                        f"Simulator-only test requires an explicit method override: {test_id}"
                    )
                if match.group(1).startswith("testPhysical") and group not in {
                    "device", "performance", "add-only", "capture-sheet"
                }:
                    raise ValueError(f"Physical test leaked into routine CI: {test_id}")
                used_classes.add(class_id)
                found[test_id] = group
    stale = set(manifest["overrides"]) - set(found)
    stale_classes = set(manifest["classes"]) - used_classes
    if stale or stale_classes:
        raise ValueError(f"Stale suite entries: {sorted(stale | stale_classes)}")
    return found


def phases(lane, tests):
    groups = LANES[lane]
    selected = lambda names: sorted(test for test, group in tests.items() if group in names)
    if lane == "ci":
        return [("core", selected({"unit", "integration"})),
                ("e2e", selected({"e2e", "simulator-e2e"})),
                ("photos-e2e", selected({"photos-e2e"}))]
    return [(lane, selected(set(groups)))] if groups else []


def validate_destination(lane, destination, allow_photos_writes):
    simulator = "platform=iOS Simulator" in destination
    physical = re.search(r"(?:^|,)platform=iOS(?:,|$)", destination) is not None
    if lane in PHYSICAL and (not physical or "id=" not in destination):
        raise ValueError(f"{lane} requires an explicit physical iOS device destination")
    if lane in {"unit", "integration", "core", "e2e", "ci", "photos-e2e", "store-media"} and not simulator:
        raise ValueError(f"{lane} requires an iOS Simulator destination")
    if lane in PHOTOS_WRITES and not allow_photos_writes:
        raise ValueError(f"{lane} can keep real photos; pass --allow-photos-writes to run it")
    if not simulator and not physical and lane != "device-build":
        raise ValueError("Use platform=iOS Simulator,id=... or platform=iOS,id=...")


def xcode_command(destination, derived_data, coverage=False):
    command = ["xcodebuild", "-project", "FilmyCamera.xcodeproj", "-scheme", "FilmyCamera",
               "-destination", destination, "-derivedDataPath", str(derived_data),
               "-parallel-testing-enabled", "NO", "-maximum-parallel-testing-workers", "1",
               "-enableCodeCoverage", "YES" if coverage else "NO"]
    if "Simulator" in destination or destination == "generic/platform=iOS":
        command += ["CODE_SIGNING_ALLOWED=NO", "CODE_SIGNING_REQUIRED=NO"]
    return command


def test_environment(phase, inherited=None):
    env = dict(os.environ if inherited is None else inherited)
    # A prior benchmark/Photos opt-in in the shell must not widen this lane.
    for key in list(env):
        if key.startswith("FILMY_RUN_") or key.startswith("TEST_RUNNER_FILMY_RUN_"):
            del env[key]
    for key, value in ENVIRONMENT.get(phase, {}).items():
        env["TEST_RUNNER_" + key] = value
    return env


def build_input_digest(root=ROOT):
    paths = [root / "project.yml", root / "FilmyCamera.xcodeproj/project.pbxproj"]
    for directory in ("FilmyCamera", "FilmyCameraTests", "FilmyCameraUITests",
                      "FilmyCamera.xcodeproj/xcshareddata"):
        paths += [path for path in (root / directory).rglob("*")
                  if path.is_file() and not any(part.startswith(".") for part in path.relative_to(root).parts)]
    digest = hashlib.sha256()
    for path in sorted(paths):
        if path.is_file():
            digest.update(str(path.relative_to(root)).encode() + b"\0")
            digest.update(hashlib.sha256(path.read_bytes()).digest())
    return digest.hexdigest()


def build_stamp_path(derived_data, destination):
    platform = "simulator" if "Simulator" in destination else "device"
    return derived_data / f".filmy-test-build-{platform}.json"


def validate_build_stamp(path, input_digest, coverage, toolchain):
    if not path.exists():
        raise ValueError("No verified test build exists; run this runner without --skip-build first")
    stamp = json.loads(path.read_text())
    if stamp != {"inputDigest": input_digest, "coverage": coverage, "toolchain": toolchain}:
        raise ValueError("Test build is stale or uses different coverage/Xcode settings; rebuild without --skip-build")


def run_logged(command, path, env=None):
    print(f"Running {command[0]} -> {path}", flush=True)
    with path.open("w") as log:
        process = subprocess.Popen(command, cwd=ROOT, env=env, stdout=subprocess.PIPE,
                                   stderr=subprocess.STDOUT, text=True)
        try:
            for line in process.stdout:
                log.write(line)
                print(line, end="", flush=True)
            return process.wait()
        except KeyboardInterrupt:
            process.terminate()
            process.wait(timeout=20)
            raise


def simctl(*arguments):
    return subprocess.check_output(["xcrun", "simctl", *arguments], text=True).strip()


def create_photos_simulator(destination):
    match = re.search(r"(?:^|,)id=([^,]+)", destination)
    if not match:
        raise ValueError("Photos E2E needs a simulator id to choose its runtime and device type")
    reference = match.group(1)
    devices = json.loads(simctl("list", "devices", "available", "--json"))["devices"]
    runtime, device = next(((runtime, device) for runtime, entries in devices.items()
                            for device in entries if device["udid"] == reference), (None, None))
    if not device or not device.get("deviceTypeIdentifier"):
        raise ValueError("Cannot resolve the reference simulator's runtime/device type")
    owned = simctl("create", "Filmy-Photos-E2E-" + uuid.uuid4().hex[:8],
                   device["deviceTypeIdentifier"], runtime)
    try:
        simctl("boot", owned)
        simctl("bootstatus", owned, "-b")
        # XCTest installs the app; the normal UI flow handles permission
        # prompts after installation instead of relying on pre-install grants.
        simctl("addmedia", owned, str(ROOT / "docs/app-store/screenshots/demo-source/cafe-original.png"))
        return owned
    except BaseException:
        destroy_simulator(owned)
        raise


def destroy_simulator(owned):
    # Only the UUID returned by this invocation's `simctl create` is deleted.
    subprocess.run(["xcrun", "simctl", "shutdown", owned], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["xcrun", "simctl", "delete", owned], check=True)


def summarize_result(result, exit_code):
    if not result.exists():
        return {"status": "failed", "reason": "XCTest did not produce a result bundle", "exitCode": exit_code}
    command = ["xcrun", "xcresulttool", "get", "test-results", "summary", "--path", str(result), "--format", "json"]
    summary = json.loads(subprocess.check_output(command, text=True))
    passed, failed, skipped = (summary.get(key, 0) for key in ("passedTests", "failedTests", "skippedTests"))
    return {"status": "passed" if exit_code == 0 and passed > 0 and failed == 0 else "failed",
            "passed": passed, "failed": failed, "skipped": skipped, "exitCode": exit_code,
            "testFailures": summary.get("testFailures", []),
            "devicesAndConfigurations": summary.get("devicesAndConfigurations", [])}


def require_complete_run(phase, selectors, summary):
    if phase in {"unit", "integration", "core", "e2e", "photos-e2e"} and summary.get("skipped", 0):
        summary.update(status="failed", reason="Unexpected skipped tests in a deterministic lane")
    actual_count = sum(summary.get(key, 0) for key in ("passed", "failed", "skipped"))
    if actual_count != len(selectors):
        summary.update(status="failed", reason=f"Selected {len(selectors)} tests but XCTest reported {actual_count}; check target membership/build products")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("lane", choices=[*LANES, "inventory"])
    parser.add_argument("--destination", default="")
    parser.add_argument("--derived-data", type=Path, default=ROOT / "build/TestSuiteDerivedData")
    parser.add_argument("--output-dir", type=Path)
    parser.add_argument("--skip-build", action="store_true")
    parser.add_argument("--coverage", action="store_true", help="Collect coverage explicitly; off in routine CI")
    parser.add_argument("--allow-photos-writes", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args(argv)
    tests = inventory()
    if args.lane == "inventory":
        print(json.dumps({"declaredTests": len(tests), "groups": dict(sorted(Counter(tests.values()).items())),
                          "tests": tests}, indent=2))
        return 0
    destination = "generic/platform=iOS" if args.lane == "device-build" else args.destination
    validate_destination(args.lane, destination, args.allow_photos_writes)
    selected_phases = phases(args.lane, tests)
    if args.dry_run:
        print(json.dumps({"lane": args.lane, "destination": destination,
                          "build": not args.skip_build, "phases": selected_phases}, indent=2))
        return 0
    output = (args.output_dir or ROOT / "build/test-runs" /
              (datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ-") + uuid.uuid4().hex[:6])).resolve()
    output.mkdir(parents=True, exist_ok=True)
    args.derived_data = args.derived_data.resolve()
    base = xcode_command(destination, args.derived_data, args.coverage)
    input_digest = build_input_digest()
    toolchain = subprocess.check_output(["xcodebuild", "-version"], text=True).strip()
    stamp_path = build_stamp_path(args.derived_data, destination)
    if not args.skip_build:
        # A failed replacement build must invalidate the previous verification.
        stamp_path.unlink(missing_ok=True)
        code = run_logged(base + ["-quiet", "build-for-testing"], output / "filmycamera-build-for-testing.log",
                          test_environment("build"))
        if code:
            return code
        if build_input_digest() != input_digest:
            raise ValueError("Source changed while building; rebuild before testing")
        stamp_path.write_text(json.dumps({"inputDigest": input_digest,
                                         "coverage": args.coverage, "toolchain": toolchain}) + "\n")
    else:
        validate_build_stamp(stamp_path, input_digest, args.coverage, toolchain)
    for phase, selectors in selected_phases:
        if not selectors:
            raise ValueError(f"No tests selected for {phase}")
        name = {"core": "Unit", "unit": "Unit", "integration": "Integration", "e2e": "UI",
                "photos-e2e": "PhotosE2E"}.get(phase, phase.title().replace("-", ""))
        result = output / f"FilmyCamera{name}.xcresult"
        if result.exists():
            raise ValueError(f"Refusing to overwrite evidence: {result}; choose another --output-dir")
        owned_simulator = None
        phase_destination = destination
        started = time.monotonic()
        try:
            if phase == "photos-e2e":
                owned_simulator = create_photos_simulator(destination)
                phase_destination = "platform=iOS Simulator,id=" + owned_simulator
            command = xcode_command(phase_destination, args.derived_data, args.coverage)
            command += ["-resultBundlePath", str(result)]
            command += ["-only-testing:" + test for test in selectors]
            command += ["test-without-building"]
            log_name = {"core": "unit", "e2e": "ui"}.get(phase, phase)
            code = run_logged(command, output / f"filmycamera-{log_name}-test.log", test_environment(phase))
            summary = summarize_result(result, code)
            require_complete_run(phase, selectors, summary)
            summary.update({"lane": phase, "selectedTests": selectors, "destination": phase_destination,
                            "elapsedSeconds": round(time.monotonic() - started, 2),
                            "commit": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
                            "worktreeDirty": bool(subprocess.check_output(["git", "status", "--porcelain"], cwd=ROOT, text=True).strip()),
                            "buildInputDigest": input_digest, "toolchain": toolchain,
                            "coverageEnabled": args.coverage})
            (output / f"filmycamera-{phase}-summary.json").write_text(json.dumps(summary, indent=2) + "\n")
            print(json.dumps({key: summary.get(key) for key in ("lane", "status", "passed", "failed", "skipped")}), flush=True)
            if summary["status"] != "passed":
                return code or 1
        finally:
            if owned_simulator:
                destroy_simulator(owned_simulator)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (ValueError, subprocess.CalledProcessError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(2)
