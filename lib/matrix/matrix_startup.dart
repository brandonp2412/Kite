import 'dart:async';

import 'package:kite/matrix/matrix_deep_link.dart';

typedef MatrixSessionRestore = Future<void> Function();
typedef MatrixDeepLinkDispatch = FutureOr<void> Function(MatrixDeepLink link);

/// Orders process/session restoration ahead of launch and warm deep links.
///
/// Android can deliver a launch intent before the restored Matrix session has
/// settled. Keeping inbound links here prevents default startup navigation from
/// clobbering that intent. Once restoration succeeds, queued links are drained
/// in arrival order; warm links dispatch immediately through the same path.
final class MatrixStartupCoordinator {
  MatrixStartupCoordinator({
    required this.restoreSession,
    required this.dispatchDeepLink,
  });

  final MatrixSessionRestore restoreSession;
  final MatrixDeepLinkDispatch dispatchDeepLink;

  final List<MatrixDeepLink> _pendingLinks = <MatrixDeepLink>[];
  Future<void>? _startup;
  bool _ready = false;

  bool get isReady => _ready;
  int get pendingLinkCount => _pendingLinks.length;

  Future<bool> submitDeepLink(String raw) async {
    final link = MatrixDeepLinkParser.parse(raw);
    if (link == null) return false;

    if (!_ready) {
      _pendingLinks.add(link);
      return true;
    }

    await dispatchDeepLink(link);
    return true;
  }

  Future<void> start() {
    final active = _startup;
    if (active != null) return active;
    if (_ready) return Future<void>.value();

    final startup = _restoreAndDrain();
    _startup = startup;
    return startup.whenComplete(() {
      if (identical(_startup, startup)) {
        _startup = null;
      }
    });
  }

  Future<void> _restoreAndDrain() async {
    await restoreSession();
    _ready = true;

    while (_pendingLinks.isNotEmpty) {
      final link = _pendingLinks.removeAt(0);
      await dispatchDeepLink(link);
    }
  }
}
