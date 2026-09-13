#!/usr/bin/env python3
"""Replay a paired renderer capture through the local iOS Simulator test lane.

The script intentionally runs one XCTest invocation with parallel testing disabled.
It records xcodebuild output in the requested output directory; it does not imply
that simulator pixels are bitwise equivalent to an iPad render.
"""

import argparse
import io
import json
from pathlib import Path
import plistlib
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_DEVICE = "B90FF3A2-50FA-45F2-9ACB-CED1C8FE5043"
TEST_ID = "FilmyCameraTests/RendererSkinCaptureDiagnosticsTests"


def run_logged(command, log_path):
    """Run one command and preserve its combined output in *log_path*."""
    with log_path.open("w", encoding="utf-8") as log:
        process = subprocess.run(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT,
                                 check=False)
    return process.returncode


def xctestrun_path(derived_data):
    candidates = sorted(derived_data.glob("Build/Products/*.xctestrun"))
    preferred = [path for path in candidates if "iphonesimulator" in path.name.lower()]
    candidates = preferred or candidates
    if len(candidates) != 1:
        names = ", ".join(str(path) for path in candidates) or "none"
        raise RuntimeError(f"expected one simulator xctestrun in {derived_data}/Build/Products; found {names}")
    return candidates[0]


def patch_xctestrun(path, input_dir, output_dir, variants):
    raw = path.read_bytes()
    data = plistlib.loads(raw)
    testable = data.get("FilmyCameraTests")
    if not isinstance(testable, dict):
        raise RuntimeError(f"{path} has no flat FilmyCameraTests testable entry")
    environment = testable.setdefault("EnvironmentVariables", {})
    environment["FILMY_SKIN_DIAGNOSTIC_INPUT"] = str(input_dir)
    environment["FILMY_SKIN_DIAGNOSTIC_OUTPUT"] = str(output_dir)
    if variants:
        environment["FILMY_SKIN_DIAGNOSTIC_VARIANTS"] = "1"
    else:
        environment.pop("FILMY_SKIN_DIAGNOSTIC_VARIANTS", None)
    fmt = plistlib.FMT_BINARY if raw.startswith(b"bplist00") else plistlib.FMT_XML
    with path.open("wb") as handle:
        plistlib.dump(data, handle, fmt=fmt, sort_keys=False)


def parse_args(argv):
    parser = argparse.ArgumentParser(description="Replay a paired skin renderer capture on an iOS Simulator.")
    parser.add_argument("--input", required=True, type=Path, help="paired capture directory")
    parser.add_argument("--output", required=True, type=Path, help="directory for diagnostics and logs")
    parser.add_argument("--device", default=DEFAULT_DEVICE, help="Simulator UDID")
    parser.add_argument("--derived-data", type=Path, default=Path("/tmp/filmy-mac-speckle"),
                        help="DerivedData directory (default: /tmp/filmy-mac-speckle)")
    parser.add_argument("--skip-build", action="store_true", help="reuse an existing build-for-testing output")
    parser.add_argument("--variants", action="store_true",
                        help="set FILMY_SKIN_DIAGNOSTIC_VARIANTS=1 for the harness")
    parser.add_argument("--compare", action="store_true",
                        help="write an observational Pillow/numpy comparison against input/final.jpg")
    return parser.parse_args(argv)


def write_replay_command(output_dir, args, input_dir, derived_data):
    try:
        head = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
        dirty = bool(subprocess.check_output(["git", "status", "--porcelain"], cwd=ROOT, text=True).strip())
    except subprocess.CalledProcessError:
        head, dirty = None, None
    record = {
        "invocation": [str(Path(sys.argv[0]).resolve()), *sys.argv[1:]],
        "gitHEAD": head,
        "worktreeDirty": dirty,
        "input": str(input_dir),
        "output": str(output_dir),
        "derivedData": str(derived_data),
        "skipBuild": args.skip_build,
    }
    (output_dir / "replay-command.json").write_text(json.dumps(record, indent=2) + "\n", encoding="utf-8")


