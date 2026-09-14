enum MatrixDeepLinkKind { room, event, user }

enum MatrixDeepLinkAction { join, chat }

/// Protocol-level Matrix deep-link target.
///
/// UI navigation remains outside this type: it normalises both the Matrix URI
/// scheme and matrix.to links into one deterministic routing input.
final class MatrixDeepLink {
  const MatrixDeepLink({
    required this.kind,
    required this.targetId,
    this.eventId,
    this.action,
    this.viaServers = const <String>[],
  });

  final MatrixDeepLinkKind kind;
  final String targetId;
  final String? eventId;
  final MatrixDeepLinkAction? action;
  final List<String> viaServers;
}

/// Parses Matrix links according to the Matrix URI/matrix.to specification.
abstract final class MatrixDeepLinkParser {
  static MatrixDeepLink? parse(String raw) {
    final uri = Uri.tryParse(raw);
    if (uri == null) return null;

    if (uri.scheme == 'matrix') {
      return _parseMatrixUri(uri);
    }
    if ((uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.host.toLowerCase() == 'matrix.to') {
      return _parseMatrixTo(uri);
    }
    return null;
  }

  static MatrixDeepLink? _parseMatrixUri(Uri uri) {
    final segments = uri.pathSegments
        .where((segment) => segment.isNotEmpty)
        .map(Uri.decodeComponent)
        .toList(growable: false);
    if (segments.length < 2) return null;

    final qualifier = segments[0];
    final id = segments[1];
    final action = _action(uri.queryParameters['action']);
    final via = List<String>.unmodifiable(
      uri.queryParametersAll['via'] ?? const <String>[],
    );

    switch (qualifier) {
      case 'u':
      case 'user':
        return _user('@$id', action: action, via: via);
      case 'r':
      case 'room':
        if (segments.length >= 4 &&
            (segments[2] == 'e' || segments[2] == 'event')) {
          return _event('#$id', '\$${segments[3]}', action: action, via: via);
        }
        return _room('#$id', action: action, via: via);
      case 'roomid':
        if (segments.length >= 4 &&
            (segments[2] == 'e' || segments[2] == 'event')) {
          return _event('!$id', '\$${segments[3]}', action: action, via: via);
        }
        return _room('!$id', action: action, via: via);
      default:
        return null;
    }
  }

  static MatrixDeepLink? _parseMatrixTo(Uri uri) {
    var fragment = uri.fragment;
    if (!fragment.startsWith('/')) return null;
    fragment = fragment.substring(1);

    final queryIndex = fragment.indexOf('?');
    final path = queryIndex == -1
        ? fragment
        : fragment.substring(0, queryIndex);
    final query = queryIndex == -1 ? '' : fragment.substring(queryIndex + 1);
    final segments = path
        .split('/')
        .where((segment) => segment.isNotEmpty)
        .map(Uri.decodeComponent)
        .toList(growable: false);
    if (segments.isEmpty) return null;

    final parameters = Uri(query: query).queryParametersAll;
    final action = _action(parameters['action']?.lastOrNull);
    final via = List<String>.unmodifiable(
      parameters['via'] ?? const <String>[],
    );
    final target = segments[0];

    if (target.startsWith('@')) {
      return _user(target, action: action, via: via);
    }
    if (target.startsWith('!') || target.startsWith('#')) {
      if (segments.length >= 2) {
        return _event(target, segments[1], action: action, via: via);
      }
      return _room(target, action: action, via: via);
    }
    return null;
  }

  static MatrixDeepLink? _room(
    String roomId, {
    required MatrixDeepLinkAction? action,
    required List<String> via,
  }) {
    if (!_validNamespacedId(roomId, <String>{'!', '#'})) return null;
    return MatrixDeepLink(
      kind: MatrixDeepLinkKind.room,
      targetId: roomId,
      action: action == MatrixDeepLinkAction.join ? action : null,
      viaServers: via,
    );
  }

  static MatrixDeepLink? _event(
    String roomId,
    String eventId, {
    required MatrixDeepLinkAction? action,
    required List<String> via,
  }) {
    if (!_validNamespacedId(roomId, <String>{'!', '#'}) ||
        !eventId.startsWith(r'$') ||
        eventId.length < 2) {
      return null;
    }
    return MatrixDeepLink(
      kind: MatrixDeepLinkKind.event,
      targetId: roomId,
      eventId: eventId,
      action: action == MatrixDeepLinkAction.join ? action : null,
      viaServers: via,
    );
  }

  static MatrixDeepLink? _user(
    String userId, {
    required MatrixDeepLinkAction? action,
    required List<String> via,
  }) {
    if (!_validNamespacedId(userId, <String>{'@'})) return null;
    return MatrixDeepLink(
      kind: MatrixDeepLinkKind.user,
      targetId: userId,
      action: action == MatrixDeepLinkAction.chat ? action : null,
      viaServers: via,
    );
  }

  static MatrixDeepLinkAction? _action(String? value) => switch (value) {
    'join' => MatrixDeepLinkAction.join,
    'chat' => MatrixDeepLinkAction.chat,
    _ => null,
  };

  static bool _validNamespacedId(String value, Set<String> sigils) {
    if (value.length < 4 || !sigils.contains(value[0])) return false;
    final separator = value.indexOf(':', 1);
    return separator > 1 && separator < value.length - 1;
  }
}

extension on List<String> {
  String? get lastOrNull => isEmpty ? null : last;
}
