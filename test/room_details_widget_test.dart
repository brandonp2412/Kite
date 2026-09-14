import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kite/app/kite_app.dart';
import 'package:kite/features/rooms/room_members.dart';

void main() {
  testWidgets('room details exposes deterministic member search and profile', (
    tester,
  ) async {
    selectRoom('kite');
    await tester.pumpWidget(const KiteApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('room-details-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('room-details-screen')), findsOneWidget);
    expect(find.byKey(const Key('member-list')), findsOneWidget);
    expect(find.text('Administrator'), findsOneWidget);
    expect(find.text('Moderator'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('member-search')), 'bob');
    await tester.pump();

    expect(find.byKey(const Key('member-@bob:example.org')), findsOneWidget);
    expect(find.byKey(const Key('member-@alice:example.org')), findsNothing);

    await tester.tap(find.byKey(const Key('member-@bob:example.org')));
    await tester.pumpAndSettle();

    final sheet = find.byKey(const Key('member-profile-sheet'));
    expect(sheet, findsOneWidget);
    expect(
      find.descendant(of: sheet, matching: find.text('@bob:example.org')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: sheet, matching: find.text('Power 0')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('member-promote')))
          .onPressed,
      isNotNull,
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('member-kick')))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('promote and kick actions update the member list', (
    tester,
  ) async {
    selectRoom('kite');
    await tester.pumpWidget(const KiteApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('room-details-button')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('member-search')), 'bob');
    await tester.pump();
    await tester.tap(find.byKey(const Key('member-@bob:example.org')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('member-promote')));
    await tester.pump();
    final sheet = find.byKey(const Key('member-profile-sheet'));
    expect(
      find.descendant(of: sheet, matching: find.text('Power 50')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: sheet,
        matching: find.text(RoomMemberRole.moderator.label),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('member-kick')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('member-kick-confirm')), findsOneWidget);
    expect(find.byKey(const Key('member-profile-sheet')), findsOneWidget);
    expect(find.byKey(const Key('member-@bob:example.org')), findsOneWidget);

    await tester.tap(find.byKey(const Key('member-kick-cancel')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('member-kick-confirm')), findsNothing);
    expect(find.byKey(const Key('member-kick')), findsOneWidget);
    expect(find.byKey(const Key('member-profile-sheet')), findsOneWidget);
    expect(find.byKey(const Key('member-@bob:example.org')), findsOneWidget);

    await tester.tap(find.byKey(const Key('member-kick')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('member-kick-confirm')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('member-kick-confirm')), findsNothing);
    expect(find.byKey(const Key('member-profile-sheet')), findsNothing);
    expect(find.byKey(const Key('member-@bob:example.org')), findsNothing);
    expect(find.byKey(const Key('member-search-empty')), findsOneWidget);
  });

  testWidgets('moderation controls are disabled for self and equal power', (
    tester,
  ) async {
    selectRoom('kite');
    await tester.pumpWidget(const KiteApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('room-details-button')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('member-${RoomMembersFixture.currentUserId}')),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('member-promote')))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('member-demote')))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('member-kick')))
          .onPressed,
      isNull,
    );
  });
}
