# Kite agent rules

## Shared Waydroid benchmark device

Waydroid performance results are valid only when one Kite process owns the device for the full install/run cycle. Required benchmarks must still run; locking serializes them and is not a reason to skip them.

- Run every Waydroid-targeted `flutter drive`, Android performance test, benchmark install, or benchmark launch through `tool/with_waydroid_lock.sh -- ...`.
- Do not install or launch `nz.presley.kite` on Waydroid directly while another benchmark may be running.
- `tool/quality_gate.sh` and `tool/verify_jitter_harness.sh` already acquire this lock; do not wrap them a second time.
- Never weaken frame thresholds because a contended Waydroid run failed. First rerun with exclusive device ownership.
