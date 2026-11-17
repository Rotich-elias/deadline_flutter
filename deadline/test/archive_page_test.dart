import 'package:deadline/data/local_db.dart';
import 'package:deadline/data/notes_store.dart';
import 'package:deadline/data/task_store.dart';
import 'package:deadline/models/note.dart';
import 'package:deadline/models/task.dart';
import 'package:deadline/theme.dart';
import 'package:deadline/ui/archive_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The page only reads [TaskStore.archived] and calls restore/purge, so the
/// database-backed parts of the real stores are not needed here.
class _FakeTaskStore extends TaskStore {
  _FakeTaskStore(this.items) : super(LocalDb(), startTicker: false);

  final List<Task> items;
  final List<Task> restored = [];
  final List<Task> purged = [];
  bool emptied = false;

  @override
  List<Task> get archived => List.unmodifiable(items);

  @override
  Future<void> restore(Task t) async {
    restored.add(t);
    items.remove(t);
    notifyListeners();
  }

  @override
  Future<void> purge(Task t) async {
    purged.add(t);
    items.remove(t);
    notifyListeners();
  }

  @override
  Future<void> emptyArchive() async {
    emptied = true;
    items.clear();
    notifyListeners();
  }
}

class _FakeNotesStore extends NotesStore {
  _FakeNotesStore(this.items) : super(LocalDb());

  final List<Note> items;
  final List<Note> restored = [];
  final List<Note> purged = [];
  bool emptied = false;

  @override
  List<Note> get archived => List.unmodifiable(items);

  @override
  Future<void> restore(Note n) async {
    restored.add(n);
    items.remove(n);
    notifyListeners();
  }

  @override
  Future<void> purge(Note n) async {
    purged.add(n);
    items.remove(n);
    notifyListeners();
  }

  @override
  Future<void> emptyArchive() async {
    emptied = true;
    items.clear();
    notifyListeners();
  }
}

Widget _wrap(Widget child) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.dark),
      home: child,
    );

Task _task() => Task(
      id: 't1',
      title: 'Lab report',
      notes: 'Include the graphs',
      tag: 'Physics',
      dueAt: DateTime.utc(2026, 11, 20),
      deleted: true,
      archivedAt: DateTime.utc(2026, 11, 16, 9, 30),
      updatedAt: DateTime.utc(2026, 11, 16, 9, 30),
    );

Note _note() => Note(
      id: 'n1',
      title: 'Reading list',
      body: 'Chapters 4 and 5',
      deleted: true,
      archivedAt: DateTime.utc(2026, 11, 16, 10),
      updatedAt: DateTime.utc(2026, 11, 16, 10),
    );

void main() {
  testWidgets('archive shows both kinds of deleted item', (tester) async {
    final tasks = _FakeTaskStore([_task()]);
    final notes = _FakeNotesStore([_note()]);
    addTearDown(tasks.dispose);

    await tester.pumpWidget(
      _wrap(ArchivePage(taskStore: tasks, notesStore: notes)),
    );

    expect(find.text('Archive'), findsOneWidget);
    expect(find.text('Deadlines (1)'), findsOneWidget);
    expect(find.text('Notes (1)'), findsOneWidget);
    expect(find.text('Lab report'), findsOneWidget);
    expect(find.text('PHYSICS'), findsOneWidget);

    await tester.tap(find.text('Notes (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Reading list'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('restoring a deadline puts it back in the live list',
      (tester) async {
    final task = _task();
    final tasks = _FakeTaskStore([task]);
    final notes = _FakeNotesStore([]);
    addTearDown(tasks.dispose);

    await tester.pumpWidget(
      _wrap(ArchivePage(taskStore: tasks, notesStore: notes)),
    );

    await tester.tap(find.text('Restore'));
    await tester.pump();

    expect(tasks.restored, [task]);
    expect(find.text('Restored "Lab report"'), findsOneWidget);
  });

  testWidgets('deleting forever asks for confirmation first', (tester) async {
    final task = _task();
    final tasks = _FakeTaskStore([task]);
    final notes = _FakeNotesStore([]);
    addTearDown(tasks.dispose);

    await tester.pumpWidget(
      _wrap(ArchivePage(taskStore: tasks, notesStore: notes)),
    );

    await tester.tap(find.byTooltip('Delete forever').hitTestable());
    await tester.pumpAndSettle();
    expect(find.text('Delete forever?'), findsOneWidget);
    expect(tasks.purged, isEmpty);

    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(tasks.purged, [task]);
  });

  testWidgets('cancelling keeps the archived item', (tester) async {
    final task = _task();
    final tasks = _FakeTaskStore([task]);
    final notes = _FakeNotesStore([]);
    addTearDown(tasks.dispose);

    await tester.pumpWidget(
      _wrap(ArchivePage(taskStore: tasks, notesStore: notes)),
    );

    await tester.tap(find.byTooltip('Delete forever').hitTestable());
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(tasks.purged, isEmpty);
    expect(find.text('Lab report'), findsOneWidget);
  });

  testWidgets('empty archive clears both stores after confirming',
      (tester) async {
    final tasks = _FakeTaskStore([_task()]);
    final notes = _FakeNotesStore([_note()]);
    addTearDown(tasks.dispose);

    await tester.pumpWidget(
      _wrap(ArchivePage(taskStore: tasks, notesStore: notes)),
    );

    await tester.tap(find.byTooltip('Empty archive'));
    await tester.pumpAndSettle();
    expect(find.text('Empty the archive?'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Empty'));
    await tester.pumpAndSettle();

    expect(tasks.emptied, isTrue);
    expect(notes.emptied, isTrue);
    expect(find.text('Nothing archived'), findsWidgets);
  });

  testWidgets('empty archive is disabled when there is nothing to clear',
      (tester) async {
    final tasks = _FakeTaskStore([]);
    final notes = _FakeNotesStore([]);
    addTearDown(tasks.dispose);

    await tester.pumpWidget(
      _wrap(ArchivePage(taskStore: tasks, notesStore: notes)),
    );

    final button = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.delete_sweep_outlined),
    );
    expect(button.onPressed, isNull);
    expect(find.text('Nothing archived'), findsWidgets);
  });
}
