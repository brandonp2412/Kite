import 'package:flutter/material.dart';
import 'package:kite/benchmark/performance_contract.dart';
import 'package:kite/matrix/matrix_models.dart';
import 'package:kite/matrix/presentation_cache.dart';
import 'package:signals/signals_flutter.dart';

final class OfflineRecoveryBenchmarkController {
  OfflineRecoveryBenchmarkController()
    : cache = MatrixPresentationCache(
        initialSnapshot: MatrixPresentationSnapshot(rooms: _cachedRooms),
      );

  static const int changedRoomCount = 20;

  final MatrixPresentationCache cache;
  final Signal<bool> isOnline = signal<bool>(false);

  void recover() {
    cache.applySync(
      MatrixSyncBatch(
        cursor: 'recovered-sync-1',
        rooms: List<MatrixRoomDelta>.generate(changedRoomCount, (index) {
          final streamPosition = PerformanceContract.fixtureRoomCount - index;
          return MatrixRoomDelta(
            roomId: '!benchmark-${index.toString().padLeft(4, '0')}:kite.test',
            summary: MatrixRoomSummary(
              roomId:
                  '!benchmark-${index.toString().padLeft(4, '0')}:kite.test',
              displayName: 'Cached room ${index + 1}',
              lastActivity: DateTime.utc(
                2026,
                9,
                15,
              ).subtract(Duration(minutes: index)),
              streamPosition: streamPosition,
              lastEventId: r'$cached-' + index.toString(),
              unreadCount: 2,
            ),
          );
        }),
      ),
    );
    isOnline.value = true;
  }

  void dispose() => isOnline.dispose();

  static final List<MatrixRoomSummary> _cachedRooms =
      List<MatrixRoomSummary>.unmodifiable(
        List<MatrixRoomSummary>.generate(
          PerformanceContract.fixtureRoomCount,
          (index) => MatrixRoomSummary(
            roomId: '!benchmark-${index.toString().padLeft(4, '0')}:kite.test',
            displayName: 'Cached room ${index + 1}',
            lastActivity: DateTime.utc(
              2026,
              9,
              15,
            ).subtract(Duration(minutes: index)),
            streamPosition: PerformanceContract.fixtureRoomCount - index,
            lastEventId: r'$cached-' + index.toString(),
            unreadCount: index.isEven ? 1 : 0,
          ),
        ),
      );
}

class OfflineRecoveryBenchmarkSurface extends StatelessWidget {
  const OfflineRecoveryBenchmarkSurface({required this.controller, super.key});

  final OfflineRecoveryBenchmarkController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: <Widget>[
            SizedBox(
              height: 56,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: <Widget>[
                    const Expanded(
                      child: Text(
                        'Cached rooms',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    SizedBox(
                      width: 108,
                      child: SignalBuilder(
                        builder: (context) {
                          final online = controller.isOnline.value;
                          return Text(
                            online ? 'Back online' : 'Offline cache',
                            key: const Key('offline-recovery-status'),
                            textAlign: TextAlign.end,
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: SignalBuilder(
                builder: (context) {
                  final roomIds = controller.cache.roomOrder.value;
                  return ListView.builder(
                    key: const Key('offline-recovery-room-list'),
                    itemExtent: 56,
                    itemCount: roomIds.length,
                    itemBuilder: (context, index) {
                      final roomId = roomIds[index];
                      return SignalBuilder(
                        key: Key('offline-recovery-room-$roomId'),
                        builder: (context) {
                          final room = controller.cache
                              .roomSummarySignal(roomId)
                              .value;
                          if (room == null) return const SizedBox.shrink();
                          return ListTile(
                            dense: true,
                            minVerticalPadding: 0,
                            title: Text(
                              room.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: SizedBox(
                              width: 32,
                              child: Text(
                                '${room.unreadCount}',
                                textAlign: TextAlign.end,
                              ),
                            ),
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
