#!/usr/bin/env python3
"""Idempotently wire the capture workspace into an existing Filmy checkout.

Run from the repository root, followed by `xcodegen generate`. This script checks
anchors instead of replacing complete upstream files. CI stages only these known
feature paths; it never force-pushes, modifies main, or changes signing credentials.
"""
from pathlib import Path
import os
import plistlib
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / "FilmyCamera/FilmyCameraApp.swift"
CAMERA = ROOT / "FilmyCamera/Services/CameraService.swift"
PROJECT = ROOT / "project.yml"
INFO = ROOT / "FilmyCamera/Info.plist"

SUSPEND = '''
// MARK: - Exclusive capture-workspace handoff
extension CameraService {
    /// Acknowledges release on the same queue that owns start/stop. Callers must
    /// unmount the legacy camera surface before awaiting this method, so its
    /// lifecycle cannot enqueue a later start while another workspace is active.
    public func suspendForCaptureModes() async {
        await withCheckedContinuation { continuation in
            sessionQueue.async { [weak self] in
                guard let self else { continuation.resume(); return }
                self.deferredStopGeneration &+= 1
                self.stopOnQueue()
                continuation.resume()
            }
        }
    }
}
'''


def main() -> None:
    app = APP.read_text()
    if "CaptureModesRoot(" not in app:
        if app.count("ContentView(") != 1:
            raise RuntimeError("Expected one ContentView entrypoint; reconcile the current app before integration.")
        APP.write_text(app.replace("ContentView(", "CaptureModesRoot(", 1))
    camera = CAMERA.read_text()
    if "func suspendForCaptureModes()" not in camera:
        for anchor in ["private let sessionQueue", "private func stopOnQueue()", "deferredStopGeneration"]:
            if anchor not in camera:
                raise RuntimeError(f"Camera handoff anchor is missing: {anchor}")
        CAMERA.write_text(camera.rstrip() + "\n" + SUSPEND)
    descriptions = {
        "NSCameraUsageDescription": "Filmy Camera uses the camera to capture photos and videos and to read text or codes when requested.",
        "NSMicrophoneUsageDescription": "Filmy Camera records microphone audio when you enable audio for a video.",
        "NSPhotoLibraryAddUsageDescription": "Filmy Camera saves finished photos and videos to your photo library.",
    }
    project = PROJECT.read_text()
    for key, value in descriptions.items():
        pattern = rf"(?m)^(\s*){key}:.*$"
        if re.search(pattern, project):
            project = re.sub(pattern, lambda m: f"{m.group(1)}{key}: {value}", project)
        else:
            anchor = re.search(r"(?m)^( +)NSCameraUsageDescription:.*$", project)
            if not anchor:
                raise RuntimeError("The XcodeGen camera permission anchor is missing.")
            project = project[:anchor.end()] + f"\n{anchor.group(1)}{key}: {value}" + project[anchor.end():]
    PROJECT.write_text(project)
    with INFO.open("rb") as file:
        info = plistlib.load(file)
    info.update(descriptions)
    with INFO.open("wb") as file:
        plistlib.dump(info, file, sort_keys=False)
    if os.environ.get("GITHUB_ACTIONS") == "true":
        paths = ["FilmyCamera/CaptureModes", "FilmyCameraTests/CaptureModesPolicyTests.swift",
                 "FilmyCameraTests/CaptureModesProcessingTests.swift", "docs/capture-modes.md",
                 "scripts/integrate_capture_modes.py", "scripts/test-capture-modes-policy.sh",
                 "scripts/capture-modes-policy/main.swift"]
        subprocess.run(["git", "add", "--", *paths], cwd=ROOT, check=True)
    print("Capture workspace integration is current. Run xcodegen generate to update the checked-in project.")


if __name__ == "__main__":
    main()
