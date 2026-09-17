import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kite/app/kite_runtime.dart';
import 'package:kite/app/platform_matrix_bootstrap_gateway.dart';
import 'package:kite/features/auth/authentication_gateway.dart';
import 'package:kite/features/home/matrix_home_presentation.dart';
import 'package:kite/features/profile/platform_avatar_picker.dart';
import 'package:kite/features/rooms/matrix_room_creation_adapter.dart';
import 'package:kite/features/rooms/matrix_room_member_management_adapter.dart';
import 'package:kite/features/rooms/room_management.dart';
import 'package:kite/features/rooms/room_member_management.dart' as managed;
import 'package:kite/features/rooms/room_members.dart';
import 'package:kite/matrix/io_matrix_well_known_client.dart';
import 'package:kite/matrix/matrix_homeserver_discovery.dart';
import 'package:kite/matrix/matrix_production_profile_api.dart';
import 'package:kite/matrix/matrix_production_runtime.dart';
import 'package:kite/matrix/matrix_rust_auth_session_api.dart';
import 'package:kite/matrix/matrix_rust_native_bridge.dart';
import 'package:kite/matrix/matrix_runtime_bindings.dart';
import 'package:kite/matrix/native_matrix_account_sdk_boundary.dart';
import 'package:kite/matrix/presentation_cache.dart';

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
      accountBoundary: NativeMatrixAccountSdkBoundary(
        authApi,
        profileApi: MatrixProductionProfileApi(matrixRuntime),
      ),
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
      beforeSignOut: (session) async {
        await widget.matrixRuntime.removeAccount(session.userId);
      },
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
  final MatrixSessionExpiryBinding _sessionExpiryBinding =
      MatrixSessionExpiryBinding();
  var _activationGeneration = 0;

  @override
  void initState() {
    super.initState();
    _activation = _startActivation();
  }

  @override
  void didUpdateWidget(_AuthenticatedMatrixHome oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session.userId == widget.session.userId &&
        oldWidget.session.homeserver.uri == widget.session.homeserver.uri &&
        identical(oldWidget.runtime, widget.runtime)) {
      return;
    }
    _activation = _startActivation();
  }

  Future<MatrixPresentationCache> _startActivation() {
    _sessionExpiryBinding.detach();
    _activationGeneration += 1;
    return _activate(_activationGeneration);
  }

  Future<MatrixPresentationCache> _activate(int generation) async {
    widget.runtime.registerAuthenticatedAccount(
      accountId: widget.session.userId,
      homeserver: widget.session.homeserver.uri,
    );
    final cache = await widget.runtime.activate(widget.session.userId);
    if (mounted && generation == _activationGeneration) {
      _sessionExpiryBinding.attach(
        widget.runtime.activeSyncState,
        widget.onSessionExpired,
      );
    }
    return cache;
  }

  @override
  void dispose() {
    _activationGeneration += 1;
    _sessionExpiryBinding.detach();
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

  Future<Uri?> _pickProfileAvatar() {
    return PlatformAvatarPicker(
      uploadMedia: ({required mimeType, required bytes}) =>
          widget.runtime.uploadMedia(
            accountId: widget.session.userId,
            mimeType: mimeType,
            bytes: bytes,
          ),
    ).pick();
  }

  RoomManagementCoordinator _roomCreationCoordinator() {
    return RoomManagementCoordinator(
      rooms: MatrixRoomCreationManagementPort(
        (request) => widget.runtime.createRoom(
          accountId: widget.session.userId,
          request: request,
        ),
        reportRoom: (roomId, reason) => widget.runtime.reportRoom(
          accountId: widget.session.userId,
          roomId: roomId,
          reason: reason,
        ),
        reportUser: (roomId, userId, reason) => widget.runtime.reportUser(
          accountId: widget.session.userId,
          roomId: roomId,
          userId: userId,
          reason: reason,
        ),
        leaveRoom: (roomId) => widget.runtime.leaveRoom(
          accountId: widget.session.userId,
          roomId: roomId,
        ),
        forgetRoom: (roomId) => widget.runtime.forgetRoom(
          accountId: widget.session.userId,
          roomId: roomId,
        ),
        roomDetails: (roomId) => widget.runtime.roomDetails(
          accountId: widget.session.userId,
          roomId: roomId,
        ),
        setName: (roomId, name) => widget.runtime.setRoomName(
          accountId: widget.session.userId,
          roomId: roomId,
          name: name,
        ),
        setTopic: (roomId, topic) => widget.runtime.setRoomTopic(
          accountId: widget.session.userId,
          roomId: roomId,
          topic: topic,
        ),
        setAvatar: (roomId, avatarUrl) => widget.runtime.setRoomAvatar(
          accountId: widget.session.userId,
          roomId: roomId,
          avatarUrl: avatarUrl,
        ),
        setCanonicalAlias: (roomId, canonicalAlias) =>
            widget.runtime.setRoomCanonicalAlias(
              accountId: widget.session.userId,
              roomId: roomId,
              canonicalAlias: canonicalAlias,
            ),
        setJoinRule: (roomId, joinRule) => widget.runtime.setRoomJoinRule(
          accountId: widget.session.userId,
          roomId: roomId,
          joinRule: joinRule,
        ),
        enableEncryption: (roomId) => widget.runtime.enableRoomEncryption(
          accountId: widget.session.userId,
          roomId: roomId,
        ),
        setHistoryVisibility: (roomId, visibility) =>
            widget.runtime.setRoomHistoryVisibility(
              accountId: widget.session.userId,
              roomId: roomId,
              visibility: visibility,
            ),
        setNotificationMode: (roomId, mode) =>
            widget.runtime.setRoomNotificationMode(
              accountId: widget.session.userId,
              roomId: roomId,
              mode: mode,
            ),
      ),
      directMetadata: const MatrixDirectRoomMetadataPort(),
    );
  }

  managed.RoomMemberManagementCoordinator _roomMemberManagementCoordinator() {
    final port = MatrixRoomMemberManagementPort(
      loadMembers: (roomId) => widget.runtime.roomMembers(
        accountId: widget.session.userId,
        roomId: roomId,
      ),
      inviteMember: (roomId, userId) => widget.runtime.inviteRoomMember(
        accountId: widget.session.userId,
        roomId: roomId,
        userId: userId,
      ),
      authorizeMember:
          (roomId, actorUserId, targetUserId, action, requestedPowerLevel) =>
              widget.runtime.canModerateRoomMember(
                accountId: widget.session.userId,
                roomId: roomId,
                actorUserId: actorUserId,
                targetUserId: targetUserId,
                action: action,
                requestedPowerLevel: requestedPowerLevel,
              ),
      setPowerLevel: (roomId, userId, powerLevel) =>
          widget.runtime.setRoomMemberPowerLevel(
            accountId: widget.session.userId,
            roomId: roomId,
            userId: userId,
            powerLevel: powerLevel,
          ),
      kickMember: (roomId, userId) => widget.runtime.kickRoomMember(
        accountId: widget.session.userId,
        roomId: roomId,
        userId: userId,
      ),
      banMember: (roomId, userId, reason) => widget.runtime.banRoomMember(
        accountId: widget.session.userId,
        roomId: roomId,
        userId: userId,
        reason: reason,
      ),
      unbanMember: (roomId, userId) => widget.runtime.unbanRoomMember(
        accountId: widget.session.userId,
        roomId: roomId,
        userId: userId,
      ),
    );
    return managed.RoomMemberManagementCoordinator(
      actorUserId: widget.session.userId,
      directory: port,
      authorization: port,
      mutations: port,
    );
  }

  void _retry() {
    setState(() {
      _activation = _startActivation();
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
            onRoomFavouriteChanged: (roomId, isFavourite) =>
                widget.runtime.setRoomFavourite(
                  accountId: widget.session.userId,
                  roomId: roomId,
                  isFavourite: isFavourite,
                ),
            onMarkAllRoomsRead: () => widget.runtime.markAllRoomsRead(
              accountId: widget.session.userId,
            ),
            onRoomInviteResponse: (roomId, accept) =>
                widget.runtime.respondToRoomInvite(
                  accountId: widget.session.userId,
                  roomId: roomId,
                  accept: accept,
                ),
            profileAvatarPicker: _pickProfileAvatar,
            roomCreation: _roomCreationCoordinator(),
            memberManagement: _roomMemberManagementCoordinator(),
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
            memberModerationEnabled: true,
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
