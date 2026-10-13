#!/usr/bin/env bash
# Runs the real hardware-independent Swift controller tests on Linux or macOS.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/Sources/SceneAutoCore" "$work/Tests/SceneAutoCoreTests"
cp "$root/FilmyCamera/Models/SceneAutoPolicy.swift" "$work/Sources/SceneAutoCore/"
cp "$root/FilmyCameraTests/SceneAutoPolicyTests.swift" "$work/Tests/SceneAutoCoreTests/"
cat > "$work/Package.swift" <<'SWIFT'
// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "SceneAutoCore", targets: [
    .target(name: "SceneAutoCore"),
    .testTarget(name: "SceneAutoCoreTests", dependencies: ["SceneAutoCore"])
])
SWIFT
expected="$(grep -cE 'func[[:space:]]+test[A-Za-z0-9_]*[[:space:]]*\(' "$work/Tests/SceneAutoCoreTests/SceneAutoPolicyTests.swift" || true)"
[[ "$expected" -gt 0 ]] || { echo 'No tests found' >&2; exit 1; }
log="$work/swift-test.log"
swift test --package-path "$work" -j 2 2>&1 | tee "$log"
grep -Fq "Executed ${expected} tests, with 0 failures" "$log" || { echo "Expected ${expected} executed tests" >&2; exit 1; }
