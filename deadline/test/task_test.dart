import 'package:deadline/models/task.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('monthly recurrence', () {
    test('clamps 31 January to the end of February', () {
      final next = Repeat.monthly.next(DateTime.utc(2026, 1, 31, 9, 30));
      expect(next, DateTime.utc(2026, 2, 28, 9, 30));
      expect(next.isUtc, isTrue);
    });

    test('clamps to 29 February in a leap year', () {
      final next = Repeat.monthly.next(DateTime.utc(2024, 1, 31, 9, 30));
      expect(next, DateTime.utc(2024, 2, 29, 9, 30));
    });

    test('rolls December over to January of the next year', () {
      final next = Repeat.monthly.next(DateTime.utc(2026, 12, 31, 18, 0));
      expect(next, DateTime.utc(2027, 1, 31, 18, 0));
    });

    test('keeps ordinary month lengths intact', () {
      final next = Repeat.monthly.next(DateTime.utc(2026, 3, 15, 7, 5));
      expect(next, DateTime.utc(2026, 4, 15, 7, 5));
    });
  });

  group('nextOccurrence', () {
    test('is null for a task that does not repeat', () {
      final task = Task(
        id: 'a',
        title: 'One off',
        dueAt: DateTime.utc(2026, 1, 31, 9),
      );
      expect(task.nextOccurrence(), isNull);
    });

    test('keeps the due date in UTC', () {
      final task = Task(
        id: 'a',
        title: 'Rent',
        dueAt: DateTime.utc(2026, 1, 31, 9),
        repeat: Repeat.monthly,
      );
      final next = task.nextOccurrence()!;
      expect(next.dueAt, DateTime.utc(2026, 2, 28, 9));
      expect(next.dueAt.isUtc, isTrue);
      expect(next.id, isNot(task.id));
    });
  });

  group('reminder parsing', () {
    Map<String, Object?> row({Object? reminders}) => {
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
          'reminders': reminders,
        };

    test('ignores malformed and out-of-range values', () {
      final task = Task.fromRow(row(reminders: '60,oops,-5,1440,9999999'));
      expect(task.reminderMinutes, [60, 1440]);
    });

    test('falls back to the defaults when nothing parses', () {
      final task = Task.fromRow(row(reminders: 'oops,,'));
      expect(task.reminderMinutes, defaultReminderMinutes);
    });

    test('sorts valid offsets', () {
      final task = Task.fromRow(row(reminders: '1440,10,60'));
      expect(task.reminderMinutes, [10, 60, 1440]);
    });

    test('unknown repeat values fall back to none instead of crashing', () {
      final data = row()..['repeat'] = 99;
      expect(Task.fromRow(data).repeat, Repeat.none);
    });
  });

  group('JSON round trip', () {
    test('preserves the fields that sync depends on', () {
      final original = Task(
        id: '7d2e9f13-8e0c-4b3a-9a4e-6f6f3d3f0001',
        title: 'Submit report',
        notes: 'Include the appendix',
        tag: 'Work',
        dueAt: DateTime.utc(2026, 11, 2, 17, 30),
        done: true,
        deleted: false,
        repeat: Repeat.weekly,
        updatedAt: DateTime.utc(2026, 10, 23, 12),
      );

      final copy = Task.fromJson(original.toJson());

      expect(copy.id, original.id);
      expect(copy.title, original.title);
      expect(copy.notes, original.notes);
      expect(copy.tag, original.tag);
      expect(copy.dueAt, original.dueAt);
      expect(copy.done, isTrue);
      expect(copy.deleted, isFalse);
      expect(copy.repeat, Repeat.weekly);
      expect(copy.updatedAt, original.updatedAt);
    });
  });
}
