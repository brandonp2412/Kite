`previously_passing_cadence.json` contains timing-only extracts from the two
4 October 2026 avatar-static captures documented in
`docs/performance/android_chat_fling.md`. No account metadata or row content is
included. Timestamps are relative to each fling's start.

Each frame tuple is `[vsync_us, build_us, raster_us, vsync_overhead_us]`.
All frames passed the original cost gate. Expected cadence-gap counts exclude
the final two refresh periods to avoid counting settlement as a scrolling gap.
The fixture tests run the production analyzer and lock in the observed false
negative: seven gaps in capture 111609 and two in capture 111643.
