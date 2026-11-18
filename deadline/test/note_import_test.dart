import 'package:deadline/data/local_db.dart';
import 'package:deadline/data/notes_store.dart';
import 'package:deadline/models/note.dart';
import 'package:deadline/services/note_import.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeNotesStore extends NotesStore {
  _FakeNotesStore(this._all) : super(LocalDb());

  final List<Note> _all;
  final List<Note> added = [];
  final List<Note> saved = [];
  final List<Note> purged = [];

  @override
  List<Note> get notes => List.unmodifiable(_all);

  @override
  List<Note> get archived => const [];

  @override
  Future<void> add(Note n) async {
    added.add(n);
    _all.add(n);
  }

  @override
  Future<void> save(Note n) async {
    saved.add(n);
    final i = _all.indexWhere((old) => old.id == n.id);
    if (i >= 0) _all[i] = n;
  }

  @override
  Future<void> purge(Note n) async {
    purged.add(n);
    _all.removeWhere((old) => old.id == n.id);
  }
}

void main() {
  group('parsing shared Samsung Notes text', () {
    test('first line is the title, the rest is the body', () {
      final parsed = NoteImport.parse(
        'Jobs to be paid\nVoke = 5k +1k\nCynthia aus 4500',
      );
      expect(parsed!.title, 'Jobs to be paid');
      expect(parsed.body, 'Voke = 5k +1k\nCynthia aus 4500');
    });

    test('single-line notes have no body', () {
      final parsed = NoteImport.parse('Books idea');
      expect(parsed!.title, 'Books idea');
      expect(parsed.body, isNull);
    });

    test('blank notes are ignored', () {
      expect(NoteImport.parse(''), isNull);
      expect(NoteImport.parse('  \n\n\t\n'), isNull);
    });

    test('handles BOM, CRLF, blank leading lines and direction marks', () {
      final parsed = NoteImport.parse(
        '\ufeff\n\n\u200eSCHOOL OF THOUGHTS\r\nFirst point\r\nSecond point',
      );
      expect(parsed!.title, 'SCHOOL OF THOUGHTS');
      expect(parsed.body, 'First point\nSecond point');
    });

    test('keeps blank lines inside the body', () {
      final parsed = NoteImport.parse('Title\n\npara one\n\npara two\n');
      expect(parsed!.body, 'para one\n\npara two');
    });

    test('collapses whitespace in the title', () {
      final parsed = NoteImport.parse('  My    weekend   plans  \nStuff');
      expect(parsed!.title, 'My weekend plans');
      expect(parsed.body, 'Stuff');
    });

    test('a very long first line is split into title and body', () {
      final long = List.filled(40, 'word').join(' '); // 199 characters
      final parsed = NoteImport.parse(long);

      expect(parsed!.title.length, lessThanOrEqualTo(120));
      expect(parsed.title.endsWith(' '), isFalse);
      expect(parsed.body, isNotNull);
      expect('${parsed.title} ${parsed.body}', long);
    });

    test('uses the shared file name as the title when it adds information', () {
      // Samsung Notes keeps the title out of its text export and names the
      // file after the note instead.
      final parsed = NoteImport.parse(
        '[ ] Voke = 5k +1k\n[ ] Cynthia aus 4500',
        name: 'Jobs to be paid.txt',
      );

      expect(parsed!.title, 'Jobs to be paid');
      expect(parsed.body, '[ ] Voke = 5k +1k\n[ ] Cynthia aus 4500');
    });

    test('keeps the first line as title when the file name is generic', () {
      for (final name in ['text.txt', 'Samsung Notes.txt', 'note.txt']) {
        final parsed = NoteImport.parse('Real title\nbody', name: name);
        expect(parsed!.title, 'Real title', reason: name);
        expect(parsed.body, 'body', reason: name);
      }
    });

    test('does not repeat a title the exported text already starts with', () {
      final parsed = NoteImport.parse(
        'Jobs to be paid\nVoke = 5k',
        name: 'Jobs to be paid.txt',
      );

      expect(parsed!.title, 'Jobs to be paid');
      expect(parsed.body, 'Voke = 5k');
    });

    test('strips folders and the .txt extension from the shared name', () {
      final parsed = NoteImport.parse('body text', name: '/cache/My note.txt');
      expect(parsed!.title, 'My note');
      expect(parsed.body, 'body text');
    });

    test('strips the Samsung Notes timestamp from the export file name', () {
      final parsed = NoteImport.parse(
        'If I was God for a day',
        name: 'Books idea_260708_045209.txt',
      );
      expect(parsed!.title, 'Books idea');
      expect(parsed.body, 'If I was God for a day');
    });

    test('falls back to the first line for a timestamp-only name', () {
      final parsed = NoteImport.parse(
        'Shopping list\nSugar\nMilk',
        name: 'Notes_240429_030544.txt',
      );
      expect(parsed!.title, 'Shopping list');
      expect(parsed.body, 'Sugar\nMilk');
    });

    test('ignores the copy suffix Samsung adds to a repeated export', () {
      final parsed = NoteImport.parse(
        'If I was God for a day',
        name: 'Books idea_260708_045209 (1).txt',
      );
      expect(parsed!.title, 'Books idea');
      expect(parsed.body, 'If I was God for a day');
    });
  });

  group('repairing older imports', () {
    test('renames timestamped titles without touching other notes', () async {
      final store = _FakeNotesStore([
        Note.create(title: 'Movies list _261011_141605', body: 'The Office'),
        Note.create(title: 'My own note', body: 'unchanged'),
      ]);

      final repaired = await NoteImport.repairLegacyTitles(store);

      expect(repaired, 1);
      expect(store.saved.single.title, 'Movies list');
      expect(store.notes.last.title, 'My own note');
    });

    test('uses the first body line when only "Notes" prefixes the title',
        () async {
      final store = _FakeNotesStore([
        Note.create(title: 'Notes_230116_092550', body: 'Leseru fees\nKCB'),
      ]);

      await NoteImport.repairLegacyTitles(store);

      expect(store.saved.single.title, 'Leseru fees');
      expect(store.saved.single.body, 'KCB');
    });

    test('a repaired note is not duplicated by a fresh share of the same file',
        () async {
      final store = _FakeNotesStore([
        Note.create(
            title: 'Notes_240429_030544', body: 'Shopping list\nSugar\nMilk'),
      ]);
      await NoteImport.repairLegacyTitles(store);

      final outcome = await NoteImport.importAll(store, const [
        SharedNote('Shopping list\nSugar\nMilk',
            name: 'Notes_240429_030544.txt'),
      ]);

      expect(outcome.imported, 0);
      expect(outcome.duplicates, 1);
    });

    test('purges the newer copy left by a repeated Samsung export', () async {
      final original = Note(
        id: 'old',
        title: 'Shopping list',
        body: 'Sugar\nMilk',
        updatedAt: DateTime.utc(2026, 11, 18, 7),
      );
      final duplicate = Note(
        id: 'new',
        title: 'Notes_240429_030544 (1)',
        body: 'Shopping list\nSugar\nMilk',
        updatedAt: DateTime.utc(2026, 11, 18, 9),
      );
      final store = _FakeNotesStore([original, duplicate]);

      await NoteImport.repairLegacyTitles(store);

      expect(store.purged.single.id, 'new');
      expect(store.notes.map((n) => n.id), ['old']);
      expect(store.saved, isEmpty);
    });
  });

  group('importing into the notes store', () {
    test('skips duplicates and blanks, adds the rest', () async {
      final store = _FakeNotesStore([
        Note.create(title: 'Existing', body: 'keep me'),
      ]);

      final outcome = await NoteImport.importAll(store, [
        const SharedNote('Existing\nkeep me'),
        const SharedNote('Fresh note\nwith some detail'),
        const SharedNote('   '),
        const SharedNote('Another\none'),
      ]);

      expect(outcome.imported, 2);
      expect(outcome.duplicates, 1);
      expect(store.added.map((n) => n.title), ['Fresh note', 'Another']);
      expect(store.added.first.body, 'with some detail');
    });

    test('duplicates inside one share are only added once', () async {
      final store = _FakeNotesStore([]);

      final outcome = await NoteImport.importAll(store, const [
        SharedNote('Same note\nbody'),
        SharedNote('Same note\nbody'),
      ]);

      expect(outcome.imported, 1);
      expect(outcome.duplicates, 1);
      expect(store.added, hasLength(1));
    });
  });
}
