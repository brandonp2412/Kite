// SPDX-FileCopyrightText: 2026 Brandon Dick
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:developer';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kite/main.dart' as app;
import 'package:kite/pages/chat_list/chat_list_item.dart';

import 'utils/fling_metrics.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('fresh-process chat-list flings meet frame deadlines', (
    tester,
  ) async {
    expect(
      kProfileMode,
      isTrue,
      reason: 'Run on a physical device in profile mode',
    );
    final frames = <FrameTiming>[];
    void record(List<FrameTiming> batch) => frames.addAll(batch);
    binding.addTimingsCallback(record);
    addTearDown(() => binding.removeTimingsCallback(record));

    app.main([]);
    final list = find.byKey(const Key('chat_list_scroll'));
    final deadline = DateTime.now().add(const Duration(seconds: 60));
    while (list.evaluate().isEmpty ||
        find.byType(ChatListItem).evaluate().length < 3) {
      if (DateTime.now().isAfter(deadline)) {
        fail(
          'Signed-in chat list did not load. No login or account mutation is performed.',
        );
      }
      await tester.pump(const Duration(milliseconds: 16));
    }
    final position = tester
        .state<ScrollableState>(
          find.descendant(of: list, matching: find.byType(Scrollable)).first,
        )
        .position;
    expect(
      position.maxScrollExtent,
      greaterThan(500),
      reason: 'Need enough chats to fling',
    );
    final refreshRate = tester.view.display.refreshRate;
    expect(refreshRate, greaterThan(0));
    final budgetUs = 1000000 / refreshRate;
    final windows = <Map<String, Object>>[];
    final positions = <Map<String, num>>[];
    void recordPosition() =>
        positions.add({'ts_us': Timeline.now, 'pixels': position.pixels});
    position.addListener(recordPosition);
    addTearDown(() => position.removeListener(recordPosition));

    // No warmup scroll or pumpAndSettle before the first fling.
    for (var index = 0; index < 4; index++) {
      final start = Timeline.now;
      final before = position.pixels;
      await tester.fling(list, Offset(0, index.isEven ? -500 : 500), 2500);
      final release = Timeline.now;
      final timeout = DateTime.now().add(const Duration(seconds: 10));
      while (position.isScrollingNotifier.value) {
        if (DateTime.now().isAfter(timeout)) fail('Fling failed to settle');
        await tester.pump(const Duration(milliseconds: 8));
      }
      windows.add({
        'name': index == 0 ? 'cold_first_fling' : 'fling_${index + 1}',
        'start_us': start,
        'release_us': release,
        'end_us': Timeline.now,
        'distance': (position.pixels - before).abs(),
      });
      await tester.pump(const Duration(milliseconds: 250));
    }
    // FrameTiming batches can arrive up to a second after the rendered frame.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 2)),
    );
    final samples = frames
        .map(
          (frame) => <String, num>{
            'vsync_us': frame.timestampInMicroseconds(FramePhase.vsyncStart),
            'build_us': frame.buildDuration.inMicroseconds,
            'raster_us': frame.rasterDuration.inMicroseconds,
            'vsync_overhead_us': frame.vsyncOverhead.inMicroseconds,
          },
        )
        .toList();
    final reports = windows
        .map((window) => analyzeFling(samples, window, budgetUs))
        .toList();
    binding.reportData = {
      'schema_version': 2,
      'refresh_rate_hz': refreshRate,
      'budget_us': budgetUs,
      'flings': reports,
      'frames': samples,
      'scroll_positions': positions,
      'scope':
          'Fresh process, existing account and disk caches, no warmup scroll',
    };
    debugPrint('FLING_RESULTS: $reports');
    for (final report in reports) {
      expect(
        report['valid'],
        isTrue,
        reason: 'Insufficient motion/frame coverage: $report',
      );
      expect(report['slow_frames'], 0, reason: 'Missed frame budget: $report');
      expect(
        report['cadence_gap_count'],
        0,
        reason: 'Missing frames during ballistic scrolling: $report',
      );
    }
  });
}
