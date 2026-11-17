import 'package:deadline/data/local_db.dart';
import 'package:deadline/data/notes_store.dart';
import 'package:deadline/models/note.dart';
import 'package:deadline/services/app_lock_service.dart';
import 'package:deadline/theme.dart';
import 'package:deadline/ui/note_form_sheet.dart';
import 'package:deadline/ui/note_view_page.dart';
import 'package:deadline/utils/list_continuation.dart';
import 'package:deadline/utils/markup.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryNotesDb extends LocalDb {
  _MemoryNotesDb(this._notes);

  final List<Note> _notes;

  @override
  Future<List<Note>> allNotes() async => List.unmodifiable(_notes);

  @override
  Future<List<Note>> archivedNotes() async => const [];

  @override
  Future<List<String>> distinctNoteTags() async => const [];

  @override
  Future<void> upsertNote(Note n) async {
    final index = _notes.indexWhere((item) => item.id == n.id);
    if (index < 0) {
      _notes.add(n);
    } else {
      _notes[index] = n;
    }
  }
}

void main() {
  group('note checklist markup', () {
    test('checkbox lines parse and toggle without touching other lines', () {
      final parsed = parseChecklistLine('- [ ] Buy <b>milk</b>');
      expect(parsed, isNotNull);
      expect(parsed!.checked, isFalse);
      expect(parsed.text, 'Buy <b>milk</b>');

      expect(toggleChecklistLine('- [ ] Buy milk'), '- [x] Buy milk');
      expect(toggleChecklistLine('  - [X] Buy milk'), '  - [ ] Buy milk');
      expect(toggleChecklistLineAt('- [ ] A\nplain\n- [x] B', 2),
          '- [ ] A\nplain\n- [ ] B');
      expect(toggleChecklistLineAt('- [ ] A\nplain', 1), '- [ ] A\nplain');
    });

    test('old handwritten bracket notes stay literal', () {
      expect(parseChecklistLine('[  ] Parks and recreation'), isNull);
      expect(parseChecklistLine('[v] Other mommy'), isNull);
      expect(stripMarkup('[  ] Parks and recreation'),
          '[  ] Parks and recreation');
      expect(stripMarkup('[v] Other mommy'), '[v] Other mommy');
    });

    test('previews and search show tick boxes instead of raw markers', () {
      const body = '- [ ] Buy <b>milk</b>\n- [x] Pay rent';
      expect(stripMarkup(body), '☐ Buy milk\n☑ Pay rent');
      expect(Note(id: 'n', title: 'N', body: body).plainBody,
          '☐ Buy milk\n☑ Pay rent');
    });

    test('the caret action creates a checklist line then ticks it', () {
      final added = toggleChecklistAtCaret('one\ntwo', 5);
      expect(added.text, 'one\n- [ ] two');

      final checked = toggleChecklistAtCaret(added.text, added.start);
      expect(checked.text, 'one\n- [x] two');

      final reverted = toggleChecklistAtCaret(checked.text, checked.start);
      expect(reverted.text, 'one\n- [ ] two');
    });

    test('an existing bullet becomes a checklist instead of doubling', () {
      final result = toggleChecklistAtCaret('- milk', 6);
      expect(result.text, '- [ ] milk');
    });
  });

  group('note checklist UI', () {
    testWidgets('the editor checkbox turns a line into a checklist item',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      Note? saved;
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async => saved = await showNoteForm(context),
              child: const Text('Open form'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('Open form'));
      await tester.pumpAndSettle();
      final title = find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.hintText == 'Title');
      await tester.enterText(title, 'Groceries');
      final body = find.byWidgetPredicate((w) =>
          w is TextField && w.decoration?.hintText == 'Write something…');
      await tester.enterText(body, 'Buy milk');

      final checkbox = find.byKey(const Key('note-checklist-checkbox'));
      expect(checkbox, findsOneWidget);
      await tester.tap(checkbox);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(body).controller!.text, '- [ ] Buy milk');

      await tester.tap(checkbox);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(body).controller!.text, '- [x] Buy milk');

      final save = find.text('Add note');
      await tester.ensureVisible(save);
      await tester.pumpAndSettle();
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(saved!.body, '- [x] Buy milk');
    });

    testWidgets('tapping a reader checkbox saves the ticked note',
        (tester) async {
      final note = Note(
        id: 'trip',
        title: 'Trip',
        body: '- [x] Passport\n- [ ] Tickets',
        dirty: false,
      );
      final store = NotesStore(_MemoryNotesDb([note]));
      await store.load();

      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: NoteViewPage(
          store: store,
          noteId: note.id,
          appLock: AppLockService(),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Passport'), findsOneWidget);
      expect(find.text('Tickets'), findsOneWidget);
      final boxes = find.byType(Checkbox);
      expect(boxes, findsNWidgets(2));
      expect(boxes.evaluate().map((e) => (e.widget as Checkbox).value),
          [true, false]);

      await tester.tap(find.byKey(const Key('note-checklist-box-1')));
      await tester.pumpAndSettle();
      expect(store.notes.single.body, '- [x] Passport\n- [x] Tickets');
      expect(store.notes.single.dirty, isTrue);
    });
  });

  group('note list continuation', () {
    test('Enter continues checklist and bullet lines', () {
      final check = continueListAtCaret('- [ ] One', 9);
      expect(check!.text, '- [ ] One\n- [ ] ');
      expect(check.selection, 16);

      final done = continueListAtCaret('- [x] Done', 10);
      expect(done!.text, '- [x] Done\n- [ ] ');

      final bullet = continueListAtCaret('- first', 7);
      expect(bullet!.text, '- first\n- ');

      final indented = continueListAtCaret('  * item', 8);
      expect(indented!.text, '  * item\n  * ');
    });

    test('Enter on an empty item closes the list', () {
      expect(continueListAtCaret('- [ ] ', 6), (text: '', selection: 0));
      expect(continueListAtCaret('- ', 2), (text: '', selection: 0));
      expect(continueListAtCaret('one\n- [ ] \ntwo', 10),
          (text: 'one\n\ntwo', selection: 4));
    });

    test('splitting a line keeps the marker on both halves', () {
      final result = continueListAtCaret('- [ ] Buy milk', 10);
      expect(result!.text, '- [ ] Buy \n- [ ] milk');
      expect(result.selection, 17);
    });

    test('ordinary lines and caret positions inside a marker are untouched',
        () {
      expect(continueListAtCaret('plain text', 10), isNull);
      expect(continueListAtCaret('- [ ] One', 2), isNull);
    });

    test('the formatter rewrites a soft-keyboard newline', () {
      final formatter = ListContinuationFormatter();
      const old = TextEditingValue(
        text: '- [ ] One',
        selection: TextSelection.collapsed(offset: 9),
      );
      const proposed = TextEditingValue(
        text: '- [ ] One\n',
        selection: TextSelection.collapsed(offset: 10),
      );
      final result = formatter.formatEditUpdate(old, proposed);
      expect(result.text, '- [ ] One\n- [ ] ');
      expect(result.selection.baseOffset, 16);

      const plainOld = TextEditingValue(
        text: 'plain',
        selection: TextSelection.collapsed(offset: 5),
      );
      const plainNew = TextEditingValue(
        text: 'plain\n',
        selection: TextSelection.collapsed(offset: 6),
      );
      expect(formatter.formatEditUpdate(plainOld, plainNew).text, 'plain\n');

      const paste = TextEditingValue(
        text: '- [ ] One\nPast\nTwo',
        selection: TextSelection.collapsed(offset: 20),
      );
      expect(formatter.formatEditUpdate(old, paste).text, paste.text);
    });

    testWidgets('Enter in the editor continues then closes a checklist',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async => await showNoteForm(context),
              child: const Text('Open form'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('Open form'));
      await tester.pumpAndSettle();
      final body = find.byWidgetPredicate((w) =>
          w is TextField && w.decoration?.hintText == 'Write something…');
      await tester.enterText(body, '- [ ] One');
      await tester.pumpAndSettle();
      await tester.enterText(body, '- [ ] One\n');
      await tester.pumpAndSettle();
      expect(
          tester.widget<TextField>(body).controller!.text, '- [ ] One\n- [ ] ');

      await tester.enterText(body, '- [ ] One\n- [ ] \n');
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(body).controller!.text, '- [ ] One\n');
    });
  });
}
