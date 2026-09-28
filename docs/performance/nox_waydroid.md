# Nox Waydroid performance harness

This harness measures Kite on the real Nox Waydroid device in Flutter profile mode. It does not use a production Matrix login.

## Fixture

`integration_test/performance/fixtures/real_chat_shape.json` is a deterministic anonymized snapshot derived from a real Kite presentation cache. It preserves structural pressure such as room counts, timeline sizes, event types, text lengths and line breaks, avatar presence, media dimensions, favourites, mute state, direct-room shape, and unread metadata.

The fixture contains no original Matrix room, user, or event IDs, server name, display names, message bodies, timestamps, URLs, or media. Images used by the local homeserver are generated synthetic PNGs.

To regenerate it on Glass from a local presentation cache:

```sh
python3 tool/perf/anonymize_kite_presentation.py   /path/to/presentation.json   integration_test/performance/fixtures/real_chat_shape.json
```

The anonymizer fails closed if source identifiers, server names, or private text values survive.

## Local Matrix replica

Nox already provides Synapse under `/opt/matrix/synapse-venv`. The runner creates a dedicated persistent server under `~/.local/state/kite-perf/synapse`, seeds the anonymized fixture once, and reuses it.

The test account is local-only and the Android performance build uses the isolated application ID `app.kite.perf`. Production Kite app data and production Matrix credentials are not touched. Push/notification setup is disabled in the performance harness so Android permission prompts cannot contaminate frame timings. The runner also disables Flutter DDS because Waydroid's forwarded VM Service needs a direct connection for timeline tracing.

If the committed fixture changes, the runner automatically rebuilds the dedicated Synapse state and clears `app.kite.perf` so stale access tokens cannot survive.

## One run

From the Kite checkout on Nox:

```sh
python3 tool/perf/run_nox_waydroid_soak.py --iterations 1
```

To explicitly rebuild the local replica and app session:

```sh
python3 tool/perf/run_nox_waydroid_soak.py   --iterations 1   --reset-fixture   --reset-app-data
```

## Overnight soak

Eight hours is the default:

```sh
python3 tool/perf/run_nox_waydroid_soak.py --hours 8
```

The runner holds the existing Kite Waydroid flock for the duration so other device jobs cannot contaminate frame timings.

Results are written to `~/.local/state/kite-perf/results/`. Each iteration produces a driver JSON result and log. `soak-summary.jsonl` appends the result, elapsed time, host load, and exit status for every iteration. Failed iterations also capture logcat and a Waydroid screenshot.

## Measured scenarios

The profile integration test currently records Flutter FrameTiming and GC summaries for:

- `chat_list_cold_scroll`
- `chat_list_warm_scroll`
- `chat_timeline_cold_scroll`
- `chat_timeline_warm_scroll`
- `settings_scroll_control`

New jitter cases should be added as named `watchPerformance` scenarios in `integration_test/performance_test.dart`. Keep the local fixture and test package stable so before and after results remain comparable.
