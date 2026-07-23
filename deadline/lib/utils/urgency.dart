import 'package:flutter/material.dart';

import '../models/task.dart';

/// How much time is left, bucketed. The colour scale runs cool to hot as the
/// deadline closes in, so a glance at the list tells you where the pressure is.
enum Urgency { done, overdue, critical, today, soon, week, later }

extension UrgencyStyle on Urgency {
  Color get color {
    switch (this) {
      case Urgency.done:
        return const Color(0xFF55627A);
      case Urgency.overdue:
        return const Color(0xFFFF3355);
      case Urgency.critical:
        return const Color(0xFFFF6B2C);
      case Urgency.today:
        return const Color(0xFFFFA51F);
      case Urgency.soon:
        return const Color(0xFFE4C441);
      case Urgency.week:
        return const Color(0xFF46C08A);
      case Urgency.later:
        return const Color(0xFF5C8DEF);
    }
  }

  String get label {
    switch (this) {
      case Urgency.done:
        return 'Done';
      case Urgency.overdue:
        return 'Overdue';
      case Urgency.critical:
        return 'Due now';
      case Urgency.today:
        return 'Today';
      case Urgency.soon:
        return 'Next few days';
      case Urgency.week:
        return 'This week';
      case Urgency.later:
        return 'Later';
    }
  }
}

Urgency urgencyOf(Task t) {
  if (t.done) return Urgency.done;
  final left = t.remaining;
  if (left.isNegative) return Urgency.overdue;
  if (left < const Duration(hours: 6)) return Urgency.critical;
  if (left < const Duration(hours: 24)) return Urgency.today;
  if (left < const Duration(days: 3)) return Urgency.soon;
  if (left < const Duration(days: 7)) return Urgency.week;
  return Urgency.later;
}

/// How far along the runway a task is, measured against a one-week horizon.
/// Drives the pressure bar on each card: empty when far off, full at the line.
double pressureOf(Task t) {
  if (t.done) return 0;
  const horizon = Duration(days: 7);
  final left = t.remaining;
  if (left.isNegative) return 1;
  if (left >= horizon) return 0;
  return 1 - (left.inMinutes / horizon.inMinutes);
}

/// Compact time-left string: "3d 4h", "5h 20m", "12m", "2d late".
String countdownOf(Task t) {
  final left = t.remaining;
  final late = left.isNegative;
  final d = left.abs();

  String core;
  if (d.inDays >= 1) {
    final hours = d.inHours % 24;
    core = hours == 0 ? '${d.inDays}d' : '${d.inDays}d ${hours}h';
  } else if (d.inHours >= 1) {
    final mins = d.inMinutes % 60;
    core = mins == 0 ? '${d.inHours}h' : '${d.inHours}h ${mins}m';
  } else {
    core = '${d.inMinutes}m';
  }
  return late ? '$core late' : core;
}
