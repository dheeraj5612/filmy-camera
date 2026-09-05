# Runtime and CI efficiency — September 4, 2026

## Changes

- Release the camera after 8 seconds in Roll, Settings, or a foreground import, instead of retaining it for 45 seconds. Review retains its 45-second Retake window. Backgrounding still stops capture immediately. Filter math, preview resolution, and saved-image resolution are unchanged.
- Compile both XCTest bundles once with `build-for-testing`; execute unit and UI suites with `test-without-building` using the same destination and DerivedData. Start simulator boot before compilation and await readiness before tests.
- Skip the hardware-only Retake test immediately on Simulator. Previously it waited 20 seconds for a shutter that cannot exist; physical-device runs still exercise all three Retake cycles and now fail if the camera cannot start.
- Preserve all three required checks. Run release validation on macOS when its inputs change; use a lightweight Ubuntu success check when they do not. Credential scanning still runs on every workflow invocation.
- Retain logs and source provenance for 14 days. Upload large XCTest result bundles only for failures, retaining them for 7 days.

## Cost evidence

The repository is public and uses standard GitHub-hosted runners. Their execution is free under [GitHub's published billing policy](https://docs.github.com/en/billing/concepts/product-billing/github-actions). These changes reduce repeated work and stored diagnostics; they do not establish a reduction in the account's bill.

Before this pass, the repository held 563 unexpired Actions artifacts totaling 2,186,377,551 bytes (2.04 GiB), plus approximately 61 MiB of dependency caches. Historical artifacts were retained. Successful run [33933713759](https://github.com/dheeraj5612/filmy-camera/actions/runs/33933713759) uploaded a 19,064,624-byte XCTest bundle even though the step was named “on failure.” Its build job took 12 minutes 8 seconds, including 2 minutes 41 seconds waiting for simulator selection/boot before compiling. These are baseline observations, not a guaranteed future timing reduction.

The app's capture, filtering, and photo storage paths use native on-device frameworks. This pass adds no backend, paid API, or hosted processing dependency. A shorter camera grace period reduces the time hardware remains active after leaving the viewfinder; battery percentage and dollar savings have not been measured.

## Validation

- `actionlint`, ShellCheck, Bash syntax, and whitespace validation passed. The portable credential scanner accepted a clean Git fixture, rejected a synthetic key header without revealing it, and passed against this checkout.
- Physical iPad acceptance passed for background/foreground recovery, G7 X capture/save/Roll/detail/share, repeated Retake, and quick Roll/Settings return. The rapid-look-switching test was interrupted by the system AssistiveTouch menu; its screenshot identifies the overlay. This is not counted as a passed test.
- Hosted unit/UI execution and any subsequent device evidence are attached to the change's pull request. Actual battery drain and live-preview frame pacing remain unmeasured.
