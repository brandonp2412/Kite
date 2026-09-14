import 'package:flutter_test/flutter_test.dart';
import 'package:kite/benchmark/performance_contract.dart';

void main() {
  test('zero-jitter performance contract is pinned', () {
    expect(PerformanceContract.fixtureRoomCount, 200);
    expect(PerformanceContract.fixtureMessagesPerRoom, 100);

    expect(PerformanceContract.motionRefreshRateHz, 120);
    expect(PerformanceContract.motionFrame, const Duration(microseconds: 8333));
    expect(PerformanceContract.motionSamples, 24);

    expect(PerformanceContract.warmChatOpenIterations, 30);
    expect(PerformanceContract.maxBuildBudgetViolations, 0);
    expect(PerformanceContract.maxRasterBudgetViolations, 0);
    expect(PerformanceContract.maxTotalSpanBudgetViolations, 0);

    expect(
      PerformanceContract.artificialJitterDelay,
      const Duration(milliseconds: 40),
    );

    expect(PerformanceContract.gateVirtualizedTotalSpan, isFalse);
    expect(PerformanceContract.gatePhysicalTotalSpan, isTrue);
  });
}
