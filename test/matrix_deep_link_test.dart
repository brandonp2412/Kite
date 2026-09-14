import 'package:flutter_test/flutter_test.dart';
import 'package:kite/matrix/matrix_deep_link.dart';

void main() {
  group('MatrixDeepLinkParser matrix: URI', () {
    test('parses room ids with routing servers', () {
      final link = MatrixDeepLinkParser.parse(
        'matrix:roomid/somewhere:example.org?via=one.example&via=two.example',
      );

      expect(link?.kind, MatrixDeepLinkKind.room);
      expect(link?.targetId, '!somewhere:example.org');
      expect(link?.viaServers, <String>['one.example', 'two.example']);
    });

    test('parses event permalinks', () {
      final link = MatrixDeepLinkParser.parse(
        'matrix:roomid/somewhere:example.org/e/event:example.org?via=one.example',
      );

      expect(link?.kind, MatrixDeepLinkKind.event);
      expect(link?.targetId, '!somewhere:example.org');
      expect(link?.eventId, r'$event:example.org');
    });

    test('keeps only valid action for the target kind', () {
      final user = MatrixDeepLinkParser.parse(
        'matrix:u/alice:example.org?action=chat',
      );
      final room = MatrixDeepLinkParser.parse(
        'matrix:r/community:example.org?action=join',
      );
      final invalidUserAction = MatrixDeepLinkParser.parse(
        'matrix:u/alice:example.org?action=join',
      );

      expect(user?.kind, MatrixDeepLinkKind.user);
      expect(user?.targetId, '@alice:example.org');
      expect(user?.action, MatrixDeepLinkAction.chat);
      expect(room?.targetId, '#community:example.org');
      expect(room?.action, MatrixDeepLinkAction.join);
      expect(invalidUserAction?.action, isNull);
    });

    test('accepts deprecated qualifiers for inbound compatibility', () {
      final link = MatrixDeepLinkParser.parse(
        'matrix:room/somewhere:example.org/event/event:example.org',
      );

      expect(link?.kind, MatrixDeepLinkKind.event);
      expect(link?.targetId, '#somewhere:example.org');
      expect(link?.eventId, r'$event:example.org');
    });
  });

  group('MatrixDeepLinkParser matrix.to', () {
    test('parses encoded room alias', () {
      final link = MatrixDeepLinkParser.parse(
        'https://matrix.to/#/%23somewhere%3Aexample.org',
      );

      expect(link?.kind, MatrixDeepLinkKind.room);
      expect(link?.targetId, '#somewhere:example.org');
    });

    test('parses room event and fragment query routing', () {
      final link = MatrixDeepLinkParser.parse(
        'https://matrix.to/#/%21somewhere%3Aexample.org/%24event%3Aexample.org?via=elsewhere.ca&via=second.example',
      );

      expect(link?.kind, MatrixDeepLinkKind.event);
      expect(link?.targetId, '!somewhere:example.org');
      expect(link?.eventId, r'$event:example.org');
      expect(link?.viaServers, <String>['elsewhere.ca', 'second.example']);
    });

    test('accepts historically unencoded identifiers', () {
      final link = MatrixDeepLinkParser.parse(
        'https://matrix.to/#/@alice:example.org',
      );

      expect(link?.kind, MatrixDeepLinkKind.user);
      expect(link?.targetId, '@alice:example.org');
    });
  });

  test('rejects unsupported and malformed links', () {
    expect(MatrixDeepLinkParser.parse('https://example.org/room'), isNull);
    expect(MatrixDeepLinkParser.parse('matrix:roomid/no-server'), isNull);
    expect(
      MatrixDeepLinkParser.parse('https://matrix.to/#/not-matrix'),
      isNull,
    );
  });
}
