import 'dart:convert';

import 'package:deadline/data/local_db.dart';
import 'package:deadline/data/task_store.dart';
import 'package:deadline/models/task.dart';
import 'package:deadline/theme.dart';
import 'package:deadline/ui/task_card.dart';
import 'package:deadline/ui/task_form_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    as fln;
import 'package:flutter_test/flutter_test.dart';

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

Map<String, Object?> _taskRow({Object? checklist}) => {
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
      if (checklist != null) 'checklist': checklist,
    };

List<ChecklistItem> _items() => const [
      ChecklistItem(id: 'one', title: 'First step', done: true),
      ChecklistItem(id: 'two', title: 'Second step'),
    ];

Task _task(String id, {List<ChecklistItem> checklist = const []}) => Task(
      id: id,
      title: id,
      dueAt: DateTime.utc(2026, 1, 1),
      checklist: checklist,
    );

void main() {
  setUpAll(() {
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
          return true;
        }
        return null;
      });
    }
  });

  group('checklist model', () {
    test('item JSON round-trips id, title and done', () {
      final item = ChecklistItem.create('Print form');
      final copy = ChecklistItem.fromJson(
          jsonDecode(jsonEncode(item.toJson())) as Map<String, dynamic>);
      expect(copy.id, item.id);
      expect(copy.title, 'Print form');
      expect(copy.done, isFalse);
    });

    test('task row round-trip keeps the whole checklist', () {
      final original = _task('a', checklist: _items());
      final row = original.toRow();
      expect(row['checklist'], isA<String>());
      final copy = Task.fromRow(row);
      expect(copy.checklist.map((i) => i.title), ['First step', 'Second step']);
      expect(copy.checklistDone, 1);
    });

    test('legacy rows and corrupt JSON degrade to an empty checklist', () {
      expect(Task.fromRow(_taskRow()).checklist, isEmpty);
      expect(Task.fromRow(_taskRow(checklist: 'not json')).checklist, isEmpty);
      expect(
        Task.fromRow(_taskRow(checklist: '[{"title":""}]')).checklist,
        isEmpty,
      );
    });

    test('sync JSON round-trip keeps checklist state', () {
      final original = _task('a', checklist: _items());
      final decoded = Task.fromJson(
          jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>);
      expect(decoded.checklistDone, 1);
      expect(decoded.checklist.last.id, 'two');
    });

    test('a repeat occurrence keeps items but resets every box', () {
      final original = Task(
        id: 'a',
        title: 'Weekly',
        dueAt: DateTime.utc(2026, 1, 1),
        repeat: Repeat.weekly,
        checklist: _items(),
      );
      final next = original.nextOccurrence()!;
      expect(next.id, isNot(original.id));
      expect(next.checklist.map((i) => i.id), ['one', 'two']);
      expect(next.checklistDone, 0);
    });
  });

  group('checklist store', () {
    test('search matches an item title', () async {
      final db = _FakeTasksDb([
        _task('plain'),
        _task('with-list', checklist: _items()),
      ]);
      final store = TaskStore(db, startTicker: false)..onLocalChange = () {};
      await store.load();

      store.setQuery('second step');
      expect(store.visible.map((t) => t.id), ['with-list']);

      store.setQuery('first step');
      expect(store.visible.map((t) => t.id), ['with-list']);

      store.setQuery('');
      expect(store.visible.length, 2);
      store.dispose();
    });

    test('add, toggle and remove all go through the dirty save path', () async {
      final task = _task('a');
      final db = _FakeTasksDb([task]);
      final store = TaskStore(db, startTicker: false);
      await store.load();

      await store.addChecklistItem(task, '  Buy stamps  ');
      var saved = db.upserted.last;
      expect(saved.checklist.single.title, 'Buy stamps');
      expect(saved.dirty, isTrue);

      await store.addChecklistItem(saved, '');
      expect(db.upserted.length, 1, reason: 'blank items are ignored');

      final id = saved.checklist.single.id;
      await store.toggleChecklistItem(saved, id);
      saved = db.upserted.last;
      expect(saved.checklist.single.done, isTrue);

      await store.removeChecklistItem(saved, id);
      expect(db.upserted.last.checklist, isEmpty);
      store.dispose();
    });
  });

  group('checklist UI', () {
    testWidgets('task card shows checklist progress', (tester) async {
      final task = _task('a', checklist: _items());
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: Scaffold(
          body: TaskCard(
            task: task,
            onToggle: () {},
            onEdit: () {},
            onPin: () {},
          ),
        ),
      ));

      expect(find.text('1/2 steps'), findsOneWidget);
    });

    testWidgets('task form adds a checklist step and saves its done state',
        (tester) async {
      Task? saved;
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async => saved = await showTaskForm(context),
              child: const Text('Open form'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('Open form'));
      await tester.pumpAndSettle();
      expect(find.text('Checklist'), findsOneWidget);

      final addStep = find.text('Add step');
      await tester.ensureVisible(addStep);
      await tester.pumpAndSettle();
      await tester.tap(addStep);
      await tester.pumpAndSettle();
      final stepField = find.byWidgetPredicate((w) =>
          w is TextField &&
          w.decoration?.hintText == 'Step — what needs doing?');
      expect(stepField, findsOneWidget);
      final titleField = find.byWidgetPredicate((w) =>
          w is TextField &&
          w.decoration?.hintText == 'e.g. ICT3052 forensics report');
      await tester.enterText(titleField, 'Test task');
      await tester.enterText(stepField, 'Collect receipts');
      final box = find.byKey(const Key('task-checklist-box-0'));
      await tester.drag(
          find.ancestor(
            of: box,
            matching: find.byType(SingleChildScrollView),
          ),
          const Offset(0, 300));
      await tester.pumpAndSettle();
      await tester.tap(box);
      await tester.pumpAndSettle();
      expect(find.text('1/1'), findsOneWidget);

      await tester.ensureVisible(find.text('Add task'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add task'));
      await tester.pumpAndSettle();
      expect(saved, isNotNull);
      final result = saved!;
      expect(result.checklist.single.title, 'Collect receipts');
      expect(result.checklist.single.done, isTrue);
    });
  });
}
