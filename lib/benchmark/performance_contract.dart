abstract final class PerformanceContract {
  static const int fixtureRoomCount = 200;
  static const int fixtureMessagesPerRoom = 100;
  static const int roomListBenchmarkRoomCount = 3000;

  static const double motionRefreshRateHz = 120;
  static const Duration motionFrame = Duration(microseconds: 8333);
  static const int motionSamples = 24;

  static const int warmChatOpenIterations = 30;
  static const int maxBuildBudgetViolations = 0;
  static const int maxRasterBudgetViolations = 0;
  static const int maxTotalSpanBudgetViolations = 0;

  static const Duration artificialJitterDelay = Duration(milliseconds: 40);

  static const bool gateVirtualizedTotalSpan = false;
  static const bool gatePhysicalTotalSpan = true;
}