def compare_images(input_dir, output_dir):
    try:
        import numpy as np
        from PIL import Image, ImageCms
    except ImportError as error:
        print(f"--compare requires Pillow and numpy: {error}", file=sys.stderr)
        return 2
    source_path = input_dir / "final.jpg"
    replay_path = output_dir / "capture-replay.jpg"
    report = {
        "source": str(source_path),
        "replay": str(replay_path),
        "comparison": "decoded JPEG pixels after optional ICC-to-sRGB conversion",
        "orientationHandling": "EXIF orientation is reported, not applied; production JPEGs are expected to be orientation=1",
    }
    try:
        with Image.open(source_path) as source, Image.open(replay_path) as replay:
            report["sourceDimensions"] = list(source.size)
            report["replayDimensions"] = list(replay.size)
            report["sourceICCProfilePresent"] = "icc_profile" in source.info
            report["replayICCProfilePresent"] = "icc_profile" in replay.info
            report["sourceEXIFOrientation"] = source.getexif().get(274, 1)
            report["replayEXIFOrientation"] = replay.getexif().get(274, 1)
            if source.size != replay.size:
                report["error"] = "dimension mismatch"
            else:
                srgb = ImageCms.createProfile("sRGB")

                def to_srgb(image):
                    icc = image.info.get("icc_profile")
                    image = image.convert("RGB")
                    if not icc:
                        return image
                    return ImageCms.profileToProfile(
                        image, ImageCms.ImageCmsProfile(io.BytesIO(icc)), srgb,
                        outputMode="RGB")

                source_rgb = np.asarray(to_srgb(source), dtype=np.float32) / 255.0
                replay_rgb = np.asarray(to_srgb(replay), dtype=np.float32) / 255.0
                difference = np.abs(source_rgb - replay_rgb)
                report["metrics"] = {
                    "mae": float(difference.mean()),
                    "p95ChannelDiff": float(np.percentile(difference, 95)),
                    "p99ChannelDiff": float(np.percentile(difference, 99)),
                    "maxChannelDiff": float(difference.max()),
                    "fractionPixelsAnyChannelDiffOver2Of255": float(
                        np.mean(np.any(difference > (2.0 / 255.0), axis=2))),
                }
    except (OSError, ValueError) as error:
        report["error"] = str(error)
    (output_dir / "parity.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    if "error" in report:
        print(f"comparison unavailable: {report['error']}; see {output_dir / 'parity.json'}", file=sys.stderr)
        return 2
    print(f"comparison written: {output_dir / 'parity.json'}")
    return 0


def main(argv=None):
    args = parse_args(argv)
    input_dir = args.input.expanduser().resolve()
    output_dir = args.output.expanduser().resolve()
    derived_data = args.derived_data.expanduser().resolve()
    if not input_dir.is_dir():
        raise SystemExit(f"input directory does not exist: {input_dir}")
    output_dir.mkdir(parents=True, exist_ok=True)
    derived_data.mkdir(parents=True, exist_ok=True)
    for required in (input_dir / "source.capture", input_dir / "metadata.json"):
        if not required.is_file():
            print(f"input capture is incomplete; missing {required}", file=sys.stderr)
            return 2
    write_replay_command(output_dir, args, input_dir, derived_data)

    if not args.skip_build:
        build = ["xcodebuild", "-project", "FilmyCamera.xcodeproj", "-scheme", "FilmyCamera",
                 "-destination", f"platform=iOS Simulator,id={args.device}",
                 "-derivedDataPath", str(derived_data), "-parallel-testing-enabled", "NO",
                 "-maximum-parallel-testing-workers", "1", "CODE_SIGNING_ALLOWED=NO",
                 "CODE_SIGNING_REQUIRED=NO", "build-for-testing"]
        code = run_logged(build, output_dir / "build-for-testing.log")
        if code:
            print(f"build-for-testing failed ({code}); see {output_dir / 'build-for-testing.log'}", file=sys.stderr)
            return code

    try:
        run = xctestrun_path(derived_data)
        patch_xctestrun(run, input_dir, output_dir, args.variants)
    except (OSError, plistlib.InvalidFileException, RuntimeError) as error:
        print(f"cannot prepare xctestrun: {error}", file=sys.stderr)
        return 2

    test = ["xcodebuild", "test-without-building", "-xctestrun", str(run),
            "-destination", f"platform=iOS Simulator,id={args.device}",
            "-parallel-testing-enabled", "NO", "-maximum-parallel-testing-workers", "1",
            "-only-testing:" + TEST_ID]
    for name in ("render-info.json", "capture-replay.jpg"):
        stale = output_dir / name
        if stale.exists():
            stale.unlink()
    code = run_logged(test, output_dir / "test-without-building.log")
    if code:
        print(f"diagnostic replay failed ({code}); see {output_dir / 'test-without-building.log'}", file=sys.stderr)
        return code
    missing = [name for name in ("render-info.json", "capture-replay.jpg")
               if not (output_dir / name).is_file()]
    if missing:
        print(f"diagnostic replay produced no required output ({', '.join(missing)}); see {output_dir}", file=sys.stderr)
        return 2
    if args.compare:
        code = compare_images(input_dir, output_dir)
        if code:
            return code
    print(f"diagnostic replay passed; logs and captures: {output_dir}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        raise SystemExit(130)
