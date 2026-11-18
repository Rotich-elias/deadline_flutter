import 'package:deadline/utils/schedule_suggestions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 11, 18, 9, 30); // Wednesday

  group('ScheduleSuggestions', () {
    test('returns free hourly blocks in working hours', () {
      final result = ScheduleSuggestions.suggest(
        const [],
        const [],
        now: now,
        daysAhead: 1,
      );
      expect(result, isNotEmpty);
      expect(result.first.start, DateTime(2026, 11, 18, 10));
      expect(result.first.duration, const Duration(hours: 1));
      expect(
          result.every((b) => b.start.hour >= 8 && b.start.hour < 18), isTrue);
    });

    test('skips a busy interval that overlaps the slot', () {
      final result = ScheduleSuggestions.suggest(
        [DateTime(2026, 11, 18, 10, 30)],
        [const Duration(minutes: 90)],
        now: now,
        daysAhead: 1,
      );
      expect(result.map((b) => b.start.hour), isNot(contains(10)));
      expect(result.map((b) => b.start.hour), isNot(contains(11)));
      expect(result.first.start, DateTime(2026, 11, 18, 12));
    });

    test('ignores commitments in the past', () {
      final result = ScheduleSuggestions.suggest(
        [DateTime(2026, 11, 17, 10)],
        [const Duration(hours: 2)],
        now: now,
        daysAhead: 1,
      );
      expect(result.first.start.hour, 10);
    });

    test('respects the limit and daysAhead', () {
      final result = ScheduleSuggestions.suggest(
        const [],
        const [],
        now: now,
        daysAhead: 2,
        limit: 3,
      );
      expect(result, hasLength(3));
      expect(result.map((b) => b.dayIndex).toSet(), {0});
    });

    test('ranks weekdays before weekend blocks', () {
      final result = ScheduleSuggestions.suggest(
        const [],
        const [],
        now: DateTime(2026, 11, 20, 7), // Friday
        daysAhead: 3,
        limit: 20,
      );
      final firstWeekend = result.indexWhere((b) => b.start.weekday > 5);
      final lastWeekday = result.lastIndexWhere((b) => b.start.weekday <= 5);
      expect(firstWeekend, greaterThan(lastWeekday));
    });

    test('rejects nonsensical working hours', () {
      expect(
        ScheduleSuggestions.suggest(
          const [],
          const [],
          now: now,
          workStartHour: 18,
          workEndHour: 8,
        ),
        isEmpty,
      );
    });
  });
}
