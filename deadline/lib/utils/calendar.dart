import '../models/task.dart';

/// Date helpers for the in-app month view. Everything is local time: a task is
/// shown on the day the user saved it, not on the UTC day its timestamp uses
/// internally.

DateTime startOfDay(DateTime value) =>
    DateTime(value.year, value.month, value.day);

DateTime startOfMonth(DateTime value) => DateTime(value.year, value.month, 1);

/// Normalises to the first of the month, so adding 12 from December cannot
/// overflow into an invalid month number.
DateTime addMonths(DateTime value, int count) =>
    DateTime(value.year, value.month + count, 1);

bool sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Six weeks starting on Monday, always 42 cells so the grid never jumps when
/// a month happens to fit in four or five rows.
List<DateTime> calendarGrid(DateTime month) {
  final first = startOfMonth(month);
  final mondayBefore = first.day - (first.weekday - 1);
  final start = DateTime(first.year, first.month, mondayBefore);
  return List.generate(
      42, (i) => DateTime(start.year, start.month, start.day + i));
}

/// Tasks whose local due date is [day], regardless of time. Done tasks are
/// included so a completed day still shows what was on it.
List<Task> tasksOn(List<Task> tasks, DateTime day) =>
    tasks.where((t) => !t.deleted && sameDay(t.dueLocal, day)).toList()
      ..sort((a, b) => a.dueAt.compareTo(b.dueAt));

/// Colour cue for a day: the most urgent open task, or grey when the day only
/// has completed work.
List<Task> openFirst(List<Task> tasks) {
  final open = tasks.where((t) => !t.done).toList();
  return open.isEmpty ? tasks : open;
}

bool hasOpenTasks(List<Task> tasks) => tasks.any((t) => !t.done);
