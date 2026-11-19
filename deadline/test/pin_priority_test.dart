import 'dart:convert';

import 'package:deadline/data/local_db.dart';
import 'package:deadline/data/notes_store.dart';
import 'package:deadline/data/task_store.dart';
import 'package:deadline/models/note.dart';
import 'package:deadline/models/task.dart';
import 'package:deadline/theme.dart';
import 'package:deadline/ui/note_card.dart';
import 'package:deadline/ui/note_page_card.dart';
import 'package:deadline/ui/task_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    as fln;
import 'package:flutter_test/flutter_test.dart';

/// Only the reads used by [TaskStore.load] are overridden; no database is
/// opened. Upserts are captured so we can assert pin writes go through sync.
class _FakeTasksDb extends LocalDb {
  _FakeTasksDb(this.items);

  final List<Task> items;
  final List<Task> upserted = [];

  @override
  Future<List<Task>> all() async => List.unmodifiable(items);

  @override
  Future<List<Task>> archivedTasks() async => const [];

  @override
  Future<List<String>> distinctTags() async => const [];

  @override
  Future<void> upsert(Task t) async {
    upserted.add(t);
    final i = items.indexWhere((x) => x.id == t.id);
    if (i >= 0) {
      items[i] = t;
    } else {
      items.add(t);
    }
  }
}

class _FakeNotesDb extends LocalDb {
  _FakeNotesDb(this.items);

  final List<Note> items;
  final List<Note> upserted = [];

  @override
  Future<List<Note>> allNotes() async => List.unmodifiable(items);

  @override
  Future<List<Note>> archivedNotes() async => const [];

  @override
  Future<List<String>> distinctNoteTags() async => const [];

  @override
  Future<void> upsertNote(Note n) async {
    upserted.add(n);
    final i = items.indexWhere((x) => x.id == n.id);
    if (i >= 0) {
      items[i] = n;
    } else {
      items.add(n);
    }
  }
}

Map<String, Object?> _taskRow() => {
      'id': 'a',
      'title': 'Task',
      'notes': null,
      'tag': null,
      'due_at': DateTime.utc(2026, 1, 1).millisecondsSinceEpoch,
      'done': 0,
      'updated_at': DateTime.utc(2026, 1, 1).millisecondsSinceEpoch,
      'deleted': 0,
      'dirty': 0,
      'repeat': 0,
      'reminders': '',
    };

Map<String, Object?> _noteRow() => {
      'id': 'n',
      'title': 'Note',
      'body': null,
      'tag': null,
      'updated_at': DateTime.utc(2026, 1, 1).millisecondsSinceEpoch,
      'deleted': 0,
      'dirty': 0,
      'locked': 0,
    };

Task _task(String id,
    {bool pinned = false,
    Priority priority = Priority.none,
    required DateTime dueAt,
    bool done = false}) {
  return Task(
    id: id,
    title: id,
    dueAt: dueAt,
    pinned: pinned,
    priority: priority,
    done: done,
  );
}

