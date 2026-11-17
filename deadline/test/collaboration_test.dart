import 'dart:convert';

import 'package:deadline/data/local_db.dart';
import 'package:deadline/data/task_store.dart';
import 'package:deadline/models/task.dart';
import 'package:deadline/models/task_comment.dart';
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

Map<String, Object?> _taskRow({Object? assignedTo, Object? comments}) => {
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
      if (assignedTo != null) 'assigned_to': assignedTo,
      if (comments != null) 'comments': comments,
    };

Task _task(String id,
        {String? assignedTo, List<TaskComment> comments = const []}) =>
    Task(
      id: id,
      title: id,
      dueAt: DateTime.utc(2026, 1, 1),
      assignedTo: assignedTo,
      comments: comments,
    );

TextField _fieldByHint(WidgetTester tester, String hint) =>
    tester.widget<TextField>(find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText == hint));

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

  group('collaboration model', () {
    test('comment JSON round-trips author, body and timestamp', () {
      final original = TaskComment(
        id: 'c1',
        author: 'Alex',
        body: 'Please check the figures',
        createdAt: DateTime.utc(2026, 11, 17, 10),
      );
      final copy = TaskComment.fromJson(
          jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>);
      expect(copy.id, original.id);
      expect(copy.author, 'Alex');
      expect(copy.body, 'Please check the figures');
      expect(copy.createdAt, DateTime.utc(2026, 11, 17, 10));
    });

    test('task row round-trip keeps assignee and comments', () {
      final original = _task(
        'a',
        assignedTo: 'alex@example.com',
        comments: [
          TaskComment(
            id: 'c1',
            author: 'Alex',
            body: 'First',
            createdAt: DateTime.utc(2026, 11, 17, 10),
          ),
        ],
      );
      final row = original.toRow();
      expect(row['assigned_to'], 'alex@example.com');
      expect(row['comments'], isA<String>());
      final copy = Task.fromRow(row);
      expect(copy.assignedTo, 'alex@example.com');
      expect(copy.comments.single.body, 'First');
      expect(copy.hasComments, isTrue);
    });

    test('legacy and corrupt rows degrade safely', () {
      final legacy = Task.fromRow(_taskRow());
      expect(legacy.assignedTo, isNull);
      expect(legacy.comments, isEmpty);

      final corrupt = Task.fromRow(_taskRow(comments: 'not json'));
      expect(corrupt.comments, isEmpty);

      final emptyBodies = Task.fromRow(
          _taskRow(comments: '[{"id":"x","author":"A","body":""}]'));
      expect(emptyBodies.comments, isEmpty);
    });

    test('sync payload carries metadata and survives a server round trip', () {
      final original = _task(
        'a',
        assignedTo: 'sam@example.com',
        comments: [
          TaskComment(
            id: 'c1',
            author: 'Sam',
            body: 'Sent',
            createdAt: DateTime.utc(2026, 11, 17, 11),
          ),
        ],
      );
      final payload = original.toJson();
      expect(payload['assigned_to'], 'sam@example.com');
      expect(payload['comments'], isA<List>());

      final copy = Task.fromJson(
          jsonDecode(jsonEncode(payload)) as Map<String, dynamic>);
      expect(copy.assignedTo, 'sam@example.com');
      expect(copy.comments.single.author, 'Sam');
      expect(copy.comments.single.createdAt, DateTime.utc(2026, 11, 17, 11));
    });

    test('a repeat occurrence carries the assignee but clears comments', () {
      final original = Task(
        id: 'a',
        title: 'Weekly',
        dueAt: DateTime.utc(2026, 1, 1),
        repeat: Repeat.weekly,
        assignedTo: 'sam@example.com',
        comments: [
          TaskComment(
            id: 'c1',
            author: 'Sam',
            body: 'Old discussion',
            createdAt: DateTime.utc(2026, 1, 1),
          ),
        ],
      );
      final next = original.nextOccurrence()!;
      expect(next.assignedTo, 'sam@example.com');
      expect(next.comments, isEmpty);
    });
  });

  group('collaboration store', () {
    test('assignee and comment edits go through the dirty save path', () async {
      final task = _task('a');
      final db = _FakeTasksDb([task]);
      final store = TaskStore(db, startTicker: false);
      await store.load();

      await store.setAssignee(task, '  alex@example.com  ');
      var saved = db.upserted.last;
      expect(saved.assignedTo, 'alex@example.com');
      expect(saved.dirty, isTrue);

      await store.addComment(saved, '  Ready for review  ', author: 'Alex');
      saved = db.upserted.last;
      expect(saved.comments.single.author, 'Alex');
      expect(saved.comments.single.body, 'Ready for review');

      final id = saved.comments.single.id;
      await store.removeComment(saved, id);
      saved = db.upserted.last;
      expect(saved.comments, isEmpty);

      await store.setAssignee(saved, '   ');
      expect(db.upserted.last.assignedTo, isNull);
      store.dispose();
    });
  });

  group('collaboration UI', () {
    testWidgets('task card shows assignee and comment count only when enabled',
        (tester) async {
      final task = _task(
        'a',
        assignedTo: 'alex@example.com',
        comments: [
          TaskComment(
            id: 'c1',
            author: 'Alex',
            body: 'Note',
            createdAt: DateTime.utc(2026, 11, 17),
          ),
        ],
      );
      Future<void> pump(bool enabled) => tester.pumpWidget(MaterialApp(
            theme: buildTheme(Brightness.dark),
            home: Scaffold(
              body: TaskCard(
                task: task,
                onToggle: () {},
                onEdit: () {},
                onPin: () {},
                showCollaboration: enabled,
              ),
            ),
          ));

      await pump(false);
      expect(find.text('alex@example.com'), findsNothing);
      expect(find.text('1'), findsNothing);

      await pump(true);
      expect(find.text('alex@example.com'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
    });

    testWidgets('form hides collaboration controls by default', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showTaskForm(context),
              child: const Text('Open form'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('Open form'));
      await tester.pumpAndSettle();
      expect(find.text('Collaboration'), findsNothing);
      expect(find.text('Discussion'), findsNothing);
    });

    testWidgets('form adds and removes comments, then saves the assignee',
        (tester) async {
      Task? saved;
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async => saved = await showTaskForm(
                context,
                collaborationEnabled: true,
              ),
              child: const Text('Open form'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('Open form'));
      await tester.pumpAndSettle();
      expect(find.text('Collaboration'), findsOneWidget);
      expect(find.text('Discussion'), findsOneWidget);

      await tester.enterText(
          find.byWidgetPredicate((w) =>
              w is TextField &&
              w.decoration?.hintText == 'e.g. ICT3052 forensics report'),
          'Shared task');
      await tester.enterText(
          find.byWidgetPredicate((w) =>
              w is TextField &&
              w.decoration?.hintText == 'Assignee — email or name'),
          '  sam@example.com  ');
      await tester.enterText(
          find.byWidgetPredicate(
              (w) => w is TextField && w.decoration?.hintText == 'As'),
          'Sam');
      await tester.enterText(
          find.byWidgetPredicate((w) =>
              w is TextField && w.decoration?.hintText == 'Write a comment…'),
          'Will review tonight');
      await tester.ensureVisible(find.byTooltip('Add comment'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Add comment'));
      await tester.pumpAndSettle();

      expect(find.text('Will review tonight'), findsOneWidget);
      expect(
          _fieldByHint(tester, 'Write a comment…').controller?.text, isEmpty);

      await tester.ensureVisible(find.byTooltip('Remove comment'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Remove comment'));
      await tester.pumpAndSettle();
      expect(find.text('Will review tonight'), findsNothing);

      await tester.enterText(
          find.byWidgetPredicate((w) =>
              w is TextField && w.decoration?.hintText == 'Write a comment…'),
          'Final comment');
      await tester.ensureVisible(find.byTooltip('Add comment'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Add comment'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Add task'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add task'));
      await tester.pumpAndSettle();

      expect(saved, isNotNull);
      final result = saved!;
      expect(result.assignedTo, 'sam@example.com');
      expect(result.comments.single.body, 'Final comment');
      expect(result.comments.single.author, 'Sam');
    });
  });
}
