#!/usr/bin/env python3
"""Portable Swift syntax and pure interaction-policy checks, not an iOS build.

Runs the actual FilmyControlInteractionTests against the production policy
extracted from Components.swift. UIKit/SwiftUI layout, VoiceOver, PhotoKit,
and rendering still require the repository's Xcode/simulator test lanes.
"""
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def declaration(source: str, start_marker: str, end_marker: str) -> str:
    """Use explicit neighboring declarations so source drift fails loudly."""
    start = source.index(start_marker)
    end = source.index(end_marker, start)
    return source[start:end].rstrip()


def main() -> None:
    swiftc = shutil.which("swiftc")
    if swiftc is None:
        raise SystemExit("swiftc is required. This script does not install a toolchain.")
    sources = [
        "FilmyCamera/ContentView.swift",
        "FilmyCamera/Views/Components.swift",
        "FilmyCamera/Views/OnboardingView.swift",
        "FilmyCamera/Views/SettingsView.swift",
        "FilmyCameraTests/CameraPreviewGesturePolicyTests.swift",
        "FilmyCameraUITests/NormalRollManagementTests.swift",
        "FilmyCameraUITests/SignalFrameUITests.swift",
    ]
    for relative in sources:
        subprocess.run([swiftc, "-frontend", "-parse", str(ROOT / relative)], check=True, timeout=45)
        print(f"PASS Swift syntax: {relative}", flush=True)

    components = (ROOT / sources[1]).read_text()
    tests = (ROOT / sources[4]).read_text()
    policy = declaration(components, "enum FilmyInteractionPolicy {", "struct PressableButtonStyle:")
    suite = tests[tests.index("final class FilmyControlInteractionTests:"):]
    names = re.findall(r"    func (test\w+)\(\)", suite)
    if len(names) != 8:
        raise SystemExit(f"Expected all 8 interaction tests, found {len(names)}. Update the harness intentionally.")
    entries = ",\n".join(f'    ("{name}", FilmyControlInteractionTests.{name})' for name in names)
    program = "import Foundation\nimport XCTest\n" + policy + "\n" + suite
    program += "\nXCTMain([testCase([\n" + entries + "\n])])\n"
    with tempfile.TemporaryDirectory(prefix="filmy-ui-policy-") as temporary:
        directory = Path(temporary)
        source = directory / "main.swift"
        executable = directory / "interaction-tests"
        source.write_text(program)
        subprocess.run([swiftc, str(source), "-o", str(executable)], check=True, timeout=45)
        subprocess.run([str(executable)], check=True, timeout=45)
    print("PASS portable interaction suite. Native iOS type checking and visual acceptance are NOT covered.")


if __name__ == "__main__":
    main()
