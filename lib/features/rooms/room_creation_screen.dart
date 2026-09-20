import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kite/design/kite_tokens.dart';
import 'package:kite/features/rooms/room_management.dart';

enum RoomCreationMode { directMessage, privateRoom, publicRoom }

class RoomCreationScreen extends StatefulWidget {
  const RoomCreationScreen({
    required this.coordinator,
    this.initialMode = RoomCreationMode.directMessage,
    this.initialDirectUserId,
    this.recentPeople = const <KiteUserSearchResult>[],
    this.parentSpaceId,
    this.onCreated,
    super.key,
  });

  final RoomManagementCoordinator coordinator;
  final RoomCreationMode initialMode;
  final String? initialDirectUserId;
  final List<KiteUserSearchResult> recentPeople;
  final String? parentSpaceId;
  final ValueChanged<KiteCreatedRoom>? onCreated;

  @override
  State<RoomCreationScreen> createState() => _RoomCreationScreenState();
}

class _RoomCreationScreenState extends State<RoomCreationScreen> {
  final _name = TextEditingController();
  final _topic = TextEditingController();
  late final TextEditingController _userId;
  final _alias = TextEditingController();
  final _userFocusNode = FocusNode();
  late RoomCreationMode _mode;
  KiteRoomCapabilities? _capabilities;
  KiteRoomJoinRule _joinRule = KiteRoomJoinRule.invite;
  bool _encrypt = true;
  bool _submitting = false;
  String? _error;
  Timer? _userSearchDebounce;
  int _userSearchGeneration = 0;
  bool _searchingUsers = false;
  String? _userSearchError;
  List<KiteUserSearchResult> _userSearchResults =
      const <KiteUserSearchResult>[];

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
    _userId = TextEditingController(text: widget.initialDirectUserId);
    _userSearchResults = widget.recentPeople.take(8).toList(growable: false);
    _encrypt = _mode != RoomCreationMode.publicRoom;
    unawaited(_loadCapabilities());
  }

  @override
  void dispose() {
    _userSearchDebounce?.cancel();
    _name.dispose();
    _topic.dispose();
    _userId.dispose();
    _userFocusNode.dispose();
    _alias.dispose();
    super.dispose();
  }

  Future<void> _loadCapabilities() async {
    try {
      final value = await widget.coordinator.capabilities();
      if (!mounted) return;
      setState(() {
        _capabilities = value;
        if (!value.supports(_joinRule)) {
          _joinRule = KiteRoomJoinRule.invite;
        }
        if (_mode == RoomCreationMode.publicRoom &&
            !value.canCreatePublicRooms) {
          _mode = RoomCreationMode.privateRoom;
          _encrypt = true;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Kite could not load room creation policy.');
    }
  }

  void _changeMode(RoomCreationMode mode) {
    if (_submitting || mode == _mode) return;
    final capabilities = _capabilities;
    if (mode == RoomCreationMode.publicRoom &&
        capabilities != null &&
        !capabilities.canCreatePublicRooms) {
      return;
    }
    _userSearchDebounce?.cancel();
    _userSearchGeneration += 1;
    setState(() {
      _mode = mode;
      _error = null;
      _searchingUsers = false;
      _userSearchError = null;
      _userSearchResults = mode == RoomCreationMode.directMessage
          ? _recentMatches(_userId.text)
          : const <KiteUserSearchResult>[];
      _encrypt = mode != RoomCreationMode.publicRoom;
      if (mode != RoomCreationMode.privateRoom) {
        _joinRule = mode == RoomCreationMode.publicRoom
            ? KiteRoomJoinRule.public
            : KiteRoomJoinRule.invite;
      } else if (_joinRule == KiteRoomJoinRule.public) {
        _joinRule = KiteRoomJoinRule.invite;
      }
    });
    if (mode == RoomCreationMode.directMessage) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _userFocusNode.requestFocus();
      });
    }
  }

  List<KiteUserSearchResult> _recentMatches(String query) {
    final normalized = query.trim().toLowerCase();
    return widget.recentPeople
        .where((person) {
          if (normalized.isEmpty) return true;
          return person.userId.toLowerCase().contains(normalized) ||
              (person.displayName?.toLowerCase().contains(normalized) ?? false);
        })
        .take(8)
        .toList(growable: false);
  }

  void _onDirectUserChanged(String rawQuery) {
    _userSearchDebounce?.cancel();
    _userSearchGeneration += 1;
    final generation = _userSearchGeneration;
    final query = rawQuery.trim();
    final recent = _recentMatches(query);
    setState(() {
      _searchingUsers = false;
      _userSearchError = null;
      _userSearchResults = recent;
    });
    if (query.length < 2) return;
    _userSearchDebounce = Timer(
      const Duration(milliseconds: 80),
      () => unawaited(_searchUsers(query, generation, recent)),
    );
  }

  Future<void> _searchUsers(
    String query,
    int generation,
    List<KiteUserSearchResult> recent,
  ) async {
    if (!mounted || generation != _userSearchGeneration) return;
    if (recent.isEmpty) setState(() => _searchingUsers = true);
    try {
      final results = await widget.coordinator.searchUsers(query);
      if (!mounted || generation != _userSearchGeneration) return;
      final byId = <String, KiteUserSearchResult>{
        for (final result in recent) result.userId: result,
        for (final result in results) result.userId: result,
      };
      setState(() {
        _searchingUsers = false;
        _userSearchResults = byId.values.take(12).toList(growable: false);
      });
    } catch (_) {
      if (!mounted || generation != _userSearchGeneration) return;
      setState(() {
        _searchingUsers = false;
        _userSearchResults = recent;
        _userSearchError = recent.isEmpty ? 'Could not search people.' : null;
      });
    }
  }

  void _selectUser(KiteUserSearchResult result) {
    _userSearchDebounce?.cancel();
    _userSearchGeneration += 1;
    _userId.value = TextEditingValue(
      text: result.userId,
      selection: TextSelection.collapsed(offset: result.userId.length),
    );
    setState(() {
      _searchingUsers = false;
      _userSearchError = null;
      _userSearchResults = const <KiteUserSearchResult>[];
    });
  }

  Future<void> _create() async {
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final created = switch (_mode) {
        RoomCreationMode.directMessage =>
          await widget.coordinator.createDirectMessage(_userId.text),
        RoomCreationMode.privateRoom =>
          await widget.coordinator.createPrivateRoom(
            name: _name.text,
            topic: _topic.text,
            joinRule: _joinRule,
            encryptionEnabled: _encrypt,
            parentSpaceId: widget.parentSpaceId,
          ),
        RoomCreationMode.publicRoom =>
          await widget.coordinator.createPublicRoom(
            name: _name.text,
            topic: _topic.text,
            canonicalAlias: _alias.text,
            encryptionEnabled: _encrypt,
            parentSpaceId: widget.parentSpaceId,
          ),
      };
      if (!mounted) return;
      widget.onCreated?.call(created);
    } on RoomManagementValidationException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Kite could not create the room.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final capabilities = _capabilities;
    final publicEnabled = capabilities?.canCreatePublicRooms ?? false;
    final joinRules = <KiteRoomJoinRule>[
      KiteRoomJoinRule.invite,
      if (capabilities?.supports(KiteRoomJoinRule.knock) ?? false)
        KiteRoomJoinRule.knock,
      if (capabilities?.supports(KiteRoomJoinRule.restricted) ?? false)
        KiteRoomJoinRule.restricted,
    ];
    return Scaffold(
      key: const Key('room-creation-screen'),
      appBar: AppBar(title: const Text('New conversation')),
      body: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: ListView(
              key: const Key('room-creation-form'),
              padding: const EdgeInsets.all(KiteSpacing.lg),
              children: <Widget>[
                SegmentedButton<RoomCreationMode>(
                  key: const Key('room-creation-mode'),
                  segments: <ButtonSegment<RoomCreationMode>>[
                    const ButtonSegment<RoomCreationMode>(
                      value: RoomCreationMode.directMessage,
                      icon: Icon(Icons.person_outline_rounded),
                      label: Text('Message'),
                    ),
                    const ButtonSegment<RoomCreationMode>(
                      value: RoomCreationMode.privateRoom,
                      icon: Icon(Icons.lock_outline_rounded),
                      label: Text('Private'),
                    ),
                    ButtonSegment<RoomCreationMode>(
                      value: RoomCreationMode.publicRoom,
                      enabled: publicEnabled,
                      icon: const Icon(Icons.public_rounded),
                      label: const Text('Public'),
                    ),
                  ],
                  selected: <RoomCreationMode>{_mode},
                  showSelectedIcon: false,
                  onSelectionChanged: _submitting
                      ? null
                      : (selection) => _changeMode(selection.single),
                ),
                const SizedBox(height: KiteSpacing.xl),
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 280),
                  child: AnimatedSwitcher(
                    duration: KiteMotion.resolve(context, KiteMotion.fast),
                    switchInCurve: KiteMotion.standardCurve,
                    switchOutCurve: KiteMotion.standardCurve,
                    child: _mode == RoomCreationMode.directMessage
                        ? Column(
                            key: const Key('room-create-direct-fields'),
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              TextField(
                                key: const Key('room-create-user-id'),
                                controller: _userId,
                                focusNode: _userFocusNode,
                                autofocus: true,
                                enabled: !_submitting,
                                autocorrect: false,
                                enableSuggestions: false,
                                textInputAction: TextInputAction.done,
                                decoration: InputDecoration(
                                  labelText: 'Search people or Matrix user ID',
                                  hintText: '@name:server or display name',
                                  prefixIcon: const Icon(
                                    Icons.person_search_rounded,
                                  ),
                                  suffixIcon: _searchingUsers
                                      ? const Padding(
                                          padding: EdgeInsets.all(14),
                                          child: SizedBox.square(
                                            dimension: 18,
                                            child: CircularProgressIndicator(
                                              key: Key(
                                                'room-create-user-searching',
                                              ),
                                              strokeWidth: 2,
                                            ),
                                          ),
                                        )
                                      : null,
                                ),
                                onChanged: _onDirectUserChanged,
                                onSubmitted: (_) => unawaited(_create()),
                              ),
                              SizedBox(
                                key: const Key(
                                  'room-create-user-search-status',
                                ),
                                height: 28,
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    _userSearchError ?? '',
                                    key: const Key(
                                      'room-create-user-search-error',
                                    ),
                                    style: KiteTypography.metadata.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .error,
                                    ),
                                  ),
                                ),
                              ),
                              if (_userSearchResults.isNotEmpty)
                                ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxHeight: 240,
                                  ),
                                  child: ListView.separated(
                                    key: const Key('room-create-user-results'),
                                    shrinkWrap: true,
                                    padding: EdgeInsets.zero,
                                    itemCount: _userSearchResults.length,
                                    separatorBuilder: (_, _) =>
                                        const Divider(height: 1),
                                    itemBuilder: (context, index) {
                                      final result = _userSearchResults[index];
                                      final displayName = result.displayName
                                          ?.trim();
                                      final label =
                                          displayName == null ||
                                              displayName.isEmpty
                                          ? result.userId
                                          : displayName;
                                      return ListTile(
                                        key: Key(
                                          'room-create-user-result-$index',
                                        ),
                                        leading: CircleAvatar(
                                          child: Text(
                                            label.startsWith('@') &&
                                                    label.length > 1
                                                ? label[1].toUpperCase()
                                                : label.characters.first
                                                      .toUpperCase(),
                                          ),
                                        ),
                                        title: Text(
                                          label,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        subtitle: label == result.userId
                                            ? null
                                            : Text(
                                                result.userId,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                        onTap: _submitting
                                            ? null
                                            : () => _selectUser(result),
                                      );
                                    },
                                  ),
                                ),
                            ],
                          )
                        : Column(
                            key: const Key('room-create-room-fields'),
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              TextField(
                                key: const Key('room-create-name'),
                                controller: _name,
                                enabled: !_submitting,
                                textInputAction: TextInputAction.next,
                                decoration: const InputDecoration(
                                  labelText: 'Room name',
                                  prefixIcon: Icon(Icons.chat_bubble_outline),
                                ),
                              ),
                              const SizedBox(height: KiteSpacing.md),
                              TextField(
                                key: const Key('room-create-topic'),
                                controller: _topic,
                                enabled: !_submitting,
                                minLines: 2,
                                maxLines: 3,
                                decoration: const InputDecoration(
                                  labelText: 'Topic (optional)',
                                  alignLabelWithHint: true,
                                ),
                              ),
                              if (_mode ==
                                  RoomCreationMode.privateRoom) ...<Widget>[
                                const SizedBox(height: KiteSpacing.md),
                                DropdownButtonFormField<KiteRoomJoinRule>(
                                  key: const Key('room-create-join-rule'),
                                  initialValue: _joinRule,
                                  isExpanded: true,
                                  decoration: const InputDecoration(
                                    labelText: 'Who can join',
                                  ),
                                  items: <DropdownMenuItem<KiteRoomJoinRule>>[
                                    for (final rule in joinRules)
                                      DropdownMenuItem<KiteRoomJoinRule>(
                                        value: rule,
                                        child: Text(_joinRuleLabel(rule)),
                                      ),
                                  ],
                                  onChanged: _submitting
                                      ? null
                                      : (value) {
                                          if (value != null) {
                                            setState(() => _joinRule = value);
                                          }
                                        },
                                ),
                              ],
                              if (_mode ==
                                  RoomCreationMode.publicRoom) ...<Widget>[
                                const SizedBox(height: KiteSpacing.md),
                                TextField(
                                  key: const Key('room-create-alias'),
                                  controller: _alias,
                                  enabled: !_submitting,
                                  autocorrect: false,
                                  decoration: const InputDecoration(
                                    labelText: 'Room address (optional)',
                                    hintText: '#room:server',
                                    prefixIcon: Icon(Icons.tag_rounded),
                                  ),
                                ),
                              ],
                              const SizedBox(height: KiteSpacing.md),
                              SwitchListTile.adaptive(
                                key: const Key('room-create-encryption'),
                                contentPadding: EdgeInsets.zero,
                                title: const Text('Encrypt messages'),
                                subtitle: Text(
                                  _encrypt
                                      ? 'Messages use Matrix end-to-end encryption.'
                                      : 'Messages are not end-to-end encrypted.',
                                ),
                                value: _encrypt,
                                onChanged: _submitting
                                    ? null
                                    : (value) =>
                                          setState(() => _encrypt = value),
                              ),
                              if (_encrypt)
                                Text(
                                  'Encryption cannot be disabled after the room is created.',
                                  style: KiteTypography.metadata.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                                ),
                            ],
                          ),
                  ),
                ),
                const SizedBox(height: KiteSpacing.md),
                SizedBox(
                  key: const Key('room-create-error-slot'),
                  height: 48,
                  child: Center(
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        _error ?? '',
                        key: const Key('room-create-error'),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        style: KiteTypography.metadata.copyWith(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: KiteSpacing.sm),
                Semantics(
                  value: _submitting ? 'Creating' : null,
                  child: FilledButton.icon(
                    key: const Key('room-create-submit'),
                    style: const ButtonStyle(
                      animationDuration: Duration.zero,
                      splashFactory: NoSplash.splashFactory,
                    ),
                    onPressed: _create,
                    icon: const Icon(Icons.arrow_forward_rounded),
                    label: Text(_submitLabel(_mode)),
                  ),
                ),
                if (widget.parentSpaceId != null) ...<Widget>[
                  const SizedBox(height: KiteSpacing.sm),
                  Text(
                    'This room will be linked to the selected Space.',
                    textAlign: TextAlign.center,
                    style: KiteTypography.metadata.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _joinRuleLabel(KiteRoomJoinRule rule) => switch (rule) {
  KiteRoomJoinRule.invite => 'Invite only',
  KiteRoomJoinRule.knock => 'Request to join',
  KiteRoomJoinRule.restricted => 'Members of allowed Spaces',
  KiteRoomJoinRule.public => 'Anyone',
};

String _submitLabel(RoomCreationMode mode) => switch (mode) {
  RoomCreationMode.directMessage => 'Start conversation',
  RoomCreationMode.privateRoom => 'Create private room',
  RoomCreationMode.publicRoom => 'Create public room',
};
