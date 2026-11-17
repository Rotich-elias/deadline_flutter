import 'package:deadline/data/local_db.dart';
import 'package:sqflite/sqflite.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records DELETE calls so we can prove purged tombstones are never removed
/// from the local database. Every other Database member is unused here and is
/// handled by noSuchMethod forwarding.
class _RecordingDatabase implements Database {
  final List<String> deletes = [];

  @override
  Future<int> delete(String table,
      {String? where, List<Object?>? whereArgs}) async {
    deletes.add('$table: $where');
    return 0;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeDb extends LocalDb {
  _FakeDb(this.recording);

  final _RecordingDatabase recording;

  @override
  Database get db => recording;
}

void main() {
  group('purged tombstones survive sync', () {
    test('task tombstones are never hard-deleted', () async {
      final recording = _RecordingDatabase();
      final db = _FakeDb(recording);

      await db.purgeSyncedDeletes();

      expect(recording.deletes, isEmpty,
          reason: 'a hard-deleted tombstone is re-created as an ARCHIVED task '
              'by the next sync pull, because the remote payload cannot tell '
              'a permanent delete from a recoverable one');
    });

    test('note tombstones are never hard-deleted', () async {
      final recording = _RecordingDatabase();
      final db = _FakeDb(recording);

      await db.purgeSyncedNoteDeletes();

      expect(recording.deletes, isEmpty);
    });
  });
}
