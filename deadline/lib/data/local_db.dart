import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/note.dart';
import '../models/task.dart';

/// Single source of truth on the device. Everything the UI shows is read from
/// here; sync only ever writes into this table.
class LocalDb {
  Database? _db;
  Database get db => _db!;

  Future<void> open() async {
    final dir = await getDatabasesPath();
    _db = await openDatabase(
      p.join(dir, 'deadline.db'),
      version: 3,
      onCreate: (d, _) async {
        await d.execute('''
          CREATE TABLE tasks (
            id          TEXT PRIMARY KEY,
            title       TEXT    NOT NULL,
            notes       TEXT,
            tag         TEXT,
            due_at      INTEGER NOT NULL,
            done        INTEGER NOT NULL DEFAULT 0,
            updated_at  INTEGER NOT NULL,
            deleted     INTEGER NOT NULL DEFAULT 0,
            dirty       INTEGER NOT NULL DEFAULT 1,
            repeat      INTEGER NOT NULL DEFAULT 0,
            reminders   TEXT
          )
        ''');
        await d.execute('CREATE INDEX idx_tasks_due ON tasks(due_at)');
        await d.execute('CREATE INDEX idx_tasks_dirty ON tasks(dirty)');
        await d.execute('CREATE INDEX idx_tasks_tag ON tasks(tag)');
        await _createNotesTable(d);
      },
      onUpgrade: (d, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await d.execute('ALTER TABLE tasks ADD COLUMN tag TEXT');
          await d.execute(
              'ALTER TABLE tasks ADD COLUMN repeat INTEGER NOT NULL DEFAULT 0');
          await d.execute('ALTER TABLE tasks ADD COLUMN reminders TEXT');
          await d.execute('CREATE INDEX idx_tasks_tag ON tasks(tag)');
        }
        if (oldVersion < 3) {
          await _createNotesTable(d);
        }
      },
    );
  }

  Future<void> _createNotesTable(DatabaseExecutor d) async {
    await d.execute('''
      CREATE TABLE notes (
        id          TEXT PRIMARY KEY,
        title       TEXT    NOT NULL,
        body        TEXT,
        tag         TEXT,
        updated_at  INTEGER NOT NULL,
        deleted     INTEGER NOT NULL DEFAULT 0,
        dirty       INTEGER NOT NULL DEFAULT 1
      )
    ''');
    await d.execute('CREATE INDEX idx_notes_dirty ON notes(dirty)');
    await d.execute('CREATE INDEX idx_notes_tag ON notes(tag)');
    await d.execute('CREATE INDEX idx_notes_updated ON notes(updated_at)');
  }

  /// Live tasks, soonest deadline first. Completed ones sink to the bottom.
  Future<List<Task>> all() async {
    final rows = await db.query(
      'tasks',
      where: 'deleted = 0',
      orderBy: 'done ASC, due_at ASC',
    );
    return rows.map(Task.fromRow).toList();
  }

  Future<void> upsert(Task t) async {
    await db.insert('tasks', t.toRow(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Task?> find(String id) async {
    final rows = await db.query('tasks', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Task.fromRow(rows.first);
  }

  Future<List<Task>> dirty() async {
    final rows = await db.query('tasks', where: 'dirty = 1');
    return rows.map(Task.fromRow).toList();
  }

  Future<void> markClean(Iterable<String> ids) async {
    if (ids.isEmpty) return;
    final marks = List.filled(ids.length, '?').join(',');
    await db.rawUpdate(
      'UPDATE tasks SET dirty = 0 WHERE id IN ($marks)',
      ids.toList(),
    );
  }

  /// Tombstones the server has acknowledged no longer need to be kept.
  Future<void> purgeSyncedDeletes() async {
    await db.delete('tasks', where: 'deleted = 1 AND dirty = 0');
  }

  /// Distinct, non-empty tags in use, alphabetical — powers the filter row.
  Future<List<String>> distinctTags() async {
    final rows = await db.query(
      'tasks',
      distinct: true,
      columns: ['tag'],
      where: "deleted = 0 AND tag IS NOT NULL AND tag != ''",
      orderBy: 'tag COLLATE NOCASE ASC',
    );
    return rows.map((r) => r['tag'] as String).toList();
  }

  // --- Notes ----------------------------------------------------------

  /// Live notes, most recently updated first.
  Future<List<Note>> allNotes() async {
    final rows = await db.query(
      'notes',
      where: 'deleted = 0',
      orderBy: 'updated_at DESC',
    );
    return rows.map(Note.fromRow).toList();
  }

  Future<void> upsertNote(Note n) async {
    await db.insert('notes', n.toRow(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Note?> findNote(String id) async {
    final rows = await db.query('notes', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Note.fromRow(rows.first);
  }

  Future<List<Note>> dirtyNotes() async {
    final rows = await db.query('notes', where: 'dirty = 1');
    return rows.map(Note.fromRow).toList();
  }

  Future<void> markNotesClean(Iterable<String> ids) async {
    if (ids.isEmpty) return;
    final marks = List.filled(ids.length, '?').join(',');
    await db.rawUpdate(
      'UPDATE notes SET dirty = 0 WHERE id IN ($marks)',
      ids.toList(),
    );
  }

  Future<void> purgeSyncedNoteDeletes() async {
    await db.delete('notes', where: 'deleted = 1 AND dirty = 0');
  }

  Future<List<String>> distinctNoteTags() async {
    final rows = await db.query(
      'notes',
      distinct: true,
      columns: ['tag'],
      where: "deleted = 0 AND tag IS NOT NULL AND tag != ''",
      orderBy: 'tag COLLATE NOCASE ASC',
    );
    return rows.map((r) => r['tag'] as String).toList();
  }
}
