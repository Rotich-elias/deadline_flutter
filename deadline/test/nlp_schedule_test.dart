import 'package:deadline/utils/nlp_schedule.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Wednesday 18 November 2026, 09:00 local.
  final now = DateTime(2026, 11, 18, 9);

  group('NaturalSchedule.parse', () {
    test('parses a weekday and 12-hour time and strips them from the title',
        () {
      final result =
          NaturalSchedule.parse('Finish report Friday 5pm', now: now)!;
      expect(result.title, 'Finish report');
      expect(result.dueLocal, DateTime(2026, 11, 20, 17));
    });

    test('parses tomorrow with an am time', () {
      final result = NaturalSchedule.parse('Pay rent tomorrow 9 am', now: now)!;
      expect(result.title, 'Pay rent');
      expect(result.dueLocal, DateTime(2026, 11, 19, 9));
    });

    test('parses ISO and slash dates', () {
      expect(NaturalSchedule.parse('Submit 2026-11-25', now: now)!.dueLocal,
          DateTime(2026, 11, 25, 9));
      expect(NaturalSchedule.parse('Renew 20/11', now: now)!.dueLocal,
          DateTime(2026, 11, 20, 9));
      expect(NaturalSchedule.parse('Fly 11/20/2026', now: now)!.dueLocal,
          DateTime(2026, 11, 20, 9));
    });

    test('parses a 24-hour time and named times', () {
      expect(NaturalSchedule.parse('Call at 17:30', now: now)!.dueLocal,
          DateTime(2026, 11, 18, 17, 30));
      expect(NaturalSchedule.parse('Standup noon', now: now)!.dueLocal,
          DateTime(2026, 11, 18, 12));
      expect(NaturalSchedule.parse('Beer midnight', now: now)!.dueLocal,
          DateTime(2026, 11, 19, 0));
    });

    test('parses a time-only phrase into the next occurrence', () {
      final result = NaturalSchedule.parse('Check oven 8pm',
          now: DateTime(2026, 11, 18, 21))!;
      expect(result.dueLocal, DateTime(2026, 11, 19, 20));
    });

    test('parses relative week phrases', () {
      expect(NaturalSchedule.parse('Review next week', now: now)!.dueLocal,
          DateTime(2026, 11, 25, 9));
      expect(NaturalSchedule.parse('Call in 3 days', now: now)!.dueLocal,
          DateTime(2026, 11, 21, 9));
    });

    test('extracts hashtags and Tag: lines', () {
      final result = NaturalSchedule.parse(
        'Write report tomorrow #work\nTag: study',
        now: now,
      )!;
      expect(result.tag, 'work');
      expect(result.title, 'Write report');
      expect(result.dueLocal, DateTime(2026, 11, 19, 9));
    });

    test('extracts checklist lines in several formats', () {
      final result = NaturalSchedule.parse(
        'Project due Friday 5pm\n- Draft outline\n[ ] Send email\n1. Review',
        now: now,
      )!;
      expect(result.checklist, [
        'Draft outline',
        'Send email',
        'Review',
      ]);
      expect(result.title, 'Project');
    });

    test('returns null with no date or time', () {
      expect(NaturalSchedule.parse('Just a thought', now: now), isNull);
      expect(NaturalSchedule.parse('#work without a date', now: now), isNull);
    });

    test('never mutates the input string and tidies whitespace', () {
      const input = '  Finish   report   Friday   5pm  ';
      final result = NaturalSchedule.parse(input, now: now)!;
      expect(input, '  Finish   report   Friday   5pm  ');
      expect(result.title, 'Finish report');
    });

    test('survives nonsense without throwing', () {
      for (final input in ['', '   ', '[[[]]]', '2026-99-99', '99:99 pm']) {
        expect(() => NaturalSchedule.parse(input, now: now), returnsNormally);
      }
    });

    test('handles month names', () {
      expect(NaturalSchedule.parse('Submit 20 Nov 2026', now: now)!.dueLocal,
          DateTime(2026, 11, 20, 9));
      expect(NaturalSchedule.parse('Submit Nov 20', now: now)!.dueLocal,
          DateTime(2026, 11, 20, 9));
    });
  });
}
