import 'package:deadline/models/note.dart';
import 'package:deadline/models/task.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final archivedAt = DateTime.utc(2026, 11, 16, 9, 30);

  group('task archive', () {
    Task archivedTask() => Task(
          id: 'a',
          title: 'Lab report',
          dueAt: DateTime.utc(2026, 11, 20),
          deleted: true,
          archivedAt: archivedAt,
          updatedAt: archivedAt,
        );

    test('row round trip keeps the archive stamp', () {
      final copy = Task.fromRow(archivedTask().toRow());
      expect(copy.archived, isTrue);
      expect(copy.archivedAt, archivedAt);
    });

    test('rows from before the archive existed read as unarchived', () {
      final row = archivedTask().toRow()..remove('archived_at');
      expect(Task.fromRow(row).archivedAt, isNull);
      expect(Task.fromRow(row).archived, isFalse);
    });

    test('a permanent delete clears the archive stamp but stays deleted', () {
      final tombstone = archivedTask().copyWith(clearArchivedAt: true);
      expect(tombstone.deleted, isTrue);
      expect(tombstone.archivedAt, isNull);
      expect(tombstone.archived, isFalse);
    });

    test('restoring makes the task live again', () {
      final back =
          archivedTask().copyWith(deleted: false, clearArchivedAt: true);
      expect(back.deleted, isFalse);
      expect(back.archivedAt, isNull);
    });

    test('the archive stamp is device-local and never synced', () {
      expect(archivedTask().toJson().containsKey('archived_at'), isFalse);
    });

    test('a delete pulled from another device lands in the archive', () {
      final copy = Task.fromJson(archivedTask().toJson());
      expect(copy.deleted, isTrue);
      expect(copy.archivedAt, archivedAt);
    });

    test('live remote tasks are not archived', () {
      final live = Task(
        id: 'b',
        title: 'Essay',
        dueAt: DateTime.utc(2026, 11, 21),
        updatedAt: archivedAt,
      );
      final copy = Task.fromJson(live.toJson());
      expect(copy.archivedAt, isNull);
    });
  });

  group('note archive', () {
    Note archivedNote() => Note(
          id: 'n',
          title: 'Reading list',
          body: 'Chapters 4 and 5',
          deleted: true,
          archivedAt: archivedAt,
          updatedAt: archivedAt,
        );

    test('row round trip keeps the archive stamp', () {
      final copy = Note.fromRow(archivedNote().toRow());
      expect(copy.archived, isTrue);
      expect(copy.archivedAt, archivedAt);
    });

    test('a permanent delete clears the archive stamp', () {
      final tombstone = archivedNote().copyWith(clearArchivedAt: true);
      expect(tombstone.deleted, isTrue);
      expect(tombstone.archivedAt, isNull);
    });

    test('the archive stamp is device-local and never synced', () {
      expect(archivedNote().toJson().containsKey('archived_at'), isFalse);
    });

    test('a delete pulled from another device lands in the archive', () {
      final copy = Note.fromJson(archivedNote().toJson());
      expect(copy.deleted, isTrue);
      expect(copy.archivedAt, archivedAt);
    });
  });
}
