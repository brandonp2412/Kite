// SPDX-FileCopyrightText: 2026 Brandon Dick
// SPDX-License-Identifier: AGPL-3.0-or-later

Map<String, Object> analyzeFling(
  List<Map<String, num>> frames,
  Map<String, Object> window,
  double budgetUs,
) {
  final start = window['start_us'] as int;
  final release = window['release_us'] as int;
  final end = window['end_us'] as int;
  final selected = frames
      .where((f) => f['vsync_us']! >= start && f['vsync_us']! < end)
      .toList();
  // Only compare adjacent frames inside the ballistic interval. The release
  // boundary and final idle frame are not guaranteed to request a new frame.
  // Exclude two refresh periods at settlement: the polling observation of
  // isScrolling=false can lag the final moving frame.
  final ballistic =
      selected
          .where(
            (f) =>
                f['vsync_us']! >= release &&
                f['vsync_us']! < end - 2 * budgetUs,
          )
          .toList()
        ..sort((a, b) => a['vsync_us']!.compareTo(b['vsync_us']!));
  final gaps = <Map<String, num>>[];
  for (var i = 1; i < ballistic.length; i++) {
    final previous = ballistic[i - 1]['vsync_us']!;
    final current = ballistic[i]['vsync_us']!;
    final interval = current - previous;
    // Half a refresh tolerates timestamp rounding, but catches a skipped vsync.
    if (interval > budgetUs * 1.5) {
      gaps.add({
        'previous_vsync_us': previous,
        'vsync_us': current,
        'interval_us': interval,
        'missed_intervals': (interval / budgetUs).round() - 1,
      });
    }
  }
  final lateStart = release + ((end - release) * .5).round();
  // UI scheduling delay matters too: a brief blocked isolate may produce a
  // quick build after missing its intended vsync. Pipeline stages overlap,
  // so totalSpan alone is not a valid one-frame regression threshold.
  final slow = selected
      .where(
        (f) =>
            f['build_us']! + f['vsync_overhead_us']! > budgetUs ||
            f['raster_us']! > budgetUs,
      )
      .toList();
  return {
    ...window,
    'valid':
        selected.length >= 20 &&
        ballistic.length >= 20 &&
        (window['distance'] as num) > 100,
    'cadence_gaps': gaps,
    'cadence_gap_count': gaps.length,
    'missed_intervals': gaps.fold<num>(
      0,
      (total, gap) => total + gap['missed_intervals']!,
    ),
    'late_deceleration_cadence_gaps': gaps
        .where((gap) => gap['previous_vsync_us']! >= lateStart)
        .length,
    'frames': selected.length,
    'slow_frames': slow.length,
    'late_deceleration_slow_frames': slow
        .where((f) => f['vsync_us']! >= lateStart)
        .length,
    'worst_ui_ms':
        selected.fold<num>(
          0,
          (v, f) => v > f['build_us']! + f['vsync_overhead_us']!
              ? v
              : f['build_us']! + f['vsync_overhead_us']!,
        ) /
        1000,
    'worst_raster_ms':
        selected.fold<num>(
          0,
          (v, f) => v > f['raster_us']! ? v : f['raster_us']!,
        ) /
        1000,
  };
}
