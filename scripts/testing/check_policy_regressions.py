#!/usr/bin/env python3
"""Execute production policy tests with SwiftPM, optionally checking six mutations.

Copies current sources into an owned temporary package. Never edits application
sources, creates simulators, accesses Photos, or substitutes for native iOS CI.
Only Linux's unavailable CoreGraphics import is omitted in the temporary copy;
Foundation supplies the geometry types used by these pure policies.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SOURCES = ("GalleryPagingPolicy.swift", "ReviewComparisonState.swift", "PhotoFinish.swift")
TESTS = ("GalleryPagingPolicyTests.swift", "ReviewComparisonStateTests.swift")
MUTATIONS = (
    ("unbounded-retention", "GalleryPagingPolicy.swift",
     "return max(0, index - 1)..<end", "return 0..<end"),
    ("invalid-offset-accepted", "GalleryPagingPolicy.swift",
     "offset == -1 || offset == 1", "offset == -1 || offset >= 0"),
    ("zoomed-panning-pages", "GalleryPagingPolicy.swift",
     "zoomScale == 1", "zoomScale >= 1"),
    ("failure-discards-visible-mode", "ReviewComparisonState.swift",
     "mutating func preparationFailed() { pendingMode = nil }",
     "mutating func preparationFailed() { pendingMode = nil; mode = .look }"),
    ("selection-discards-divider", "ReviewComparisonState.swift",
     "pendingMode = nil\n        if requested == .look",
     "pendingMode = nil\n        originalFraction = 0.5\n        if requested == .look"),
    ("mismatched-framing-accepted", "ReviewComparisonState.swift",
     "<= 0.003", "<= 0.03"),
)
PACKAGE = '''// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "FilmyPolicyValidation", targets: [
    .target(name: "FilmyCamera"),
    .testTarget(name: "FilmyCameraTests", dependencies: ["FilmyCamera"])
])
'''


def run_swift(swift, package, log):
    try:
        completed = subprocess.run(
            [swift, "test", "--package-path", str(package), "--jobs", "2"],
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=180,
        )
    except subprocess.TimeoutExpired as error:
        output = error.stdout or b""
        log.write_text(output.decode(errors="replace") if isinstance(output, bytes) else output)
        raise ValueError(f"Swift test timed out; inspect {log}") from error
    log.write_text(completed.stdout)
    return completed


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT, help="Repository checkout containing current sources")
    parser.add_argument("--output-dir", type=Path, help="New evidence directory; existing paths are never overwritten")
    parser.add_argument("--mutation-checks", action="store_true", help="Require six seeded behavioral defects to fail XCTest")
    args = parser.parse_args()
    swift = shutil.which("swift")
    if swift is None:
        raise ValueError("Swift 6 or newer is required; native app validation still requires Xcode")
    output = args.output_dir or Path(tempfile.mkdtemp(prefix="filmy-policy-evidence-"))
    if args.output_dir:
        output.mkdir(parents=True, exist_ok=False)
    version = subprocess.check_output([swift, "--version"], text=True, timeout=20).strip()
    evidence = {"toolchain": version, "nativeIOSValidated": False, "sources": {}, "mutations": []}
    print(f"Evidence: {output.resolve()}", flush=True)
    with tempfile.TemporaryDirectory(prefix="filmy-policy-package-") as temporary:
        package = Path(temporary)
        sources = package / "Sources/FilmyCamera"
        tests = package / "Tests/FilmyCameraTests"
        sources.mkdir(parents=True)
        tests.mkdir(parents=True)
        (package / "Package.swift").write_text(PACKAGE)
        for filename in SOURCES:
            path = args.root / "FilmyCamera/Models" / filename
            original = path.read_bytes()
            evidence["sources"][str(path.relative_to(args.root))] = hashlib.sha256(original).hexdigest()
            text = original.decode("utf-8")
            if sys.platform.startswith("linux"):
                text = text.replace("import CoreGraphics\n", "")
            (sources / filename).write_text(text)
        expected = 0
        for filename in TESTS:
            path = args.root / "FilmyCameraTests" / filename
            original = path.read_bytes()
            evidence["sources"][str(path.relative_to(args.root))] = hashlib.sha256(original).hexdigest()
            text = original.decode("utf-8")
            expected += len(re.findall(r"^\s*func\s+test\w+\s*\(", text, re.MULTILINE))
            (tests / filename).write_text(text)
        if expected == 0:
            raise ValueError("No XCTest methods found; refusing an empty validation")
        baseline = run_swift(swift, package, output / "baseline.log")
        evidence["baseline"] = {"exitCode": baseline.returncode, "expectedTests": expected}
        (output / "summary.json").write_text(json.dumps(evidence, indent=2) + "\n")
        if baseline.returncode != 0 or f"Executed {expected} tests, with 0 failures" not in baseline.stdout:
            raise ValueError(f"Baseline failed or did not execute all {expected} tests; inspect {output / 'baseline.log'}")
        print(f"Baseline: {expected} tests passed", flush=True)
        if args.mutation_checks:
            for name, filename, before, after in MUTATIONS:
                path = sources / filename
                original = path.read_text()
                if original.count(before) != 1:
                    raise ValueError(f"Mutation {name} no longer matches exactly once; review it against current sources")
                try:
                    path.write_text(original.replace(before, after, 1))
                    result = run_swift(swift, package, output / f"{name}.log")
                finally:
                    path.write_text(original)
                # Compilation errors and empty/aborted runs are not mutation kills.
                detected = result.returncode != 0 and re.search(
                    r"Test Case '.+' failed \(", result.stdout
                ) is not None and "Build complete!" in result.stdout and re.search(
                    rf"Executed {expected} tests, with [1-9][0-9]* failures", result.stdout
                ) is not None
                evidence["mutations"].append({"name": name, "detectedByXCTest": detected, "exitCode": result.returncode})
                (output / "summary.json").write_text(json.dumps(evidence, indent=2) + "\n")
                if not detected:
                    raise ValueError(f"Mutation {name} survived or did not reach a failing XCTest; inspect its log")
                print(f"Detected mutation: {name}", flush=True)
        evidence["status"] = "passed"
        (output / "summary.json").write_text(json.dumps(evidence, indent=2) + "\n")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
