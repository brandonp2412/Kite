<p align="center">
  <img src="assets/branding/kite-logo.svg" alt="Kite" width="720" />
</p>

<p align="center">
  A Flutter Matrix client targeting Element X feature parity, equal visual polish, and a stricter zero-jitter performance contract.
</p>

<p align="center">
  <strong>Matrix, without the jitter.</strong>
</p>

---

## What Kite is

Kite is an open-source Matrix client built in Flutter. The product target is straightforward: reach current Element X feature parity, look equally intentional and polished, and reject interaction jitter as a correctness bug rather than accepting it as UI polish debt.

Kite is early-stage. The current repository contains the architectural foundation, deterministic UI fixture, Signals-based state model, zero-jitter benchmark harness, Android Macrobenchmark target, and the full parity roadmap.

## Core principles

- **Signals** for state management.
- No Riverpod.
- No `go_router`; navigation stays explicit and lightweight.
- Matrix interoperability and audited SDK cryptography rather than custom cryptography.
- Offline-first rendering and narrow reactive rebuilds.
- No visible loading-induced layout shift.
- UI work is incomplete until it satisfies the visual-quality contract.
- Performance regressions fail tests instead of becoming accepted baselines.

## Zero-jitter contract

Kite pins its interaction performance requirements in code and tests. The canonical user-chat benchmark uses a deterministic fixture of 200 rooms and 100 messages per room, then measures a cold DM open and 30 warm room switches.

The Waydroid regression gate requires zero Flutter build-budget violations and zero raster-budget violations. Physical-device release candidates additionally require zero end-to-end frame-budget violations. A deterministic 120 Hz geometry test checks that the sidebar, chat panel, message list, and composer do not move unexpectedly.

The benchmark also contains a deliberate 40 ms fault injector. The harness is considered valid only when the same benchmark sequence produces:

```text
clean benchmark      PASS
40 ms injected stall FAIL
clean benchmark      PASS
```

Run the complete local gate with Waydroid available through ADB:

```sh
tool/quality_gate.sh
```

See [PERFORMANCE.md](PERFORMANCE.md) for the pinned contract and regression policy.

## Roadmap

The goal is current Element X parity or better, not a historical Element Classic clone. The roadmap covers Matrix sync/storage, authentication and E2EE, Spaces, Threads, rich timeline rendering, composer workflows, media, polls, live location, MatrixRTC calling, moderation, notifications, adaptive layouts, accessibility, and a dedicated visual-parity audit.

See [ROADMAP.md](ROADMAP.md).

## Visual standard

Kite should look deliberately designed next to Element X, not like a generic Flutter approximation. The roadmap treats design tokens, golden tests, responsive layouts, typography hierarchy, avatar/media quality, motion, light/dark/black themes, and side-by-side visual review as first-class product work.

See [VISUAL_PARITY.md](VISUAL_PARITY.md) for the pinned upstream reference commit, rendered comparison checklist, and current parity matrix.

The kite mark in this repository is original Kite branding and is not derived from Element trademarks or assets.

## Development

Requirements:

- Flutter stable
- Android SDK for Android builds
- Waydroid or another Android target for continuous performance regression testing
- A physical Android device for authoritative release-candidate frame timing

Useful commands:

```sh
flutter analyze
flutter test
tool/verify_jitter_harness.sh
tool/quality_gate.sh
```

Any other Waydroid-targeted performance run must share the same per-device lock:

```sh
device="$(adb devices -l | awk '/model:WayDroid/{print $1; exit}')"
tool/with_waydroid_lock.sh --device "$device" -- flutter drive --profile --no-dds \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/release_journey_performance_test.dart \
  -d "$device"
```

## Current status

Foundation work is active. Milestone 0 establishes reproducible quality gates before Matrix feature work begins. The detailed checkbox state lives in [ROADMAP.md](ROADMAP.md).
