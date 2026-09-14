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
- Timeline performance journeys use a separate deterministic 1,200-message fixture spanning text, formatted, image, file, audio, poll, and location event shapes.
- Pagination adds a deterministic 100-event page; incoming-message insertion and reaction/read-receipt/typing updates are measured as independent mutation journeys.
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

`integration_test/open_dm_performance_test.dart` and `integration_test/release_journey_performance_test.dart` emit machine-readable frame data including refresh rate, frame budget, build/raster/total-span violations, worst timings, and raw per-frame timings. Release-journey output includes room-list scroll, composer keyboard, mixed rich timeline scroll, pagination, incoming-message insertion, and reaction/read-receipt/typing mutation records. Keep this output when investigating any failure.

The 2026-09-15 Waydroid profile-mode release-journey run used a 16,666 µs frame budget and recorded zero build, raster, and total-span violations for both new journeys. The 3,000-room scroll captured 117 frames with worst build/raster/total-span times of 4,959/2,831/6,661 µs. Composer keyboard appearance captured 7 frames with worst build/raster/total-span times of 3,365/2,152/6,366 µs. Waydroid still gates only build and raster timing as described above.

A later 2026-09-15 Waydroid profile run verified the new mutation benchmarks independently: pagination captured 1 frame at 1,099/1,623/3,209 µs worst build/raster/total-span, incoming-message insertion captured 1 frame at 3,290/1,920/6,050 µs, and 20 reaction/read-receipt/typing updates peaked at 1,204/1,787/3,410 µs. All three had zero build and raster budget violations. Mixed-rich timeline scrolling is intentionally still unchecked: the same run reproduced one first-scroll raster violation at 20,892 µs with a 16,666 µs budget. The benchmark threshold remains unchanged while that raster spike is investigated.

## Regression policy

Do not raise frame budgets, allow non-zero violations, reduce the number of benchmark iterations, disable the artificial-jitter negative control, or remove geometry checks merely to make a failing change pass. Fix the regression instead. Any intentional contract revision must be documented in the same change with the reason and before/after benchmark evidence.
