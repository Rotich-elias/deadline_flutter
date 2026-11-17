import '../models/task.dart';
import 'calendar.dart';

/// The three buckets behind the My Day tab. The lists are disjoint: a pinned
/// task that is also late appears under Overdue, with a pin icon on its row.
class MyDayGroups {
  const MyDayGroups({
    required this.overdue,
    required this.today,
    required this.pinned,
    required this.completedToday,
  });

  /// Open work whose deadline has already passed, oldest first.
  final List<Task> overdue;

  /// Open work due on the selected day but not yet past its time.
  final List<Task> today;

  /// Open pinned work that is neither overdue nor due today, soonest first.
  final List<Task> pinned;

  /// Tasks that were due today and are already done.
  final int completedToday;

  int get total => overdue.length + today.length + pinned.length;
  bool get isEmpty => total == 0;
}

/// Pure date grouping so the focus view is easy to test and never depends on
/// the widget clock changing between builds.
MyDayGroups groupMyDay(List<Task> tasks, {DateTime? now}) {
  final at = now ?? DateTime.now();
  final instant = at.toUtc();
  final seen = <String>{};

  List<Task> take(bool Function(Task) predicate) {
    final found = tasks.where((t) {
      if (t.deleted || t.done || seen.contains(t.id)) return false;
      if (!predicate(t)) return false;
      seen.add(t.id);
      return true;
    }).toList()
      ..sort((a, b) => a.dueAt.compareTo(b.dueAt));
    return List.unmodifiable(found);
  }

  final overdue = take((t) => t.dueAt.isBefore(instant));
  final today = take((t) => sameDay(t.dueLocal, at));
  final pinned = take((t) => t.pinned);

  return MyDayGroups(
    overdue: overdue,
    today: today,
    pinned: pinned,
    completedToday: tasks
        .where((t) => !t.deleted && t.done && sameDay(t.dueLocal, at))
        .length,
  );
}
