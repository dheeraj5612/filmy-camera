#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BUILD=$(mktemp -d)
trap 'rm -rf "$BUILD"' EXIT
swiftc "$ROOT/FilmyCamera/CaptureModes/CaptureMode.swift" "$ROOT/scripts/capture-modes-policy/main.swift" -o "$BUILD/policy-tests"
"$BUILD/policy-tests"