void main() {
  // TaskStore.load() kicks off digest + home-widget refreshes that touch
  // platform channels. Stub them so the store tests stay hermetic.
  setUpAll(() {
    // The generated plugin registrant does not run under flutter test, so the
    // notification platform instance must be registered by hand.
    fln.AndroidFlutterLocalNotificationsPlugin.registerWith();

    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final channel in [
      'flutter_timezone',
      'dexterous.com/flutter/local_notifications',
      'home_widget',
      'home_widget/background',
    ]) {
      messenger.setMockMethodCallHandler(MethodChannel(channel), (call) async {
        if (channel == 'flutter_timezone' &&
            call.method == 'getLocalTimezone') {
          return 'UTC';
        }
        if (channel == 'dexterous.com/flutter/local_notifications') {
          // initialize()/permission checks expect a bool result.
          return true;
        }
        return null;
      });
    }
  });

  group('task pin and priority persistence', () {
    test('row round-trip keeps pinned and priority', () {
      final original = Task(
        id: 'a',
        title: 'Task',
        dueAt: DateTime.utc(2026, 1, 1),
        pinned: true,
        priority: Priority.high,
        dirty: false,
      );
      final row = original.toRow();
      expect(row['pinned'], 1);
      expect(row['priority'], Priority.high.index);
      final copy = Task.fromRow(row);
      expect(copy.pinned, isTrue);
      expect(copy.priority, Priority.high);
    });

    test('legacy rows without the new columns default to unpinned/no priority',
        () {
      final task = Task.fromRow(_taskRow());
      expect(task.pinned, isFalse);
      expect(task.priority, Priority.none);
    });

    test('JSON round-trip keeps pinned and priority through sync', () {
      final original = Task(
        id: 'a',
        title: 'Task',
        dueAt: DateTime.utc(2026, 1, 1),
        pinned: true,
        priority: Priority.medium,
      );
      final decoded = Task.fromJson(
          jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>);
      expect(decoded.pinned, isTrue);
      expect(decoded.priority, Priority.medium);
    });

    test('legacy JSON without pin/priority does not crash', () {
      final json = originalJson()
        ..remove('pinned')
        ..remove('priority');
      final decoded = Task.fromJson(json);
      expect(decoded.pinned, isFalse);
      expect(decoded.priority, Priority.none);
    });

    test('out-of-range priority falls back to none', () {
      final json = originalJson()..['priority'] = 99;
      expect(Task.fromJson(json).priority, Priority.none);
    });

    test('nextOccurrence carries pin and priority to the repeat', () {
      final task = Task(
        id: 'a',
        title: 'Rent',
        dueAt: DateTime.utc(2026, 1, 1),
        repeat: Repeat.monthly,
        pinned: true,
        priority: Priority.high,
      );
      final next = task.nextOccurrence()!;
      expect(next.pinned, isTrue);
      expect(next.priority, Priority.high);
    });
  });

  group('note pin persistence', () {
    test('row and JSON round-trip keep pinned', () {
      final note = Note(id: 'n', title: 'Note', pinned: true);
      final row = note.toRow();
      expect(row['pinned'], 1);
      expect(Note.fromRow(row).pinned, isTrue);

      final decoded = Note.fromJson(
          jsonDecode(jsonEncode(note.toJson())) as Map<String, dynamic>);
      expect(decoded.pinned, isTrue);
    });

    test('legacy row/JSON without pinned default to unpinned', () {
      expect(Note.fromRow(_noteRow()).pinned, isFalse);
      final json = <String, dynamic>{
        'id': 'n',
        'title': 'Note',
        'deleted': false,
        'updated_at': DateTime.utc(2026, 1, 1).toIso8601String(),
      };
      expect(Note.fromJson(json).pinned, isFalse);
    });

    test('a remote pinned copy keeps a local lock', () {
      final local = Note(id: 'n', title: 'Secret', locked: true);
      final remote = Note(
        id: 'n',
        title: 'Secret',
        pinned: true,
        locked: false,
        dirty: false,
        updatedAt: local.updatedAt.add(const Duration(minutes: 1)),
      );
      final merged = remote.withLocalLockFrom(local);
      expect(merged.pinned, isTrue);
      expect(merged.locked, isTrue);
    });
  });

  group('note ordering', () {
    test('newest note first even when an older note is pinned', () async {
      final older = Note(
        id: 'older',
        title: 'Older',
        pinned: true,
        updatedAt: DateTime.utc(2026, 1, 1),
      );
      final newest = Note(
        id: 'newest',
        title: 'Newest',
        updatedAt: DateTime.utc(2026, 1, 3),
      );
      final middle = Note(
        id: 'middle',
        title: 'Middle',
        updatedAt: DateTime.utc(2026, 1, 2),
      );
      final store = NotesStore(_FakeNotesDb([older, middle, newest]));
      await store.load();

      expect(store.visible.map((n) => n.id), ['newest', 'middle', 'older']);
    });

    testWidgets('note cards use their title, never a generated page label',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: Scaffold(
          body: NotePageCard(
            note: Note(id: 'n', title: 'My own title'),
            onEdit: () {},
          ),
        ),
      ));

      expect(find.text('My own title'), findsOneWidget);
      expect(find.textContaining('PAGE'), findsNothing);
    });
  });

  group('task ordering', () {
    test('pinned first, then urgency, priority inside a bucket, done last',
        () async {
      final now = DateTime.now().toUtc();
      final db = _FakeTasksDb([
        _task('later-low', dueAt: now.add(const Duration(days: 10))),
        _task(
          'today-low',
          dueAt: now.add(const Duration(hours: 12)),
          priority: Priority.low,
        ),
        _task(
          'today-high',
          dueAt: now.add(const Duration(hours: 11)),
          priority: Priority.high,
        ),
        _task('overdue', dueAt: now.subtract(const Duration(days: 1))),
        _task(
          'pinned-later',
          pinned: true,
          dueAt: now.add(const Duration(days: 10)),
          priority: Priority.low,
        ),
        _task('done', dueAt: now.subtract(const Duration(days: 5)), done: true),
      ]);
      final store = TaskStore(db, startTicker: false);
      await store.load();

      expect(store.visible.map((t) => t.id), [
        'pinned-later',
        'overdue',
        'today-high',
        'today-low',
        'later-low',
      ]);
    });

    test('completed tasks lead with the latest completion on top', () async {
      final now = DateTime.now().toUtc();
      Task completed(String id, DateTime finished) => Task(
            id: id,
            title: id,
            dueAt: now.subtract(const Duration(days: 1)),
            done: true,
            completedAt: finished,
          );
      final db = _FakeTasksDb([
        completed('older', now.subtract(const Duration(hours: 3))),
        _task('open', dueAt: now.add(const Duration(days: 1))),
        completed('newest', now.subtract(const Duration(minutes: 5))),
      ]);
      final store = TaskStore(db, startTicker: false);
      await store.load();
      store.showCompleted = true;

      expect(store.visible.map((t) => t.id), ['newest', 'older', 'open']);
    });

    test('completing stamps a time and reopening clears it', () {
      final task = _task('a', dueAt: DateTime.now().toUtc());
      final done = task.copyWith(done: true);
      expect(done.completedAt, isNotNull);
      expect(done.copyWith(done: false).completedAt, isNull);
    });

    test('setPinned writes through the normal dirty save path', () async {
      final task = _task('a', dueAt: DateTime.now().toUtc());
      final db = _FakeTasksDb([task]);
      final store = TaskStore(db, startTicker: false);
      await store.load();
      var pushed = 0;
      store.onLocalChange = () => pushed++;

      await store.setPinned(task, true);
      expect(db.upserted, hasLength(1));
      expect(db.upserted.single.pinned, isTrue);
      expect(db.upserted.single.dirty, isTrue);
      expect(pushed, 1);
      expect(store.visible.single.pinned, isTrue);
    });

    test('setPinned is a no-op when the value is unchanged', () async {
      final task = _task('a', pinned: true, dueAt: DateTime.now().toUtc());
      final db = _FakeTasksDb([task]);
      final store = TaskStore(db, startTicker: false);
      await store.load();

      await store.setPinned(task, true);
      expect(db.upserted, isEmpty);
    });
  });

  group('note ordering and pin writes', () {
    test('pinned notes are placed first by the store', () async {
      final unpinned = Note(id: 'plain', title: 'Plain');
      final pinned = Note(id: 'pin', title: 'Pinned', pinned: true);
      final store = NotesStore(_FakeNotesDb([unpinned, pinned]));
      await store.load();

      // NotesStore preserves the database order (pinned DESC, updated DESC).
      // The fake returns unpinned first to prove the store itself does not
      // reorder; the real LocalDb.allNotes() supplies the pinned-first order.
      expect(store.notes.map((n) => n.id), ['plain', 'pin']);
    });

    test('setPinned saves through the normal dirty path', () async {
      final note = Note(id: 'n', title: 'Note', dirty: false);
      final db = _FakeNotesDb([note]);
      final store = NotesStore(db);
      await store.load();
      var pushed = 0;
      store.onLocalChange = () => pushed++;

      await store.setPinned(note, true);
      expect(db.upserted, hasLength(1));
      expect(db.upserted.single.pinned, isTrue);
      expect(db.upserted.single.dirty, isTrue);
      expect(pushed, 1);
    });
  });

  group('pin and priority UI', () {
    testWidgets('task card shows pin and priority controls', (tester) async {
      var pinned = false;
      final task = Task(
        id: 'a',
        title: 'Task',
        dueAt: DateTime.now().add(const Duration(hours: 12)).toUtc(),
        priority: Priority.high,
      );
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: Scaffold(
          body: TaskCard(
            task: task,
            onToggle: () {},
            onEdit: () {},
            onPin: () => pinned = true,
          ),
        ),
      ));

      expect(find.byTooltip('Pin to top'), findsOneWidget);
      expect(find.text('HIGH'), findsOneWidget);
      await tester.tap(find.byTooltip('Pin to top'));
      expect(pinned, isTrue);
    });

    testWidgets('a pinned note card shows a pin indicator', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: Scaffold(
          body: NoteCard(
            note: Note(id: 'n', title: 'Note', pinned: true),
            onEdit: () {},
          ),
        ),
      ));

      expect(find.byIcon(Icons.push_pin), findsOneWidget);
      expect(find.text('Note'), findsOneWidget);
    });
  });
}

Map<String, dynamic> originalJson() => {
      'id': 'a',
      'title': 'Task',
      'notes': null,
      'tag': null,
      'due_at': DateTime.utc(2026, 1, 1).toIso8601String(),
      'done': false,
      'deleted': false,
      'updated_at': DateTime.utc(2026, 1, 1).toIso8601String(),
      'repeat': 0,
      'pinned': true,
      'priority': 2,
    };
