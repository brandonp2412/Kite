# Fresh-process chat-list fling regression

`integration_test/chat_list_fling_test.dart` measures the actual chat list on a
physical phone in **profile mode**, using the existing signed-in account. It
starts the first fling as soon as chat rows appear, without a warmup scroll or
`pumpAndSettle`, then measures three more flings through their full deceleration.

The JSON report contains every Flutter frame's build, raster and vsync scheduling
delay, timestamped scroll positions, and per-fling results. A single missed frame
budget or ballistic cadence gap fails the test. Frame cost alone cannot detect
a missing frame: two cheap frames can still be two refresh periods apart. The budget uses
the device's reported refresh rate (8.33 ms at 120 Hz, 16.67 ms at 60 Hz). UI work
plus scheduling delay and raster work are evaluated separately because these
pipeline stages overlap. The second half of post-release deceleration has its
own slow-frame count. Empty captures and insufficient scroll movement fail.

This is a fresh app process with existing disk caches, not a cleared-data or
first-install test. Flutter timings locate UI/raster delays; they do not measure
all downstream compositor/presentation delays. Timestamped positions are retained
to help investigate on-time layout jumps too. Repeat runs to assess variability.

## Run on the signed-in phone

Keep a normal release APK signed with the same key as the installed app available
for automatic restoration. Ensure the app opens its chat list and leave the phone
unlocked and untouched during the test. Build before installing:

```sh
ORG_GRADLE_PROJECT_kiteProfileWithReleaseKey=true flutter build apk \
  --profile --target-platform android-arm64 \
  --target integration_test/chat_list_fling_test.dart
python3 tool/perf/run_chat_list_fling.py --serial xxx \
  --restore-apk build/app/outputs/flutter-apk/app-release.apk
```

The runner uses `adb install -r` for both the profile test and restoration. It
never uninstalls or clears data, and stops on signing/version failures. It
force-stops and launches the test APK, attaches the driver to the existing VM
service (so Flutter does not install anything), saves JSON and logs under
`build/perf-results`, then restores the normal release even if the test fails.
Test logs may contain account metadata; keep them local.

The optional Gradle property affects only profile signing. It must not be set for
the separate `app.kite.perf` fixture harness. The original preview microbenchmark
does not exercise this UI or detect its jitter.

Validate the regression gate locally:

```sh
flutter test test/performance/fling_metrics_test.dart
python3 -m unittest discover -s test/performance -p 'test_*.py'
```

The runner checks the saved frame report as well as the driver's exit status.
Exit 1 indicates a failed frame budget or cadence gate; exit 2 indicates missing/invalid coverage.
This prevents a driver-level "All tests passed" message from hiding a failed
device-side test.

## Initial baseline (4 October 2026)

On the connected 120 Hz phone, the current app recorded 545 frames across four
flings. The first fling had one 13.029 ms raster frame; the second had one
9.025 ms UI frame in late deceleration, against an 8.333 ms budget. The remaining
two flings had no slow frames. All four had valid movement and frame coverage.
This is a failing baseline, not evidence that every run will reproduce the same
frames or that all visual jumps are explained by these timings.

## Avatar rendering fix (4 October 2026)

Avatars now opt out of `MxcImage` cross-fades. A zero `animationDuration`
builds the clipped image or placeholder directly, avoiding the cross-fade's
second child, animated size, and opacity work for each row entering the list.
Other images retain their default transition. Existing thumbnail decode bounds
and preview caching are preserved.

The same unmodified integration test reproduced a failure immediately before
this change on the SM-S931B at 120 Hz: 545 frames, one missed UI deadline
(8.642 ms). The first fresh-process run after the change captured 547 frames
across four flings with zero missed deadlines, including late deceleration;
worst UI time was 6.970 ms and worst raster time was 3.218 ms.
The consecutive repeat captured another 552 frames with zero missed deadlines
(worst UI 6.282 ms, raster 2.907 ms). Across both runs, all 1,099 measured frames
met the unchanged 8.333 ms budget. These captures demonstrate the regression
gate passing on this device; they do not guarantee every future frame deadline.

Local evidence (includes account metadata; not committed):

- Baseline: `build/perf-results/baseline/kite-perf-fresh-fling-20261004-111413.json`
- Fixed: `build/perf-results/avatar-static/kite-perf-fresh-fling-20261004-111609.json`
- Fixed repeat: `build/perf-results/avatar-static/kite-perf-fresh-fling-20261004-111643.json`

Eight focused Flutter tests pass, covering static placeholders, thumbnail
decoding, preview caching, hero lookup reuse, and the strict fling metric gate.
The three Python runner tests pass. Static analysis could not complete because
the configured analyzer plugin generates an invalid `dart_code_linter: latest`
version constraint.

## Cadence gate correction (4 October 2026)

The avatar-fix results above passed **only the old frame-cost gate**. They were
not evidence of uninterrupted scrolling. Replaying those same captures reveals
16.66–16.67 ms intervals between Flutter frames during active deceleration on the
120 Hz display, despite zero over-budget builds/rasters. Scroll positions around
these gaps also advance by approximately two frames of motion. For example, the
first fixed capture jumps from 1001.13 to 1027.44 logical pixels across a 16.665 ms
interval in its first fling.

The revised analyzer checks consecutive vsync timestamps after release and before
the final two refresh periods of settlement. The end guard excludes idle/boundary
frames, including a terminal gap seen in both archived runs. An interval greater
than 1.5 refresh periods fails; the half-period tolerance accommodates timestamp
rounding while detecting a skipped refresh. Reports include each gap's timestamps,
duration, estimated missed intervals, and a late-deceleration count. At least 20
ballistic frames are required. Schema version 2 is required by the runner, so old
reports without cadence coverage cannot silently pass.

With this guard, the previously passing fixed capture has **7 cadence gaps**
(per fling: 1, 2, 3, 1); its repeat has **2** (0, 1, 1, 0). Both fail the revised
gate. This is deterministic replay of observed irregular frame production, not a
promise that every new physical run will stutter identically. It does not measure
SurfaceFlinger presentation or detect all on-time row/layout jumps.

Replay local captures through the actual Dart analyzer:

```sh
KITE_FLING_REPLAY=build/perf-results/avatar-static/kite-perf-fresh-fling-20261004-111609.json \
  flutter test --no-pub test/performance/fling_metrics_test.dart \
  --plain-name 'replay saved capture'
```

The replay prints per-fling verdict inputs; its test success means the capture
was analyzed with valid coverage, not that the flings were smooth. Synthetic unit
tests independently verify that skipped refreshes fail even with 1 ms builds and
rasters, that continuous cadence passes, and that the refresh rate matters.

Timing-only, relative-timestamp extracts of both archived runs are checked into
`test/performance/fixtures/previously_passing_cadence.json`. The regression test
asserts the exact gap counts and zero slow frames for all eight recorded flings;
no account data is needed to reproduce the old gate's false passes.

A fresh physical SM-S931B run of the revised profile APK captured 543 frames with
valid coverage in all four flings and **5 cadence gaps** (0, 1, 3, 1), including
two in late deceleration. It also had three over-budget UI frames. The fourth
fling had zero slow frames but one cadence gap, demonstrating the additional
coverage live. The runner returned measurement exit code 1. Local report:
`build/perf-results/cadence-gate/kite-perf-fresh-fling-20261004-153752.json`.
Seven Dart regression tests and five Python runner tests pass.
