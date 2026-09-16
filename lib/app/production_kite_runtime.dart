import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kite/app/kite_runtime.dart';
import 'package:kite/app/platform_matrix_bootstrap_gateway.dart';
import 'package:kite/features/auth/authentication_gateway.dart';
import 'package:kite/features/home/matrix_home_presentation.dart';
import 'package:kite/features/rooms/room_members.dart';
import 'package:kite/matrix/io_matrix_well_known_client.dart';
import 'package:kite/matrix/matrix_engine.dart';
import 'package:kite/matrix/matrix_homeserver_discovery.dart';
import 'package:kite/matrix/matrix_production_runtime.dart';
import 'package:kite/matrix/matrix_rust_auth_session_api.dart';
import 'package:kite/matrix/matrix_rust_native_bridge.dart';
import 'package:kite/matrix/matrix_runtime_bindings.dart';
import 'package:kite/matrix/native_matrix_account_sdk_boundary.dart';
import 'package:kite/matrix/presentation_cache.dart';
import 'package:signals/signals_flutter.dart';

final class ProductionKiteRuntime extends StatefulWidget {
  const ProductionKiteRuntime._({
    required this.accountBoundary,
    required this.matrixRuntime,
  });

  static Future<ProductionKiteRuntime> create({
    PlatformMatrixBootstrapGateway gateway =
        const PlatformMatrixBootstrapGateway(),
  }) async {
    final root = await gateway.dataRoot();
    await root.create(recursive: true);
    late final MatrixProductionRuntime matrixRuntime;
    final nativeBridge = MatrixRustNativeBridge(
      libraryPath: matrixRustNativeLibraryPath(),
    );
    matrixRuntime = MatrixProductionRuntime(
      rootDirectory: root,
      resolveStoreSecret: gateway.resolveStoreSecret,
      encryptionKeyIdForAccount: (_) =>
          MatrixRustAuthSessionApi.encryptionKeyId,
      nativeBridge: nativeBridge,
    );
    final authApi = MatrixRustAuthSessionApi(
      homeserverDiscovery: const MatrixHomeserverDiscovery(
        IoMatrixWellKnownClient(),
      ),
      authenticationBridge: nativeBridge,
      nativeBridge: nativeBridge,
      rootDirectory: root,
      resolveStoreSecret: gateway.resolveStoreSecret,
      storeConfigurationForAccount:
          matrixRuntime.accounts.storeRegistry.forAccount,
    );
    return ProductionKiteRuntime._(
      accountBoundary: NativeMatrixAccountSdkBoundary(authApi),
      matrixRuntime: matrixRuntime,
    );
  }

  final NativeMatrixAccountSdkBoundary accountBoundary;
  final MatrixProductionRuntime matrixRuntime;

  @override
  State<ProductionKiteRuntime> createState() => _ProductionKiteRuntimeState();
}

final class _ProductionKiteRuntimeState extends State<ProductionKiteRuntime> {
  late final MatrixLifecycleBinding _lifecycleBinding;
  late final ValueNotifier<int> _sessionInvalidation;

  @override
  void initState() {
    super.initState();
    _sessionInvalidation = ValueNotifier<int>(0);
    _lifecycleBinding = MatrixLifecycleBinding(widget.matrixRuntime);
    unawaited(_lifecycleBinding.attach());
  }

  @override
  void dispose() {
    unawaited(_disposeRuntime());
    _sessionInvalidation.dispose();
    super.dispose();
  }

  Future<void> _disposeRuntime() async {
    await _lifecycleBinding.detach();
    await widget.matrixRuntime.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return KiteRuntime(
      accountSdkBoundary: widget.accountBoundary,
      sessionInvalidation: _sessionInvalidation,
      authenticatedHomeBuilder: (context, session) => _AuthenticatedMatrixHome(
        runtime: widget.matrixRuntime,
        session: session,
        onSessionExpired: () {
          _sessionInvalidation.value += 1;
        },
      ),
    );
  }
}

final class _AuthenticatedMatrixHome extends StatefulWidget {
  const _AuthenticatedMatrixHome({
    required this.runtime,
    required this.session,
    required this.onSessionExpired,
  });

