import 'package:deadline/data/local_db.dart';
import 'package:deadline/data/notes_store.dart';
import 'package:deadline/data/task_store.dart';
import 'package:deadline/models/note.dart';
import 'package:deadline/models/task.dart';
import 'package:deadline/utils/search.dart';
import 'package:flutter_test/flutter_test.dart';

Task _task(String title, {String? notes, String? tag}) => Task.create(
      title: title,
      dueAtLocal: DateTime(2026, 11, 20, 17),
      notes: notes,
      tag: tag,
    );

void main() {
  group('filterByQuery on deadlines', () {
    final tasks = [
      _task('Build your own website',
          notes: 'Flutter and Laravel', tag: 'work'),
      _task("Go for dad's shoes", tag: 'family'),
      _task('Renew passport'),
    ];

    List<Task> search(String query) =>
        filterByQuery(tasks, query, (t) => [t.title, t.notes, t.tag]);

    test('matches titles case-insensitively', () {
      expect(search('WEBSITE').map((t) => t.title), ['Build your own website']);
    });

    test('matches the notes field', () {
      expect(search('laravel').map((t) => t.title), ['Build your own website']);
    });

    test('matches a tag', () {
      expect(search('family').map((t) => t.title), ["Go for dad's shoes"]);
    });

    test('a blank query keeps every task', () {
      expect(search(''), hasLength(3));
      expect(search('   '), hasLength(3));
    });

    test('trims the query before matching', () {
      expect(search('  passport ').map((t) => t.title), ['Renew passport']);
    });

    test('returns nothing when there is no match', () {
      expect(search('dentist'), isEmpty);
    });
  });

  group('filterByQuery on notes', () {
    final notes = [
      Note.create(
          title: 'Money maker',
          body: 'Build nursery animated videos',
          tag: 'ideas'),
      Note.create(title: 'Dear future me', body: 'Humble empire pics'),
    ];

    List<Note> search(String query) =>
        filterByQuery(notes, query, (n) => [n.title, n.body, n.tag]);

    test('matches a note title', () {
      expect(search('future').map((n) => n.title), ['Dear future me']);
    });

    test('matches the note body', () {
      expect(search('nursery').map((n) => n.title), ['Money maker']);
    });

    test('matches a note tag', () {
      expect(search('ideas').map((n) => n.title), ['Money maker']);
    });

    test('no match returns an empty list', () {
      expect(search('groceries'), isEmpty);
    });
  });

  group('store search state', () {
    test('task store trims the query and only notifies on a change', () {
      final store = TaskStore(LocalDb(), startTicker: false);
      var notified = 0;
      store.addListener(() => notified++);

      store.setQuery('  shoes  ');
      expect(store.query, 'shoes');
      expect(notified, 1);

      store.setQuery('shoes');
      expect(notified, 1, reason: 'identical query should not repaint');

      store.setQuery('');
      expect(store.query, isEmpty);
      expect(notified, 2);
    });

    test('notes store trims the query and only notifies on a change', () {
      final store = NotesStore(LocalDb());
      var notified = 0;
      store.addListener(() => notified++);

      store.setQuery(' money ');
      expect(store.query, 'money');
      expect(notified, 1);

      store.setQuery('money');
      expect(notified, 1);
    });
  });
}
