import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kite/design/kite_tokens.dart';
import 'package:kite/features/rooms/room_management.dart';
import 'package:kite/l10n/kite_local_formats.dart';

class RoomDirectoryScreen extends StatefulWidget {
  const RoomDirectoryScreen({
    required this.coordinator,
    this.initialQuery = '',
    super.key,
  });

  final RoomManagementCoordinator coordinator;
  final String initialQuery;

  @override
  State<RoomDirectoryScreen> createState() => _RoomDirectoryScreenState();
}

class _RoomDirectoryScreenState extends State<RoomDirectoryScreen> {
  late final TextEditingController _searchController;
  Timer? _debounce;
  int _searchGeneration = 0;
  bool _loading = false;
  String? _error;
  List<KiteRoomDirectoryResult> _results = const <KiteRoomDirectoryResult>[];

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.initialQuery.trim());
    unawaited(_search(_searchController.text));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onQueryChanged(String query) {
    _debounce?.cancel();
    final generation = ++_searchGeneration;
    _debounce = Timer(
      const Duration(milliseconds: 180),
      () => unawaited(_search(query, generation: generation)),
    );
  }

  Future<void> _search(String query, {int? generation}) async {
    final currentGeneration = generation ?? ++_searchGeneration;
    if (!mounted || currentGeneration != _searchGeneration) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await widget.coordinator.searchRoomDirectory(query);
      if (!mounted || currentGeneration != _searchGeneration) return;
      setState(() => _results = results);
    } catch (_) {
      if (!mounted || currentGeneration != _searchGeneration) return;
      setState(() {
        _results = const <KiteRoomDirectoryResult>[];
        _error = 'Kite could not search the room directory.';
      });
    } finally {
      if (mounted && currentGeneration == _searchGeneration) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('room-directory-screen'),
      appBar: AppBar(title: const Text('Discover rooms')),
      body: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.all(KiteSpacing.lg),
                  child: TextField(
                    key: const Key('room-directory-search'),
                    controller: _searchController,
                    autofocus: true,
                    autocorrect: false,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      labelText: 'Search public rooms',
                      hintText: 'Name, topic, or room address',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _loading
                          ? const Padding(
                              padding: EdgeInsets.all(14),
                              child: SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  key: Key('room-directory-searching'),
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          : _searchController.text.isEmpty
                          ? null
                          : IconButton(
                              key: const Key('room-directory-clear'),
                              tooltip: 'Clear search',
                              onPressed: () {
                                _searchController.clear();
                                _onQueryChanged('');
                                setState(() {});
                              },
                              icon: const Icon(Icons.close_rounded),
                            ),
                    ),
                    onChanged: (query) {
                      _onQueryChanged(query);
                      setState(() {});
                    },
                    onSubmitted: (query) {
                      _debounce?.cancel();
                      unawaited(_search(query));
                    },
                  ),
                ),
                Expanded(child: _buildResults(context)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildResults(BuildContext context) {
    if (_loading && _results.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    final error = _error;
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(KiteSpacing.xl),
          child: Text(
            error,
            key: const Key('room-directory-error'),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (_results.isEmpty) {
      return const Center(
        child: Text('No public rooms found', key: Key('room-directory-empty')),
      );
    }
    return ListView.separated(
      key: const Key('room-directory-results'),
      padding: const EdgeInsets.only(bottom: KiteSpacing.xl),
      itemCount: _results.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final room = _results[index];
        final title = room.name?.trim().isNotEmpty == true
            ? room.name!.trim()
            : room.canonicalAlias ?? room.roomId;
        final alias = room.canonicalAlias;
        final topic = room.topic?.trim();
        final memberCount = KiteLocalFormats.decimal(
          context,
          room.joinedMembers,
        );
        return ListTile(
          key: Key('room-directory-result-$index'),
          leading: const CircleAvatar(child: Icon(Icons.forum_outlined)),
          title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (alias != null && alias != title)
                Text(alias, maxLines: 1, overflow: TextOverflow.ellipsis),
              if (topic != null && topic.isNotEmpty)
                Text(topic, maxLines: 2, overflow: TextOverflow.ellipsis),
              Text(
                '$memberCount members • ${_joinRuleLabel(room.joinRule)}',
                key: Key('room-directory-result-metadata-$index'),
              ),
            ],
          ),
          isThreeLine:
              (alias != null && alias != title) ||
              (topic != null && topic.isNotEmpty),
        );
      },
    );
  }
}

String _joinRuleLabel(String joinRule) => switch (joinRule) {
  'public' => 'Public',
  'knock' => 'Request to join',
  'restricted' => 'Restricted',
  'knock_restricted' => 'Restricted request',
  'invite' => 'Invite only',
  'private' => 'Private',
  _ => joinRule.replaceAll('_', ' '),
};
