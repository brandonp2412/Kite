import 'dart:async';

enum MatrixNavigationKind { home, room, event, thread, user, invite, call }

final class MatrixNavigationTarget {
  const MatrixNavigationTarget._({
    required this.kind,
    this.roomIdOrAlias,
    this.eventId,
    this.threadRootEventId,
    this.userId,
    this.callId,
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

  const MatrixNavigationTarget.thread(
    String roomIdOrAlias,
    String eventId,
    String threadRootEventId,
  ) : this._(
        kind: MatrixNavigationKind.thread,
        roomIdOrAlias: roomIdOrAlias,
        eventId: eventId,
        threadRootEventId: threadRootEventId,
      );

  const MatrixNavigationTarget.user(String userId)
    : this._(kind: MatrixNavigationKind.user, userId: userId);

  const MatrixNavigationTarget.invite(String roomIdOrAlias)
    : this._(kind: MatrixNavigationKind.invite, roomIdOrAlias: roomIdOrAlias);

  const MatrixNavigationTarget.call(String roomIdOrAlias, {String? callId})
    : this._(
        kind: MatrixNavigationKind.call,
        roomIdOrAlias: roomIdOrAlias,
        callId: callId,
      );

  final MatrixNavigationKind kind;
  final String? roomIdOrAlias;
  final String? eventId;
  final String? threadRootEventId;
  final String? userId;
  final String? callId;

  @override
  bool operator ==(Object other) {
    return other is MatrixNavigationTarget &&
        other.kind == kind &&
        other.roomIdOrAlias == roomIdOrAlias &&
        other.eventId == eventId &&
        other.threadRootEventId == threadRootEventId &&
        other.userId == userId &&
        other.callId == callId;
  }

  @override
  int get hashCode => Object.hash(
    kind,
    roomIdOrAlias,
    eventId,
    threadRootEventId,
    userId,
    callId,
  );
}

typedef MatrixNavigationHandler = FutureOr<void> Function(
  MatrixNavigationTarget target,
);

final class MatrixDeepLinkRouter {
  const MatrixDeepLinkRouter({
    this.parser = const MatrixDeepLinkParser(),
    required this.navigate,
  });

  final MatrixDeepLinkParser parser;
  final MatrixNavigationHandler navigate;

  Future<bool> route(Uri uri) async {
    final target = parser.parse(uri);
    if (target == null) return false;
    await navigate(target);
    return true;
  }
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
    late final Map<String, String> query;
    try {
      query = queryIndex < 0
          ? const <String, String>{}
          : Uri.splitQueryString(fragment.substring(queryIndex + 1));
    } on FormatException {
      return null;
    }
    final segments = _decodeSegments(
      path.split('/').where((segment) => segment.isNotEmpty),
    );
    if (segments == null || segments.isEmpty) return null;

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

  static List<String>? _decodeSegments(Iterable<String> encodedSegments) {
    final decoded = <String>[];
    try {
      for (final segment in encodedSegments) {
        decoded.add(Uri.decodeComponent(segment));
      }
    } on FormatException {
      return null;
    }
    return List<String>.unmodifiable(decoded);
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
