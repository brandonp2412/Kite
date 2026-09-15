import 'package:kite/features/calls/call_deep_link_coordinator.dart';
import 'package:kite/features/calls/call_session.dart';
import 'package:kite/features/navigation/app_destination.dart';
import 'package:kite/matrix/matrix_navigation.dart';

abstract interface class MatrixCallDeepLinkResolverPort {
  Future<MatrixRtcSessionDescriptor?> resolveActiveCall({
    required String accountId,
    required String roomIdOrAlias,
  });
}

enum MatrixCallDeepLinkResult {
  notCallTarget,
  noActiveCall,
  superseded,
  opened,
}

final class MatrixCallDeepLinkCoordinator {
  factory MatrixCallDeepLinkCoordinator({
    required AccountActivationPort accounts,
    required MatrixCallDeepLinkResolverPort resolver,
    required CallDeepLinkCoordinator calls,
  }) => MatrixCallDeepLinkCoordinator._(accounts, resolver, calls);

  MatrixCallDeepLinkCoordinator._(this._accounts, this._resolver, this._calls);

  final AccountActivationPort _accounts;
  final MatrixCallDeepLinkResolverPort _resolver;
  final CallDeepLinkCoordinator _calls;
  int _openGeneration = 0;

  Future<MatrixCallDeepLinkResult> open(MatrixNavigationTarget target) async {
    final generation = ++_openGeneration;
    if (target.kind != MatrixNavigationKind.call) {
      return MatrixCallDeepLinkResult.notCallTarget;
    }
    final accountId = _accounts.activeAccountId;
    if (accountId == null) {
      throw StateError('Call deep links require an active Matrix account.');
    }
    final roomIdOrAlias = target.roomIdOrAlias;
    if (roomIdOrAlias == null || roomIdOrAlias.isEmpty) {
      throw StateError('Call deep links require a Matrix room target.');
    }

    final descriptor = await _resolver.resolveActiveCall(
      accountId: accountId,
      roomIdOrAlias: roomIdOrAlias,
    );
    if (generation != _openGeneration ||
        _accounts.activeAccountId != accountId) {
      return MatrixCallDeepLinkResult.superseded;
    }
    if (descriptor == null) return MatrixCallDeepLinkResult.noActiveCall;
    if (roomIdOrAlias.startsWith('!') && descriptor.roomId != roomIdOrAlias) {
      throw StateError(
        'Resolved MatrixRTC call does not belong to the deep-linked room.',
      );
    }

    await _calls.open(
      CallDeepLinkTarget(
        accountId: accountId,
        roomId: descriptor.roomId,
        callId: descriptor.callId,
      ),
    );
    return MatrixCallDeepLinkResult.opened;
  }
}
