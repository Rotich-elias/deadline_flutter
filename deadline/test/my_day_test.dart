import 'package:deadline/data/local_db.dart';
import 'package:deadline/data/task_store.dart';
import 'package:deadline/models/task.dart';
import 'package:deadline/theme.dart';
import 'package:deadline/ui/my_day_page.dart';
import 'package:deadline/utils/my_day.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Skips notification scheduling in widget tests — the plugin is not available
/// there, and My Day only needs to prove the store-driven rebuild works.
class _FocusStore extends TaskStore {
  _FocusStore(this._memory) : super(_memory, startTicker: false);

  final _MemoryTasksDb _memory;

  @override
  Future<void> toggleDone(Task t) async {
    await _memory.upsert(t.copyWith(done: !t.done));
    await load();
  }
}

class _MemoryTasksDb extends LocalDb {
  _MemoryTasksDb(this._tasks);

  final List<Task> _tasks;

  @override
  Future<List<Task>> all() async => List.unmodifiable(_tasks);

  @override
  Future<List<Task>> archivedTasks() async => const [];

  @override
  Future<List<String>> distinctTags() async =>
      _tasks.map((t) => t.tag).whereType<String>().toSet().toList();

  @override
  Future<void> upsert(Task t) async {
    final index = _tasks.indexWhere((item) => item.id == t.id);
    if (index < 0) {
      _tasks.add(t);
    } else {
      _tasks[index] = t;
    }
  }
}

void main() {
  group('My Day grouping', () {
    final now = DateTime(2026, 11, 17, 10);

    List<Task> sample() => [
          Task(
            id: 'late',
            title: 'Late report',
            dueAt: DateTime(2026, 11, 16, 18).toUtc(),
          ),
          Task(
            id: 'pinned-late',
            title: 'Pinned late',
            dueAt: DateTime(2026, 11, 16, 20).toUtc(),
            pinned: true,
          ),
          Task(
            id: 'morning',
            title: 'Morning slip',
            dueAt: DateTime(2026, 11, 17, 8).toUtc(),
          ),
          Task(
            id: 'afternoon',
            title: 'Afternoon',
            dueAt: DateTime(2026, 11, 17, 15).toUtc(),
          ),
          Task(
            id: 'pinned-today',
            title: 'Pinned today',
            dueAt: DateTime(2026, 11, 17, 16).toUtc(),
            pinned: true,
          ),
          Task(
            id: 'pinned-later',
            title: 'Pinned later',
            dueAt: DateTime(2026, 11, 20, 9).toUtc(),
            pinned: true,
          ),
          Task(
            id: 'done',
            title: 'Finished',
            dueAt: DateTime(2026, 11, 17, 11).toUtc(),
            done: true,
          ),
          Task(
            id: 'gone',
            title: 'Archived',
            dueAt: DateTime(2026, 11, 17, 12).toUtc(),
            deleted: true,
          ),
        ];

    test('overdue, today and pinned are disjoint and sorted', () {
      final groups = groupMyDay(sample(), now: now);

      expect(groups.overdue.map((t) => t.title),
          ['Late report', 'Pinned late', 'Morning slip']);
      expect(groups.today.map((t) => t.title), ['Afternoon', 'Pinned today']);
      expect(groups.pinned.map((t) => t.title), ['Pinned later']);
      expect(groups.total, 6);
      expect(groups.isEmpty, isFalse);
    });

    test('done and deleted tasks never appear as focus work', () {
      final groups = groupMyDay(sample(), now: now);
      final titles = [
        ...groups.overdue,
        ...groups.today,
        ...groups.pinned,
      ].map((t) => t.title);
      expect(titles, isNot(contains('Finished')));
      expect(titles, isNot(contains('Archived')));
    });

    test('completed work due today is counted separately', () {
      final groups = groupMyDay(sample(), now: now);
      expect(groups.completedToday, 1);
    });

    test('an empty store has no focus work', () {
      final groups = groupMyDay(const [], now: now);
      expect(groups.isEmpty, isTrue);
      expect(groups.total, 0);
      expect(groups.completedToday, 0);
    });
  });

  group('My Day UI', () {
    testWidgets('shows each group and completes a task from the row',
        (tester) async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final store = _FocusStore(_MemoryTasksDb([
        Task(
          id: 'late',
          title: 'Late rent',
          dueAt: today.subtract(const Duration(days: 1)).toUtc(),
        ),
        Task(
          id: 'today',
          title: 'Submit form',
          dueAt: DateTime(today.year, today.month, today.day, 23, 59).toUtc(),
        ),
        Task(
          id: 'later',
          title: 'Plan trip',
          dueAt: DateTime(today.year, today.month, today.day + 5, 9).toUtc(),
          pinned: true,
        ),
      ]));
      await store.load();

      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: MyDayPage(store: store),
      ));
      await tester.pumpAndSettle();

      expect(find.text('My Day'), findsOneWidget);
      expect(find.text('Overdue'), findsOneWidget);
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Pinned'), findsOneWidget);
      expect(find.text('Late rent'), findsOneWidget);
      expect(find.text('Submit form'), findsOneWidget);
      expect(find.text('Plan trip'), findsOneWidget);
      expect(find.text('3 open'), findsOneWidget);

      final row = find.ancestor(
        of: find.text('Submit form'),
        matching: find.byType(ListTile),
      );
      final checkbox =
          find.descendant(of: row, matching: find.byType(Checkbox));
      await tester.tap(checkbox);
      await tester.pumpAndSettle();

      expect(store.tasks.firstWhere((t) => t.id == 'today').done, isTrue);
      expect(find.text('Submit form'), findsNothing);
      expect(find.text('2 open'), findsOneWidget);
    });

    testWidgets('an empty focus list offers a clear message', (tester) async {
      final store = _FocusStore(_MemoryTasksDb([]));
      await store.load();

      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: MyDayPage(store: store),
      ));
      await tester.pumpAndSettle();

      expect(find.text('All clear for today'), findsOneWidget);
      expect(find.text('0 open'), findsOneWidget);
    });
  });
}
