# Updated iPad compatibility — 2026-09-14

Status: implementation added; runtime and visual acceptance blocked by local Xcode build service. Do not describe this revision as device-tested or release-ready.

## Environment and scope

Connected iPad reports iPadOS 27.0 (24A437). Local Xcode is 26.6 (17F113), with iOS/iPadOS 26.5 SDK and iOS 26.5 simulators. SDK 27-specific API adoption requires a matching toolchain. Source baseline is c29688f plus the uncommitted changes below. SHA-256 over sorted app Swift paths and contents, NUL separated: `6c585e62f3698fc696f7e04e228c43f1e7d9216e4b8719ad4b902a0e9b826005`.

## Changes and existing support

- CameraService enables AVFoundation lens-smudge detection only when the active format supports it, under capture-session configuration. Detection runs at one-minute intervals. Observation is tied to the active camera and invalidated on graph reset/input changes. Unsupported devices retain normal capture behavior.
- CameraScreen displays a dismissible cleaning tip using existing adaptive glass styling. Save failures, save progress, and capture feedback take priority. A cleared detection resets dismissal. Runtime appearance of this conditional tip still needs supported hardware verification.
- Settings explains supported AirPods Camera Remote setup and the existing capture timer. The existing system capture-event handler receives AirPods shutter events; no accessory connection or audio-session changes were needed. Apple documents this behavior in [WWDC25 camera capture updates](https://developer.apple.com/videos/play/wwdc2025/253/).
- Existing Liquid Glass availability guards, accessibility appearance fallbacks, hardware shutter handling, iPad rotation, and camera-session multitasking configuration were reviewed. Review is not a runtime pass.

Apple's [iPadOS overview](https://www.apple.com/os/ipados/) and [iOS overview](https://www.apple.com/os/ios/) include broader windowing, Photos, and intelligence features. These are not all third-party Camera APIs; this revision does not claim to add Apple's Photos editing or Siri Camera capabilities.

## Windowing decision

Keep existing full-screen configuration for this revision. Enabling freely resizable windows also requires aligning scene orientation with the window-shaped preview, defining a minimum usable window size, making the side control column scroll in short windows, and bounding the look drawer in narrow windows. Portrait iPhone acceptance remains mandatory; native iPad checks supplement it.

## Verification and blocker

- Passed direct full-app Swift typecheck (all 29 current app Swift sources plus existing generated asset symbols), Swift 6, minimal strict concurrency, DEBUG, arm64 iOS 17 deployment target, installed iPhoneOS SDK. Evidence: `.ci/ipados27-20260914/full-typecheck/run-mql8kgno/result.json` (exit 0, 43.545 seconds). Existing Core Image deprecation warnings remain.
- Command: `python3 /Users/dheerajnamburu/.codex/scripts/run-with-evidence.py --log-dir .ci/ipados27-20260914/full-typecheck -- xcrun swiftc -typecheck -swift-version 6 -strict-concurrency=minimal -D DEBUG -target arm64-apple-ios17.0 -sdk /Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk -module-name FilmyCamera @build/release-build26-ipad/DeviceTestDerivedData/Build/Intermediates.noindex/FilmyCamera.build/Debug-iphoneos/FilmyCamera.build/Objects-normal/arm64/FilmyCamera.SwiftFileList`.
- Passed focused lens API typecheck and `git diff --check`. The compiler required Swift's `isCameraLensSmudgeDetectionSupported` and `isCameraLensSmudgeDetectionEnabled` names; Objective-C header spellings without `is` do not compile.
- Physical-device and simulator xcodebuild attempts stalled before compilation at `CreateBuildDescription`, in the external `clang -v -E -dM ... -x c -c /dev/null` probe. A serial retry and clean-environment retry reproduced the hang. Sampling showed clang waiting in a pipe write, with SWBBuildService idle. Direct execution of that compiler probe passed. Only this task's stalled builds were interrupted. Evidence directories: `.ci/ipados27-20260914/device-serial/`, `clean-env/`, `compiler/`. Interrupted builds are not passing evidence.

## Remaining acceptance

After fixing the toolchain, build and run the existing portrait iPhone UI acceptance (viewfinder, shutter, look picker, Pro controls/dismissal, largest Dynamic Type, Settings/gallery navigation), export screenshots and inspect them. Run physical iPad rotation, background/foreground recovery, tab round-trip, Pro controls, capture/save, timer cancellation and hardware shutter tests. Verify AirPods remote with supported paired hardware and the cleaning tip on a camera format reporting detection support. Do not reuse earlier iPadOS 26 results as iPadOS 27 acceptance.
