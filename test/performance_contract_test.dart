import 'package:flutter_test/flutter_test.dart';
import 'package:kite/benchmark/benchmark_fixture.dart';
import 'package:kite/benchmark/performance_contract.dart';

void main() {
  test('canonical message fixture is deterministic and generated per room', () {
    final kiteMessages = BenchmarkFixture.messagesFor('kite');
    final sameKiteMessages = BenchmarkFixture.messagesFor('kite');
    final aliceMessages = BenchmarkFixture.messagesFor('alice');

    expect(
      BenchmarkFixture.rooms,
      hasLength(PerformanceContract.fixtureRoomCount),
    );
    expect(kiteMessages, hasLength(PerformanceContract.fixtureMessagesPerRoom));
    expect(identical(kiteMessages, sameKiteMessages), isTrue);
    expect(identical(kiteMessages, aliceMessages), isFalse);
    expect(kiteMessages.first.id, 'kite-0');
    expect(kiteMessages.last.id, 'kite-99');
    expect(aliceMessages.first.id, 'alice-0');
  });

  test('zero-jitter performance contract is pinned', () {
    expect(PerformanceContract.fixtureRoomCount, 200);
    expect(PerformanceContract.fixtureMessagesPerRoom, 100);
    expect(PerformanceContract.roomListBenchmarkRoomCount, 3000);
    expect(PerformanceContract.timelineBenchmarkMessageCount, 1200);
    expect(PerformanceContract.paginationBenchmarkPageSize, 100);

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