  final MatrixProductionRuntime runtime;
  final AuthenticatedSession session;
  final VoidCallback onSessionExpired;

  @override
  State<_AuthenticatedMatrixHome> createState() =>
      _AuthenticatedMatrixHomeState();
}

final class _AuthenticatedMatrixHomeState
    extends State<_AuthenticatedMatrixHome> {
  late Future<MatrixPresentationCache> _activation;
  void Function()? _disposeSyncFailureEffect;
  var _sessionExpiryReported = false;

  @override
  void initState() {
    super.initState();
    _activation = _activate();
  }

  @override
  void didUpdateWidget(_AuthenticatedMatrixHome oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session.userId == widget.session.userId &&
        oldWidget.session.homeserver.uri == widget.session.homeserver.uri &&
        identical(oldWidget.runtime, widget.runtime)) {
      return;
    }
    _activation = _activate();
  }

  Future<MatrixPresentationCache> _activate() async {
    widget.runtime.registerAuthenticatedAccount(
      accountId: widget.session.userId,
      homeserver: widget.session.homeserver.uri,
    );
    final cache = await widget.runtime.activate(widget.session.userId);
    _bindSyncFailure();
    return cache;
  }

  void _bindSyncFailure() {
    _disposeSyncFailureEffect?.call();
    _sessionExpiryReported = false;
    final syncState = widget.runtime.activeSyncState;
    if (syncState == null) return;
    _disposeSyncFailureEffect = effect(() {
      final error = syncState.value.error;
      final expired =
          error is MatrixNonRetryableSyncException &&
          error.cause is MatrixSessionExpiredException;
      if (!expired || _sessionExpiryReported) return;
      _sessionExpiryReported = true;
      scheduleMicrotask(() {
        if (mounted) widget.onSessionExpired();
      });
    });
  }

  @override
  void dispose() {
    _disposeSyncFailureEffect?.call();
    super.dispose();
  }

  Future<RoomMembersStore> _loadRoomMembers(String roomId) async {
    final snapshots = await widget.runtime.roomMembers(
      accountId: widget.session.userId,
      roomId: roomId,
    );
    final members = snapshots
        .map(
          (member) => RoomMember(
            userId: member.userId,
            displayName: member.displayName,
            membership: RoomMembership.joined,
            powerLevel: member.powerLevel,
          ),
        )
        .toList(growable: false);
    final powers = <String, int>{
      for (final member in snapshots) member.userId: member.powerLevel,
    };
    return RoomMembersStore(
      roomId: roomId,
      currentUserId: widget.session.userId,
      members: members,
      powerLevels: MatrixPowerLevels(users: powers),
    );
  }

  void _retry() {
    setState(() {
      _activation = _activate();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<MatrixPresentationCache>(
      future: _activation,
      builder: (context, snapshot) {
        final cache = snapshot.data;
        if (cache != null) {
          return MatrixHomeScreen(
            cache: cache,
            currentUserId: widget.session.userId,
            sendPort: MatrixTimelineSendPort(({
              required roomId,
              required transactionId,
              required body,
            }) async {
              await widget.runtime.sendTextMessage(
                accountId: widget.session.userId,
                roomId: roomId,
                transactionId: transactionId,
                body: body,
              );
            }),
            onTimelineHistoryRequested: (roomId, oldestVisibleIndex) async {
              final paginationState = widget.runtime.paginationState(
                accountId: widget.session.userId,
                roomId: roomId,
              );
              await widget.runtime.onTimelineViewportChanged(
                accountId: widget.session.userId,
                roomId: roomId,
                oldestVisibleIndex: oldestVisibleIndex,
                hasMoreHistory: paginationState?.value.hasMoreHistory ?? true,
              );
            },
            roomMembersLoader: _loadRoomMembers,
            memberModerationEnabled: false,
          );
        }
        if (snapshot.hasError) {
          return Scaffold(
            body: SafeArea(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Text('Could not start Matrix sync.'),
                    const SizedBox(height: 16),
                    FilledButton(onPressed: _retry, child: const Text('Retry')),
                  ],
                ),
              ),
            ),
          );
        }
        return const Scaffold(
          body: SafeArea(child: Center(child: CircularProgressIndicator())),
        );
      },
    );
  }
}
