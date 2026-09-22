import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:kite/app/kite_runtime.dart';
import 'package:kite/app/platform_matrix_bootstrap_gateway.dart';
import 'package:kite/features/auth/authentication_gateway.dart';
import 'package:kite/features/home/matrix_home_presentation.dart';
import 'package:kite/features/profile/matrix_avatar_image_provider.dart';
import 'package:kite/features/profile/platform_avatar_picker.dart';
import 'package:kite/features/rooms/matrix_room_creation_adapter.dart';
import 'package:kite/features/rooms/matrix_room_member_management_adapter.dart';
import 'package:kite/features/rooms/room_management.dart';
import 'package:kite/features/rooms/room_member_management.dart' as managed;
import 'package:kite/features/rooms/room_members.dart';
import 'package:kite/features/timeline/timeline_controller.dart';
import 'package:kite/features/timeline/timeline_link_preview.dart';
import 'package:kite/features/timeline/timeline_share.dart';
import 'package:kite/matrix/io_matrix_well_known_client.dart';
import 'package:kite/matrix/matrix_homeserver_discovery.dart';
import 'package:kite/matrix/matrix_production_device_api.dart';
import 'package:kite/matrix/matrix_production_profile_api.dart';
import 'package:kite/matrix/matrix_production_recovery_api.dart';
import 'package:kite/matrix/matrix_production_runtime.dart';
import 'package:kite/matrix/matrix_rust_auth_session_api.dart';
import 'package:kite/matrix/matrix_rust_native_bridge.dart';
import 'package:kite/matrix/matrix_runtime_bindings.dart';
import 'package:kite/matrix/matrix_sdk_boundary.dart';
import 'package:kite/matrix/native_matrix_account_sdk_boundary.dart';
import 'package:kite/matrix/presentation_cache.dart';
import 'package:signals/signals.dart';

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
        recoveryApi: MatrixProductionRecoveryApi(matrixRuntime),
        deviceApi: MatrixProductionDeviceApi(matrixRuntime),
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
          unawaited(_prepareForSessionReauthentication(session.userId));
        },
      ),
    );
  }

  Future<void> _prepareForSessionReauthentication(String accountId) async {
    try {
      await widget.matrixRuntime.restartAccount(accountId);
    } finally {
      if (mounted) _sessionInvalidation.value += 1;
    }
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
  static const int _avatarPrefetchLimit = 32;
  static const int _avatarTimelineEventLimit = 8;
  static const int _avatarPrefetchAttempts = 3;
  static const int _avatarPrefetchBatchSize = 6;
  static const int _timelineMediaPrefetchLimit = 6;
  static const int _roomMemberPrefetchLimit = 6;
  static const Duration _avatarPrefetchRetryDelay = Duration(milliseconds: 350);

  final Set<String> _scheduledAvatarPrefetches = <String>{};
  final Set<String> _scheduledTimelineMediaPrefetches = <String>{};
  final Map<String, List<MatrixSdkRoomMember>> _roomMemberCache =
      <String, List<MatrixSdkRoomMember>>{};
  final Map<String, Future<List<MatrixSdkRoomMember>>> _roomMemberLoads =
      <String, Future<List<MatrixSdkRoomMember>>>{};
  void Function()? _disposeAvatarPrefetchEffect;
  var _activationGeneration = 0;
  var _avatarPrefetchGeneration = 0;

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
    _detachAvatarPrefetch();
    _roomMemberCache.clear();
    _roomMemberLoads.clear();
    _activationGeneration += 1;
    return _activate(_activationGeneration);
  }

  Future<MatrixPresentationCache> _activate(int generation) async {
    widget.runtime.registerAuthenticatedAccount(
      accountId: widget.session.userId,
      homeserver: widget.session.homeserver.uri,
    );
    late final MatrixPresentationCache cache;
    try {
      cache = await widget.runtime.activateCached(widget.session.userId);
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('Kite Matrix activation failed: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
      rethrow;
    }
    if (mounted && generation == _activationGeneration) {
      _sessionExpiryBinding.attach(
        widget.runtime.activeSyncState,
        widget.onSessionExpired,
      );
      _attachAvatarPrefetch(cache);
      unawaited(_prefetchRecentRoomMembers(cache, generation));
      unawaited(_resumeSync(generation));
    }
    return cache;
  }

  Future<void> _resumeSync(int generation) async {
    if (!mounted || generation != _activationGeneration) return;
    try {
      await widget.runtime.resumeActive();
    } catch (error, stackTrace) {
      if (!mounted || generation != _activationGeneration) return;
      if (kDebugMode) {
        debugPrint('Kite Matrix background sync failed to start: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
    }
  }

  void _attachAvatarPrefetch(MatrixPresentationCache cache) {
    _detachAvatarPrefetch();
    final generation = _avatarPrefetchGeneration;
    _disposeAvatarPrefetchEffect = effect(() {
      final snapshot = cache.snapshot(
        roomLimit: _avatarPrefetchLimit,
        timelineEventLimitPerRoom: _avatarTimelineEventLimit,
      );
      final pending = <String>[];

      void schedule(String? avatarUrl) {
        if (pending.length >= _avatarPrefetchLimit || avatarUrl == null) return;
        final uri = Uri.tryParse(avatarUrl);
        if (uri?.scheme != 'mxc') return;
        if (_scheduledAvatarPrefetches.add(avatarUrl)) {
          pending.add(avatarUrl);
        }
      }

      for (final room in snapshot.rooms) {
        schedule(room.avatarUrl);
      }
      if (pending.length < _avatarPrefetchLimit) {
        for (final events in snapshot.timelines.values) {
          for (final event in events.reversed) {
            schedule(event.senderAvatarUrl);
            if (pending.length >= _avatarPrefetchLimit) break;
          }
          if (pending.length >= _avatarPrefetchLimit) break;
        }
      }
      final seenMedia = <String>{};
      final media = <({DateTime timestamp, TimelineAttachment attachment})>[];
      for (final events in snapshot.timelines.values) {
        for (final event in events.reversed) {
          final message = TimelineMessage.fromMatrixEvent(
            event,
            currentUserId: widget.session.userId,
          );
          final attachment = message?.attachment;
          final contentUri = attachment?.contentUri;
          if (attachment?.kind != TimelineAttachmentKind.image ||
              contentUri == null ||
              !seenMedia.add(contentUri)) {
            continue;
          }
          media.add((
            timestamp: event.originServerTimestamp,
            attachment: attachment!,
          ));
        }
      }
      media.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      if (media.isNotEmpty) {
        unawaited(
          _prefetchTimelineMedia(
            generation,
            media
                .take(_timelineMediaPrefetchLimit)
                .map((item) => item.attachment)
                .toList(growable: false),
          ),
        );
      }
      if (pending.isNotEmpty) {
        unawaited(_prefetchAvatars(generation, pending));
      }
    });
  }

  Future<void> _prefetchTimelineMedia(
    int generation,
    List<TimelineAttachment> attachments,
  ) async {
    for (final attachment in attachments) {
      if (!mounted || generation != _avatarPrefetchGeneration) return;
      final contentUri = attachment.contentUri;
      if (contentUri == null ||
          !_scheduledTimelineMediaPrefetches.add(contentUri)) {
        continue;
      }
      final provider = _timelineMediaImageProvider(attachment);
      if (provider == null) {
        _scheduledTimelineMediaPrefetches.remove(contentUri);
        continue;
      }
      if (!await precacheMatrixImage(provider, context)) {
        _scheduledTimelineMediaPrefetches.remove(contentUri);
      }
    }
  }

  Future<void> _prefetchAvatars(
    int generation,
    List<String> contentUris,
  ) async {
    for (
      var offset = 0;
      offset < contentUris.length;
      offset += _avatarPrefetchBatchSize
    ) {
      if (!mounted || generation != _avatarPrefetchGeneration) return;
      final end = offset + _avatarPrefetchBatchSize < contentUris.length
          ? offset + _avatarPrefetchBatchSize
          : contentUris.length;
      final batch = contentUris.sublist(offset, end);
      await _prefetchAvatarBatch(generation, batch);
      // Each batch maps to one native FFI operation. Yield between batches so
      // interactive room history and visible-avatar requests can jump ahead.
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<void> _prefetchAvatarBatch(
    int generation,
    List<String> contentUris,
  ) async {
    for (var attempt = 0; attempt < _avatarPrefetchAttempts; attempt += 1) {
      try {
        final completed = await widget.runtime.prefetchMedia(
          accountId: widget.session.userId,
          contentUris: contentUris,
          width: 192,
          height: 192,
        );
        if (!mounted || generation != _avatarPrefetchGeneration) return;
        if (completed == contentUris.length) return;
      } catch (_) {
        if (!mounted || generation != _avatarPrefetchGeneration) return;
      }
      if (attempt + 1 < _avatarPrefetchAttempts) {
        await Future<void>.delayed(_avatarPrefetchRetryDelay * (attempt + 1));
        if (!mounted || generation != _avatarPrefetchGeneration) return;
      }
    }
    _scheduledAvatarPrefetches.removeAll(contentUris);
  }

  void _detachAvatarPrefetch() {
    _avatarPrefetchGeneration += 1;
    _disposeAvatarPrefetchEffect?.call();
    _disposeAvatarPrefetchEffect = null;
    _scheduledAvatarPrefetches.clear();
    _scheduledTimelineMediaPrefetches.clear();
  }

  @override
  void dispose() {
    _activationGeneration += 1;
    _sessionExpiryBinding.detach();
    _detachAvatarPrefetch();
    super.dispose();
  }

  Future<List<MatrixSdkRoomMember>> _refreshRoomMembers(
    String roomId,
    int generation,
  ) {
    final pending = _roomMemberLoads[roomId];
    if (pending != null) return pending;
    late final Future<List<MatrixSdkRoomMember>> guarded;
    guarded = widget.runtime
        .roomMembers(accountId: widget.session.userId, roomId: roomId)
        .then((members) {
          final result = List<MatrixSdkRoomMember>.unmodifiable(members);
          if (mounted && generation == _activationGeneration) {
            _roomMemberCache[roomId] = result;
          }
          return result;
        });
    _roomMemberLoads[roomId] = guarded;
    void cleanup() {
      if (identical(_roomMemberLoads[roomId], guarded)) {
        _roomMemberLoads.remove(roomId);
      }
    }

    unawaited(
      guarded.then<void>(
        (_) => cleanup(),
        onError: (Object _, StackTrace _) => cleanup(),
      ),
    );
    return guarded;
  }

  Future<void> _prefetchRecentRoomMembers(
    MatrixPresentationCache cache,
    int generation,
  ) async {
    final roomIds = cache.roomOrder.peek().take(_roomMemberPrefetchLimit);
    await Future.wait<void>(
      roomIds.map((roomId) async {
        try {
          await _refreshRoomMembers(roomId, generation);
        } catch (_) {
          return;
        }
      }),
    );
  }

  Future<RoomMembersStore> _loadRoomMembers(String roomId) async {
    final cached = _roomMemberCache[roomId];
    final snapshots =
        cached ?? await _refreshRoomMembers(roomId, _activationGeneration);
    if (cached != null) {
      unawaited(
        _refreshRoomMembers(
          roomId,
          _activationGeneration,
        ).then<void>((_) {}, onError: (Object _, StackTrace _) {}),
      );
    }
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

  ImageProvider<Object>? _profileAvatarImageProvider(Uri? avatarUri) {
    if (avatarUri == null) return null;
    return MatrixAvatarImageProvider(
      avatarUri: avatarUri,
      cacheNamespace: widget.runtime,
      loadBytes: (contentUri) => widget.runtime.downloadMedia(
        accountId: widget.session.userId,
        contentUri: contentUri.toString(),
        width: 192,
        height: 192,
      ),
    );
  }

  ImageProvider<Object>? _timelineMediaImageProvider(
    TimelineAttachment attachment,
  ) {
    final contentUri = attachment.contentUri;
    if (contentUri == null) return null;
    final uri = Uri.tryParse(contentUri);
    if (uri == null || uri.scheme != 'mxc') return null;
    return MatrixAvatarImageProvider(
      avatarUri: uri,
      cacheNamespace: widget.runtime,
      loadBytes: (_) => widget.runtime.downloadMedia(
        accountId: widget.session.userId,
        contentUri: contentUri,
        encryptedFile: attachment.encryptedFile,
        width: 1280,
        height: 1280,
      ),
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
        userSearch: (query) => widget.runtime.searchUsers(
          accountId: widget.session.userId,
          query: query,
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
            sendPort: MatrixTimelineSendPort(
              ({required roomId, required transactionId, required body}) async {
                await widget.runtime.sendTextMessage(
                  accountId: widget.session.userId,
                  roomId: roomId,
                  transactionId: transactionId,
                  body: body,
                );
              },
              sendReply:
                  ({
                    required roomId,
                    required transactionId,
                    required body,
                    required replyToEventId,
                  }) async {
                    await widget.runtime.sendTextMessage(
                      accountId: widget.session.userId,
                      roomId: roomId,
                      transactionId: transactionId,
                      body: body,
                      replyToEventId: replyToEventId,
                    );
                  },
            ),
            sharePort: const PlatformTimelineSharePort(),
            moderationPort: MatrixTimelineModerationPort(({
              required roomId,
              required eventId,
              required reason,
            }) {
              return widget.runtime.reportEvent(
                accountId: widget.session.userId,
                roomId: roomId,
                eventId: eventId,
                reason: reason,
              );
            }),
            editPort: MatrixTimelineEditPort(({
              required roomId,
              required transactionId,
              required eventId,
              required body,
            }) async {
              await widget.runtime.sendTextMessage(
                accountId: widget.session.userId,
                roomId: roomId,
                transactionId: transactionId,
                body: body,
                replacementEventId: eventId,
              );
            }),
            redactionPort: MatrixTimelineRedactionPort(({
              required roomId,
              required transactionId,
              required eventId,
            }) {
              return widget.runtime.redactEvent(
                accountId: widget.session.userId,
                roomId: roomId,
                eventId: eventId,
                transactionId: transactionId,
              );
            }),
            linkOpenPort: const PlatformTimelineLinkOpenPort(),
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
            profileAvatarImageProvider: _profileAvatarImageProvider,
            timelineMediaImageProvider: _timelineMediaImageProvider,
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
