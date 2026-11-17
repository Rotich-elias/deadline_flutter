import 'dart:convert';

import 'package:deadline/data/local_db.dart';
import 'package:deadline/data/notes_store.dart';
import 'package:deadline/models/note.dart';
import 'package:deadline/services/app_lock_service.dart';
import 'package:deadline/theme.dart';
import 'package:deadline/ui/note_card.dart';
import 'package:deadline/ui/pin_pad.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// [NotesStore.load] only needs these three reads; the database connection
/// itself is never opened.
class _FakeNotesDb extends LocalDb {
  _FakeNotesDb(this.items);

  final List<Note> items;

  @override
  Future<List<Note>> allNotes() async => items;

  @override
  Future<List<Note>> archivedNotes() async => const [];

  @override
  Future<List<String>> distinctNoteTags() async => const [];
}

Note _lockedNote() => Note(
      id: 'locked-1',
      title: 'Secret plans',
      body: 'Sensitive details',
      tag: 'private',
      locked: true,
    );

void main() {
  group('PIN hashing', () {
    test('is deterministic for the same salt', () {
      final first = AppLockService.hashPin('1234', 'salt-a');
      final second = AppLockService.hashPin('1234', 'salt-a');
      expect(first, second);
      expect(first, hasLength(64));
    });

    test('changes when the salt changes', () {
      final a = AppLockService.hashPin('1234', 'salt-a');
      final b = AppLockService.hashPin('1234', 'salt-b');
      expect(a, isNot(b));
    });

    test('changes when the PIN changes', () {
      final a = AppLockService.hashPin('1234', 'salt');
      final b = AppLockService.hashPin('4321', 'salt');
      expect(a, isNot(b));
    });
  });

  group('locked note persistence', () {
    test('lock survives a database row round-trip', () {
      final note = _lockedNote();
      final row = note.toRow();
      expect(row['locked'], 1);
      expect(Note.fromRow(row).locked, isTrue);
    });

    test('lock is never written to sync JSON', () {
      final json = _lockedNote().toJson();
      expect(json.containsKey('locked'), isFalse);
    });

    test('a remote payload cannot set the lock', () {
      final json = <String, dynamic>{
        ..._lockedNote().toJson(),
        'locked': true,
      };
      final remote = Note.fromJson(json);
      expect(remote.locked, isFalse);
    });

    test('a newer remote copy keeps the local lock and stays clean', () {
      final local = _lockedNote();
      final remote = Note(
        id: local.id,
        title: 'Edited on another phone',
        body: local.body,
        locked: false,
        dirty: false,
        updatedAt: local.updatedAt.add(const Duration(minutes: 1)),
      );

      final merged = remote.withLocalLockFrom(local);
      expect(merged.locked, isTrue);
      expect(merged.title, 'Edited on another phone');
      expect(merged.dirty, isFalse);
    });

    test('without a local lock the remote copy is unchanged', () {
      final remote = Note(id: 'n1', title: 'Remote', dirty: false);
      expect(remote.withLocalLockFrom(null).locked, isFalse);
      expect(
          remote
              .withLocalLockFrom(Note(id: 'n1', title: 'Local', locked: false))
              .locked,
          isFalse);
    });
  });

  group('search and the note list', () {
    test('a locked note is listed but never matches a search', () async {
      final store = NotesStore(_FakeNotesDb([
        _lockedNote(),
        Note(id: 'open-1', title: 'Money maker', body: 'money ideas'),
      ]));
      await store.load();
      expect(store.visible, hasLength(2));

      store.setQuery('money');
      expect(store.visible.map((n) => n.title), ['Money maker']);

      // Even a word from the locked title must not surface it.
      store.setQuery('secret');
      expect(store.visible, isEmpty);

      store.setQuery('');
      expect(store.visible, hasLength(2));
    });
  });

  group('lock UI', () {
    testWidgets('a locked card hides its title, body and tag', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: Scaffold(
          body: NoteCard(note: _lockedNote(), onEdit: () {}),
        ),
      ));

      expect(find.text('Locked note'), findsOneWidget);
      expect(find.text('Tap to unlock'), findsOneWidget);
      expect(find.text('Secret plans'), findsNothing);
      expect(find.text('Sensitive details'), findsNothing);
      expect(find.text('PRIVATE'), findsNothing);
    });

    testWidgets('an unlocked card still shows its content', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: Scaffold(
          body: NoteCard(
            note: Note(id: 'open', title: 'Visible title', body: 'Body text'),
            onEdit: () {},
          ),
        ),
      ));

      expect(find.text('Visible title'), findsOneWidget);
      expect(find.text('Body text'), findsOneWidget);
      expect(find.text('Locked note'), findsNothing);
    });

    testWidgets('the PIN pad rejects a wrong PIN then accepts the next try',
        (tester) async {
      var attempts = 0;
      String? accepted;

      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: Scaffold(
          body: PinPad(
            title: 'Enter PIN',
            popOnSuccess: false,
            validate: (pin) async {
              attempts++;
              return attempts == 1 ? 'Wrong PIN' : null;
            },
            onSuccess: (pin) => accepted = pin,
          ),
        ),
      ));

      Future<void> enter(String pin) async {
        for (final digit in pin.split('')) {
          await tester.tap(find.text(digit).last);
          await tester.pump();
        }
        await tester.pumpAndSettle();
      }

      await enter('1234');
      expect(attempts, 1);
      expect(find.text('Wrong PIN'), findsOneWidget);
      expect(accepted, isNull);

      await enter('1234');
      expect(attempts, 2);
      expect(accepted, '1234');
    });
  });

  group('sync payload', () {
    test('round-tripping JSON keeps notes unlocked', () {
      final note = Note(id: 'n1', title: 'Plain', body: 'Body');
      final decoded = Note.fromJson(
          jsonDecode(jsonEncode(note.toJson())) as Map<String, dynamic>);
      expect(decoded.locked, isFalse);
      expect(decoded.title, 'Plain');
      expect(decoded.body, 'Body');
    });
  });
}
