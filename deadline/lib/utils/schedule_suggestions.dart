// Suggests concrete work blocks for the My Day view. No calendar permission,
// network or dependency: it is pure arithmetic over local DateTimes.

/// A candidate block of free time.
class SuggestedBlock {
  const SuggestedBlock({
    required this.start,
    required this.duration,
    this.dayIndex = 0,
  });

  final DateTime start;
  final Duration duration;
  final int dayIndex;

  DateTime get end => start.add(duration);

  @override
  String toString() => 'SuggestedBlock($start, $duration)';
}

class ScheduleSuggestions {
  const ScheduleSuggestions._();

  /// Finds free [slot] blocks inside working hours over the next [daysAhead]
  /// days. Existing commitments are given by parallel [busyStarts] /
  /// [busyLengths] lists. Weekday slots are returned before weekend ones, then
  /// by time. At most [limit] blocks are produced.
  static List<SuggestedBlock> suggest(
    List<DateTime> busyStarts,
    List<Duration> busyLengths, {
    DateTime? now,
    int workStartHour = 8,
    int workEndHour = 18,
    int daysAhead = 3,
    int slotMinutes = 60,
    int limit = 6,
  }) {
    final at = now ?? DateTime.now();
    final slot = Duration(minutes: slotMinutes);
    if (slotMinutes <= 0 || workEndHour <= workStartHour || limit <= 0) {
      return const [];
    }

    final busy = <DateTime, DateTime>{};
    final count = busyStarts.length < busyLengths.length
        ? busyStarts.length
        : busyLengths.length;
    for (var i = 0; i < count; i++) {
      final start = busyStarts[i];
      busy[start] = start.add(busyLengths[i]);
    }

    final result = <SuggestedBlock>[];
    for (var day = 0; day < daysAhead && result.length < limit; day++) {
      final date = DateTime(at.year, at.month, at.day + day);
      for (var hour = workStartHour;
          hour + slot.inHours <= workEndHour && result.length < limit;
          hour++) {
        final start = DateTime(date.year, date.month, date.day, hour);
        if (start.isBefore(at)) continue;
        var overlaps = false;
        for (final entry in busy.entries) {
          if (start.isBefore(entry.value) &&
              start.add(slot).isAfter(entry.key)) {
            overlaps = true;
            break;
          }
        }
        if (!overlaps) {
          result.add(SuggestedBlock(
            start: start,
            duration: slot,
            dayIndex: day,
          ));
        }
      }
    }

    result.sort((a, b) {
      final aWeekend = a.start.weekday > 5;
      final bWeekend = b.start.weekday > 5;
      if (aWeekend != bWeekend) return aWeekend ? 1 : -1;
      return a.start.compareTo(b.start);
    });
    return List.unmodifiable(result.take(limit).toList());
  }
}
