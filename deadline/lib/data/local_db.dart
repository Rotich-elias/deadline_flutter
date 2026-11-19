import 'dart:convert';

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
      version: 11,
      onCreate: (d, _) async {
        await d.execute('''
          CREATE TABLE tasks (
            id          TEXT PRIMARY KEY,
            title       TEXT    NOT NULL,
            notes       TEXT,
            tag         TEXT,
            due_at      INTEGER NOT NULL,
            done        INTEGER NOT NULL DEFAULT 0,
            completed_at INTEGER,
            updated_at  INTEGER NOT NULL,
            deleted     INTEGER NOT NULL DEFAULT 0,
            dirty       INTEGER NOT NULL DEFAULT 1,
            repeat      INTEGER NOT NULL DEFAULT 0,
            reminders   TEXT,
            archived_at INTEGER,
            pinned      INTEGER NOT NULL DEFAULT 0,
            priority    INTEGER NOT NULL DEFAULT 0,
            checklist   TEXT NOT NULL DEFAULT '[]',
            assigned_to TEXT,
            comments    TEXT NOT NULL DEFAULT '[]',
            start_at    INTEGER,
            labels      TEXT NOT NULL DEFAULT '[]',
            category    TEXT,
            location_alert TEXT
          )
        ''');
        await d.execute('CREATE INDEX idx_tasks_due ON tasks(due_at)');
        await d.execute('CREATE INDEX idx_tasks_dirty ON tasks(dirty)');
        await d.execute('CREATE INDEX idx_tasks_tag ON tasks(tag)');
        await d.execute(
            'CREATE INDEX idx_tasks_pinned ON tasks(pinned, done, due_at)');
        await d.execute(
            'CREATE INDEX idx_tasks_archived ON tasks(deleted, archived_at)');
        await d.execute('CREATE INDEX idx_tasks_category ON tasks(category)');
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
        if (oldVersion < 4) {
          // Deletes now stay recoverable in an archive. Existing tombstones
          // are left without an archive stamp so they purge as before.
          await d.execute('ALTER TABLE tasks ADD COLUMN archived_at INTEGER');
          await d.execute('ALTER TABLE notes ADD COLUMN archived_at INTEGER');
          await d.execute(
              'CREATE INDEX idx_tasks_archived ON tasks(deleted, archived_at)');
          await d.execute(
              'CREATE INDEX idx_notes_archived ON notes(deleted, archived_at)');
        }
        if (oldVersion < 5) {
          // Per-note lock. Device-local: never sent to the server.
          await d.execute(
              'ALTER TABLE notes ADD COLUMN locked INTEGER NOT NULL DEFAULT 0');
        }
        if (oldVersion < 6) {
          // Pinning for both kinds, plus task priority. All three are
          // ordinary synced data, so existing rows start unpinned/unprioritised.
          await d.execute(
              'ALTER TABLE tasks ADD COLUMN pinned INTEGER NOT NULL DEFAULT 0');
          await d.execute(
              'ALTER TABLE tasks ADD COLUMN priority INTEGER NOT NULL DEFAULT 0');
          await d.execute(
              'CREATE INDEX idx_tasks_pinned ON tasks(pinned, done, due_at)');
          if (oldVersion >= 3) {
            // Databases older than v3 get notes via _createNotesTable above,
            // which already includes the pinned column and its index.
            await d.execute(
                'ALTER TABLE notes ADD COLUMN pinned INTEGER NOT NULL DEFAULT 0');
            await d.execute(
                'CREATE INDEX idx_notes_pinned ON notes(pinned, updated_at)');
          }
        }
        if (oldVersion < 7) {
          // Checklist items live inside the task row as JSON. Existing tasks
          // simply start with an empty list.
          await d.execute(
              "ALTER TABLE tasks ADD COLUMN checklist TEXT NOT NULL DEFAULT '[]'");
        }
        if (oldVersion < 8) {
          // Attachment metadata lives inside the note row as JSON, same as
          // task checklists. The files themselves are in app storage.
          await d.execute(
              "ALTER TABLE notes ADD COLUMN attachments TEXT NOT NULL DEFAULT '[]'");
        }
        if (oldVersion < 9) {
          // Assignee and discussion live inside the task row as JSON/text,
          // just like checklists. Existing tasks start unassigned and silent.
          await d.execute('ALTER TABLE tasks ADD COLUMN assigned_to TEXT');
          await d.execute(
              "ALTER TABLE tasks ADD COLUMN comments TEXT NOT NULL DEFAULT '[]'");
        }
        if (oldVersion < 10) {
          // Start dates, multiple labels, categories/notebooks and place alerts
          // all default to empty so existing rows keep working unchanged.
          await d.execute('ALTER TABLE tasks ADD COLUMN start_at INTEGER');
          await d.execute(
              "ALTER TABLE tasks ADD COLUMN labels TEXT NOT NULL DEFAULT '[]'");
          await d.execute('ALTER TABLE tasks ADD COLUMN category TEXT');
          await d.execute('ALTER TABLE tasks ADD COLUMN location_alert TEXT');
          await d.execute('CREATE INDEX idx_tasks_category ON tasks(category)');
          await d.execute(
              "ALTER TABLE notes ADD COLUMN labels TEXT NOT NULL DEFAULT '[]'");
          await d.execute('ALTER TABLE notes ADD COLUMN notebook TEXT');
          await d.execute('CREATE INDEX idx_notes_notebook ON notes(notebook)');
        }
        if (oldVersion < 11) {
          // Completion time powers the "latest completed first" ordering.
          // Existing done tasks fall back to their update time.
          await d.execute('ALTER TABLE tasks ADD COLUMN completed_at INTEGER');
          await d.execute(
              'UPDATE tasks SET completed_at = updated_at WHERE done = 1');
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
        dirty       INTEGER NOT NULL DEFAULT 1,
        archived_at INTEGER,
        locked      INTEGER NOT NULL DEFAULT 0,
        pinned      INTEGER NOT NULL DEFAULT 0,
        attachments TEXT NOT NULL DEFAULT '[]',
        labels      TEXT NOT NULL DEFAULT '[]',
        notebook    TEXT
      )
    ''');
    await d.execute('CREATE INDEX idx_notes_dirty ON notes(dirty)');
    await d.execute('CREATE INDEX idx_notes_tag ON notes(tag)');
    await d.execute('CREATE INDEX idx_notes_updated ON notes(updated_at)');
    await d
        .execute('CREATE INDEX idx_notes_pinned ON notes(pinned, updated_at)');
    await d.execute(
        'CREATE INDEX idx_notes_archived ON notes(deleted, archived_at)');
    await d.execute('CREATE INDEX idx_notes_notebook ON notes(notebook)');
  }

  /// All labels in use, across both tasks and notes, alphabetical.
  Future<List<String>> distinctLabels() async {
    // Tests and early startup can use a store before the database is open.
    if (_db == null) return const [];
    final taskRows = await db.query('tasks',
        distinct: true,
        columns: ['labels'],
        where: "deleted = 0 AND labels IS NOT NULL AND labels != '[]'");
    final noteRows = await db.query('notes',
        distinct: true,
        columns: ['labels'],
        where:
            "deleted = 0 AND locked = 0 AND labels IS NOT NULL AND labels != '[]'");
    final labels = <String>{};
    for (final row in [...taskRows, ...noteRows]) {
      final raw = row['labels'];
      if (raw is! String) continue;
      try {
        for (final value in jsonDecode(raw) as Iterable) {
          final label = value.toString().trim();
          if (label.isNotEmpty) labels.add(label);
        }
      } catch (_) {
        // Ignore a corrupt row rather than losing the whole filter.
      }
    }
    final result = labels.toList()..sort();
    return result;
  }

  /// Categories used by tasks, for the project filter.
  Future<List<String>> distinctCategories() async {
    if (_db == null) return const [];
    final rows = await db.query('tasks',
        distinct: true,
        columns: ['category'],
        where: "deleted = 0 AND category IS NOT NULL AND category != ''",
        orderBy: 'category COLLATE NOCASE ASC');
    return rows.map((r) => r['category'] as String).toList();
  }

  /// Notebooks used by notes, for the notebook filter.
  Future<List<String>> distinctNotebooks() async {
    if (_db == null) return const [];
    final rows = await db.query('notes',
        distinct: true,
        columns: ['notebook'],
        where:
            "deleted = 0 AND locked = 0 AND notebook IS NOT NULL AND notebook != ''",
        orderBy: 'notebook COLLATE NOCASE ASC');
    return rows.map((r) => r['notebook'] as String).toList();
  }

  /// Live tasks, pinned first, then soonest deadline. Completed ones sink to
  /// the bottom. [TaskStore.visible] refines this further by priority.
  Future<List<Task>> all() async {
    final rows = await db.query(
      'tasks',
      where: 'deleted = 0',
      orderBy: 'pinned DESC, done ASC, due_at ASC',
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

  /// Called after every sync. Purged rows are kept locally as hidden
  /// tombstones (deleted, not archived, clean) instead of being hard-deleted.
  ///
  /// Hard-deleting them used to let the next sync pull re-create them as
  /// *archived* rows: a remote deleted row carries no "permanently deleted"
  /// marker, so [Task.fromJson] treats it as a recoverable delete and gives it
  /// an archive timestamp. Keeping the local tombstone means the pull finds a
  /// row with the same updatedAt and leaves it alone, permanently.
  ///
  /// Tombstones are invisible to both the live list (`deleted = 0`) and the
  /// archive (`archived_at IS NOT NULL`), so retaining them costs a few bytes
  /// per deleted item and nothing in the UI.
  Future<void> purgeSyncedDeletes() async {
    // Intentionally a no-op — see above.
  }

  /// Deleted tasks kept in the archive, most recently deleted first.
  Future<List<Task>> archivedTasks() async {
    final rows = await db.query(
      'tasks',
      where: 'deleted = 1 AND archived_at IS NOT NULL',
      orderBy: 'archived_at DESC',
    );
    return rows.map(Task.fromRow).toList();
  }

  /// Turns every archived task into a tombstone so the deletes travel to the
  /// server, then the normal sync purge can remove them.
  Future<void> emptyTaskArchive() async {
    await db.update(
      'tasks',
      {
        'archived_at': null,
        'dirty': 1,
        'updated_at': DateTime.now().toUtc().millisecondsSinceEpoch,
      },
      where: 'deleted = 1 AND archived_at IS NOT NULL',
    );
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

  /// Live notes, most recently updated first. Pins are still shown on each
  /// card but no longer reorder the list: "last one first" means newest first.
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

  /// Same as [purgeSyncedDeletes], for notes: a purged note stays as a hidden
  /// tombstone so a later sync cannot resurrect it into the archive.
  Future<void> purgeSyncedNoteDeletes() async {
    // Intentionally a no-op — see purgeSyncedDeletes.
  }

  /// Deleted notes kept in the archive, most recently deleted first.
  Future<List<Note>> archivedNotes() async {
    final rows = await db.query(
      'notes',
      where: 'deleted = 1 AND archived_at IS NOT NULL',
      orderBy: 'archived_at DESC',
    );
    return rows.map(Note.fromRow).toList();
  }

  /// Turns every archived note into a tombstone so the deletes travel to the
  /// server, then the normal sync purge can remove them.
  Future<void> emptyNoteArchive() async {
    await db.update(
      'notes',
      {
        'archived_at': null,
        'dirty': 1,
        'updated_at': DateTime.now().toUtc().millisecondsSinceEpoch,
      },
      where: 'deleted = 1 AND archived_at IS NOT NULL',
    );
  }

  /// Updates only the device-local lock flag, leaving the sync state and
  /// `updated_at` untouched so locking a note does not reorder or re-upload it.
  Future<void> setNoteLocked(String id, bool locked) async {
    await db.update(
      'notes',
      {'locked': locked ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Used when app lock is turned off: a note lock without the app PIN would
  /// be impossible to open.
  Future<void> clearNoteLocks() async {
    await db.update('notes', {'locked': 0}, where: 'locked = 1');
  }

  Future<List<String>> distinctNoteTags() async {
    final rows = await db.query(
      'notes',
      distinct: true,
      columns: ['tag'],
      where: "deleted = 0 AND locked = 0 AND tag IS NOT NULL AND tag != ''",
      orderBy: 'tag COLLATE NOCASE ASC',
    );
    return rows.map((r) => r['tag'] as String).toList();
  }
}
