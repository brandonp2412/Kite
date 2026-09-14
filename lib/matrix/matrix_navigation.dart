enum MatrixNavigationKind { home, room, event, user, invite, call }

final class MatrixNavigationTarget {
  const MatrixNavigationTarget._({
    required this.kind,
    this.roomIdOrAlias,
    this.eventId,
    this.userId,
  });

  const MatrixNavigationTarget.home() : this._(kind: MatrixNavigationKind.home);

  const MatrixNavigationTarget.room(String roomIdOrAlias)
    : this._(kind: MatrixNavigationKind.room, roomIdOrAlias: roomIdOrAlias);

  const MatrixNavigationTarget.event(String roomIdOrAlias, String eventId)
    : this._(
        kind: MatrixNavigationKind.event,
        roomIdOrAlias: roomIdOrAlias,
        eventId: eventId,
      );

  const MatrixNavigationTarget.user(String userId)
    : this._(kind: MatrixNavigationKind.user, userId: userId);

  const MatrixNavigationTarget.invite(String roomIdOrAlias)
    : this._(kind: MatrixNavigationKind.invite, roomIdOrAlias: roomIdOrAlias);

  const MatrixNavigationTarget.call(String roomIdOrAlias)
    : this._(kind: MatrixNavigationKind.call, roomIdOrAlias: roomIdOrAlias);

  final MatrixNavigationKind kind;
  final String? roomIdOrAlias;
  final String? eventId;
  final String? userId;

  @override
  bool operator ==(Object other) {
    return other is MatrixNavigationTarget &&
        other.kind == kind &&
        other.roomIdOrAlias == roomIdOrAlias &&
        other.eventId == eventId &&
        other.userId == userId;
  }

  @override
  int get hashCode => Object.hash(kind, roomIdOrAlias, eventId, userId);
}

final class MatrixDeepLinkParser {
  const MatrixDeepLinkParser();

  MatrixNavigationTarget? parse(Uri uri) {
    if (uri.scheme == 'matrix') {
      return _parseMatrixUri(uri);
    }
    if ((uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.host.toLowerCase() == 'matrix.to') {
      return _parseMatrixTo(uri);
    }
    return null;
  }

  MatrixNavigationTarget? _parseMatrixUri(Uri uri) {
    final segments = uri.pathSegments
        .where((segment) => segment.isNotEmpty)
        .map(Uri.decodeComponent)
        .toList(growable: false);
    if (segments.isEmpty) return null;

    final kind = segments.first.toLowerCase();
    if (kind == 'call' && segments.length >= 2) {
      return MatrixNavigationTarget.call(_normaliseRoom(segments[1]));
    }
    if ((kind == 'u' || kind == 'user' || kind == 'userid') &&
        segments.length >= 2) {
      return MatrixNavigationTarget.user(_normaliseUser(segments[1]));
    }
    if ((kind == 'r' || kind == 'room' || kind == 'roomid') &&
        segments.length >= 2) {
      final room = _normaliseRoom(segments[1]);
      if (segments.length >= 4 &&
          (segments[2] == 'e' || segments[2] == 'event')) {
        return MatrixNavigationTarget.event(room, _normaliseEvent(segments[3]));
      }
      return _targetForAction(room, uri.queryParameters['action']);
    }
    if (kind == 'roomalias' && segments.length >= 2) {
      final room = _normaliseAlias(segments[1]);
      return _targetForAction(room, uri.queryParameters['action']);
    }
    return null;
  }

  MatrixNavigationTarget? _parseMatrixTo(Uri uri) {
    var fragment = uri.fragment;
    if (fragment.startsWith('/')) fragment = fragment.substring(1);
    if (fragment.isEmpty) return null;

    final queryIndex = fragment.indexOf('?');
    final path = queryIndex < 0 ? fragment : fragment.substring(0, queryIndex);
    final query = queryIndex < 0
        ? const <String, String>{}
        : Uri.splitQueryString(fragment.substring(queryIndex + 1));
    final segments = path
        .split('/')
        .where((segment) => segment.isNotEmpty)
        .map(Uri.decodeComponent)
        .toList(growable: false);
    if (segments.isEmpty) return null;

    final first = segments.first;
    if (first.startsWith('@')) {
      return MatrixNavigationTarget.user(first);
    }
    if (!(first.startsWith('!') || first.startsWith('#'))) {
      return null;
    }

    if (segments.length >= 2 && segments[1].startsWith(r'$')) {
      return MatrixNavigationTarget.event(first, segments[1]);
    }
    return _targetForAction(first, query['action']);
  }

  static MatrixNavigationTarget _targetForAction(String room, String? action) {
    return switch (action?.toLowerCase()) {
      'join' || 'invite' => MatrixNavigationTarget.invite(room),
      'call' => MatrixNavigationTarget.call(room),
      _ => MatrixNavigationTarget.room(room),
    };
  }

  static String _normaliseUser(String value) =>
      value.startsWith('@') ? value : '@$value';

  static String _normaliseRoom(String value) =>
      value.startsWith('!') || value.startsWith('#') ? value : '!$value';

  static String _normaliseAlias(String value) =>
      value.startsWith('#') ? value : '#$value';

  static String _normaliseEvent(String value) =>
      value.startsWith(r'$') ? value : r'$' + value;
}
