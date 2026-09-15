# Kite performance contract

Kite treats visible jitter as a correctness bug, not a polish issue.

The contract is pinned in `lib/benchmark/performance_contract.dart` and independently asserted by `test/performance_contract_test.dart`. Weakening a threshold therefore requires an explicit code change and an explicit pin-test change.

## Required invariants

- Opening a user chat must produce zero Flutter build-frame budget violations.
- Opening a user chat must produce zero Flutter raster-frame budget violations.
- On physical Android hardware, opening a user chat must produce zero end-to-end frame-budget violations.
- On Waydroid, end-to-end `totalSpan` is recorded but is not a merge gate because host/compositor scheduling is outside Kite; build and raster budgets remain strict zero-violation gates.
- The deterministic 120 Hz motion test must produce zero unintended geometry movement in the sidebar, chat panel, message list, and composer.
- The canonical fixture stays at 200 rooms and 100 messages per room unless this contract and its pin test are deliberately revised.
- The dedicated room-list scroll benchmark uses a separate deterministic 3,000-room fixture; it must not replace or silently resize the canonical 200-room fixture.
- The canonical warm-switch benchmark remains 30 chat opens.
- The benchmark detector must prove itself by failing when the 40 ms artificial build stall is enabled.

## Required command before marking roadmap work complete

```sh
tool/quality_gate.sh
```

The quality gate performs `flutter analyze`, the deterministic Flutter tests, and the Waydroid positive/negative/positive jitter sequence.

The expected jitter-harness sequence is:

```text
clean benchmark      PASS
40 ms injected stall FAIL
clean benchmark      PASS
```

A benchmark that cannot detect the injected fault is itself considered broken.

## Authoritative physical-device gate

Waydroid is the continuous regression detector. Release candidates must additionally run the Android Macrobenchmark on fixed physical hardware. A physical-device result is authoritative for end-to-end presentation timing; Waydroid results are not used to claim real-device jank freedom.

## Evidence format

`integration_test/open_dm_performance_test.dart` and `integration_test/release_journey_performance_test.dart` emit machine-readable frame data including refresh rate, frame budget, build/raster/total-span violations, worst timings, and raw per-frame timings. Keep this output when investigating any failure.

The 2026-09-15 Waydroid profile-mode release-journey run used a 16,666 µs frame budget and recorded zero build, raster, and total-span violations for both new journeys. The 3,000-room scroll captured 117 frames with worst build/raster/total-span times of 4,959/2,831/6,661 µs. Composer keyboard appearance captured 7 frames with worst build/raster/total-span times of 3,365/2,152/6,366 µs. Waydroid still gates only build and raster timing as described above.

A later same-day profile-mode media-viewer run on Glass Waydroid exposed a real open Milestone 15 blocker rather than being waived. At a 16,666 µs budget, cold full-screen open had 3 raster-budget violations across 4 sampled frames with a 155,099 µs worst raster frame; flick-to-dismiss had 3/3 violations with a 57,810 µs worst raster frame; adjacent-media swipe had 30 violations across 59 frames with a 28,716 µs worst raster frame. `performance_benchmark_harness.dart` now includes violation count, worst timing, and sample count in failure diagnostics.

After the 2026-09-15 media-viewer visual-parity simplification, the same profile-mode Waydroid test was rerun before accepting the visual change as performance-neutral. It still fails the unchanged zero-violation contract: full-screen open recorded 4/4 raster violations with a 132,789 µs worst frame, flick-to-dismiss recorded 3/3 with a 58,494 µs worst frame, and adjacent-media swipe recorded 31/60 with a 20,759 µs worst frame. The lower worst open/swipe times do not make the journey acceptable because every raster violation remains a gate failure. The media-viewer benchmark stays unchecked; no threshold, sample count, or gate was relaxed.

A dedicated `timeline_mutation_performance_test.dart` now covers the first new-message insertion and deterministic send settlement with the same strict profile-mode harness. Its first Waydroid run caught 1 raster-budget violation across 2 sampled frames, worst 19,240 µs, so the Milestone 15 new-message-insertion box remains open.

`room_members_performance_test.dart` now adds deterministic 200-member search/filter coverage alongside the existing member-list scroll journey. On Glass Waydroid the unchanged 16,666 µs raster gate rejected both journeys: the baseline scroll recorded 13 violations across 78 frames with a 20,803 µs worst raster frame, while search/filter recorded 3 violations across 3 frames with a 19,215 µs worst raster frame. A render-tree isolation experiment improved the search sample to 1/3 violations at 18,648 µs but worsened scrolling to 27/78 at 21,700 µs, so that experiment was reverted and no performance checkbox was closed.

A native Android cold-start Macrobenchmark now uses `StartupTimingMetric`, `StartupMode.COLD`, full compilation and ten iterations against an isolated `nz.presley.kite.benchmark` build. The benchmark target and instrumentation are now aligned on debug signing: the module compiles, installs, launches Kite and begins Perfetto capture on Glass Waydroid. The first iteration cannot produce accepted timing evidence there, however: Android accessibility never exposes the expected `Chats` node within the five-second readiness window, and the Waydroid trace environment then reports unsupported external-storage attributes plus a missing `su` command before the guarded run is aborted. The startup item therefore remains open; no timing result is claimed from this virtualized run, and the physical-device Macrobenchmark remains the authoritative release gate.

## Regression policy

Do not raise frame budgets, allow non-zero violations, reduce the number of benchmark iterations, disable the artificial-jitter negative control, or remove geometry checks merely to make a failing change pass. Fix the regression instead. Any intentional contract revision must be documented in the same change with the reason and before/after benchmark evidence.
