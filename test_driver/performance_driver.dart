import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final resultDir =
      Platform.environment['KITE_PERF_RESULT_DIR'] ?? 'build/perf-results';
  final runId =
      Platform.environment['KITE_PERF_RUN_ID'] ??
      DateTime.now().toUtc().toIso8601String().replaceAll(':', '-');

  await integrationDriver(
    writeResponseOnFailure: true,
    responseDataCallback: (data) => writeResponseData(
      data,
      testOutputFilename: 'kite-perf-$runId',
      destinationDirectory: resultDir,
    ),
  );
}
