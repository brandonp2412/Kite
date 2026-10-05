import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/utils/fling_metrics.dart';

void main() {
  final window = <String, Object>{
    'start_us': 1000,
    'release_us': 1000,
    'end_us': 210000,
    'distance': 500.0,
  };
  List<Map<String, num>> frames() => List.generate(
    25,
    (i) => {
      'vsync_us': 1000 + i * 8333,
      'build_us': 1000,
      'raster_us': 1000,
      'vsync_overhead_us': 0,
    },
  );
  test('one mild late-deceleration hitch fails at 120Hz', () {
    final data = frames();
    data[16]['build_us'] = 9000;
    final result = analyzeFling(data, window, 1000000 / 120);
    expect(result['valid'], true);
    expect(result['slow_frames'], 1);
    expect(result['late_deceleration_slow_frames'], 1);
    expect(analyzeFling(data, window, 1000000 / 60)['slow_frames'], 0);
  });
  test('counts scheduling stalls and raster stalls', () {
    final data = frames();
    data[4]['vsync_overhead_us'] = 9000;
    data[16]['raster_us'] = 9000;
    expect(analyzeFling(data, window, 8333)['slow_frames'], 2);
  });
  test('ignores startup frames and rejects empty captures', () {
    final data = frames()
      ..insert(0, {
        'vsync_us': 0,
        'build_us': 50000,
        'raster_us': 1000,
        'vsync_overhead_us': 0,
      });
    expect(analyzeFling(data, window, 8333)['slow_frames'], 0);
    expect(analyzeFling([], window, 8333)['valid'], false);
    expect(
      analyzeFling(frames(), {...window, 'distance': 0}, 8333)['valid'],
      false,
    );
  });
  test('cheap frames still fail when a refresh is skipped', () {
    final data = List.generate(
      50,
      (i) => <String, num>{
        'vsync_us': 1000 + (i + (i >= 30 ? 1 : 0)) * 8333,
        'build_us': 1000,
        'raster_us': 1000,
        'vsync_overhead_us': 0,
      },
    );
    final realisticWindow = <String, Object>{
      'start_us': 1000,
      'release_us': 9000,
      'end_us': 430000,
      'distance': 500.0,
    };
    final result = analyzeFling(data, realisticWindow, 1000000 / 120);
    expect(result['valid'], true);
    expect(result['slow_frames'], 0);
    expect(result['cadence_gap_count'], 1);
    expect(result['missed_intervals'], 1);
    expect(result['late_deceleration_cadence_gaps'], 1);
    expect(
      analyzeFling(data, realisticWindow, 1000000 / 60)['cadence_gap_count'],
      0,
    );
    // The same quick frames at a continuous cadence must pass.
    for (var i = 0; i < data.length; i++) {
      data[i]['vsync_us'] = 1000 + i * 8333;
    }
    expect(
      analyzeFling(data, realisticWindow, 1000000 / 120)['cadence_gap_count'],
      0,
    );
  });
  test('does not count pauses outside ballistic scrolling', () {
    final data = frames();
    data[0]['vsync_us'] = -100000;
    expect(analyzeFling(data, window, 8333)['cadence_gap_count'], 0);
  });

  test('ignores a terminal gap after the final moving frame', () {
    final data = frames();
    data.last['vsync_us'] = data[data.length - 2]['vsync_us']! + 16666;
    final end = data.last['vsync_us']!.toInt() + 1000;
    final result = analyzeFling(data, {...window, 'end_us': end}, 8333);
    expect(result['valid'], true);
    expect(result['cadence_gap_count'], 0);
  });

  test('previously passing device captures expose cadence gaps', () {
    final fixtures =
        jsonDecode(
              File(
                'test/performance/fixtures/previously_passing_cadence.json',
              ).readAsStringSync(),
            )
            as List;
    for (final fixture in fixtures) {
      final samples = (fixture['frames'] as List)
          .map(
            (f) => <String, num>{
              'vsync_us': f[0] as num,
              'build_us': f[1] as num,
              'raster_us': f[2] as num,
              'vsync_overhead_us': f[3] as num,
            },
          )
          .toList();
      final result = analyzeFling(samples, <String, Object>{
        'start_us': 0,
        'release_us': fixture['release_us'] as int,
        'end_us': fixture['end_us'] as int,
        'distance': fixture['distance'] as num,
      }, (fixture['budget_us'] as num).toDouble());
      expect(result['valid'], true);
      expect(result['slow_frames'], 0);
      expect(
        result['cadence_gap_count'],
        fixture['expected_gaps'],
        reason: "${fixture['capture']} ${fixture['name']}",
      );
    }
  });

  // Optional replay uses the production analyzer, not a second implementation.
  // Account-bearing captures stay local; synthetic coverage above runs in CI.
  final replayPath = Platform.environment['KITE_FLING_REPLAY'];
  if (replayPath != null) {
    test('replay saved capture through the current cadence gate', () {
      final report = jsonDecode(File(replayPath).readAsStringSync()) as Map;
      final samples = (report['frames'] as List)
          .map((f) => Map<String, num>.from(f as Map))
          .toList();
      final results = (report['flings'] as List)
          .map(
            (w) => analyzeFling(
              samples,
              Map<String, Object>.from(w as Map),
              (report['budget_us'] as num).toDouble(),
            ),
          )
          .toList();
      expect(results, hasLength(4));
      for (final result in results) {
        expect(result['valid'], true);
      }
      // A replay is diagnostic: print the verdict without assuming the input
      // must be either smooth or jittery.
      stdout.writeln(jsonEncode(results));
    });
  }
}
