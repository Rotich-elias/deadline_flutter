import 'package:deadline/data/local_db.dart';
import 'package:deadline/data/task_store.dart';
import 'package:deadline/models/task.dart';
import 'package:deadline/theme.dart';
import 'package:deadline/ui/calendar_page.dart';
import 'package:deadline/ui/task_form_sheet.dart';
import 'package:deadline/utils/calendar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

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
  group('calendar helpers', () {
    test('the grid is six Monday-first weeks around the chosen month', () {
      final days = calendarGrid(DateTime(2026, 2, 14));
      expect(days, hasLength(42));
      expect(days.first.weekday, DateTime.monday);
      expect(days.any((d) => d.year == 2026 && d.month == 2 && d.day == 14),
          isTrue);
      // February 2026 ends on a Saturday, so the last cell is in March.
      expect(days.last.month, 3);
    });

    test('sameDay ignores the time', () {
      expect(sameDay(DateTime(2026, 11, 17, 1), DateTime(2026, 11, 17, 23, 59)),
          isTrue);
      expect(sameDay(DateTime(2026, 11, 17), DateTime(2026, 11, 18)), isFalse);
    });

    test('addMonths crosses a year boundary', () {
      final next = addMonths(DateTime(2026, 12, 31), 1);
      expect(next.year, 2027);
      expect(next.month, 1);
      expect(next.day, 1);
    });

    test('tasksOn matches the local day and sorts by due time', () {
      final localMorning = DateTime(2026, 11, 17, 9);
      final localEvening = DateTime(2026, 11, 17, 18);
      final tasks = [
        Task(id: 'late', title: 'Evening', dueAt: localEvening.toUtc()),
        Task(
            id: 'other',
            title: 'Tomorrow',
            dueAt: DateTime(2026, 11, 18, 9).toUtc()),
        Task(
            id: 'early',
            title: 'Morning',
            dueAt: localMorning.toUtc(),
            done: true),
        Task(
            id: 'gone',
            title: 'Archived',
            dueAt: localMorning.toUtc(),
            deleted: true),
      ];

      final found = tasksOn(tasks, localEvening);
      expect(found.map((t) => t.title), ['Morning', 'Evening']);
      expect(openFirst(found).single.title, 'Evening');
      expect(hasOpenTasks(found), isTrue);
    });
  });

  group('calendar UI', () {
    testWidgets('today has an agenda and month navigation works',
        (tester) async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final store = TaskStore(
          _MemoryTasksDb([
            Task(
              id: 't1',
              title: 'Pay rent',
              dueAt: DateTime(today.year, today.month, today.day, 9).toUtc(),
              tag: 'money',
            ),
          ]),
          startTicker: false);
      await store.load();

      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: CalendarPage(store: store),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Pay rent'), findsOneWidget);
      expect(find.text('Calendar'), findsNothing);
      final eventDot = find.byKey(
          Key('calendar-event-dot-${today.year}-${today.month}-${today.day}'));
      expect(eventDot, findsOneWidget);
      final dotSize = tester.getSize(eventDot);
      expect(dotSize.width, greaterThanOrEqualTo(10));
      expect(dotSize.height, greaterThanOrEqualTo(10));
      final thisMonth =
          DateFormat('MMMM y').format(DateTime(now.year, now.month, 1));
      final nextMonth =
          DateFormat('MMMM y').format(DateTime(now.year, now.month + 1, 1));
      expect(find.text(thisMonth), findsOneWidget);
      await tester.tap(find.byTooltip('Next month'));
      await tester.pumpAndSettle();
      expect(find.text(nextMonth), findsOneWidget);
      await tester.tap(find.text('Today'));
      await tester.pumpAndSettle();
      expect(find.text('Pay rent'), findsOneWidget);
    });

    testWidgets('all six weeks of the month are visible in the grid',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final store = TaskStore(_MemoryTasksDb([]), startTicker: false);
      await store.load();

      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: CalendarPage(store: store),
      ));
      await tester.pumpAndSettle();

      final grid = find.byKey(const Key('calendar-grid'));
      expect(grid, findsOneWidget);
      final gridRect = tester.getRect(grid);
      for (final day in calendarGrid(startOfMonth(DateTime.now()))) {
        final label = DateFormat('y-MM-dd').format(day);
        final cell =
            find.byKey(Key('calendar-day-${day.year}-${day.month}-${day.day}'));
        expect(cell, findsOneWidget, reason: '$label has no calendar cell');
        final rect = tester.getRect(cell);
        expect(rect.top, greaterThanOrEqualTo(gridRect.top - 1),
            reason: '$label starts above the grid');
        expect(rect.bottom, lessThanOrEqualTo(gridRect.bottom + 1),
            reason: '$label is clipped by the grid');
      }
    });

    testWidgets('the selected day pre-fills a new deadline', (tester) async {
      // The task form is taller than the default test viewport.
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final now = DateTime.now();
      final chosen = DateTime(now.year, now.month, now.day, 9);
      Task? created;
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async => created = await showTaskForm(
                context,
                initialDue: chosen,
              ),
              child: const Text('Open form'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('Open form'));
      await tester.pumpAndSettle();
      expect(
          find.text(DateFormat('EEE d MMM y').format(chosen)), findsOneWidget);

      await tester.enterText(
          find.byWidgetPredicate((w) =>
              w is TextField &&
              w.decoration?.hintText == 'e.g. ICT3052 forensics report'),
          'New task');
      await tester.pumpAndSettle();
      final save = find.text('Add task');
      await tester.ensureVisible(save);
      await tester.pumpAndSettle();
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(created!.title, 'New task');
      expect(DateFormat('y-MM-dd').format(created!.dueLocal),
          DateFormat('y-MM-dd').format(chosen));
    });
  });
}
