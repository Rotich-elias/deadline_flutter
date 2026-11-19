import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/attachment.dart';
import '../models/note.dart';
import '../services/activity_log.dart';
import '../services/attachments.dart';
import '../utils/linking.dart';
import '../utils/search.dart';
import 'local_db.dart';

/// Holds the visible note list. Simpler than TaskStore — nothing here is a
/// function of "now", so there's no ticker.
class NotesStore extends ChangeNotifier {
  NotesStore(this._db, {AttachmentService? attachments})
      : attachments = attachments ?? AttachmentService();

  final LocalDb _db;
  final AttachmentService attachments;

  List<Note> _notes = [];
  List<Note> get notes => List.unmodifiable(_notes);

  /// Deleted notes the user can still bring back, newest deletion first.
  List<Note> _archived = [];
  List<Note> get archived => List.unmodifiable(_archived);

  List<String> tags = [];
  String? tagFilter;

  /// Multiple labels and notebook grouping, with their active filters.
  List<String> labels = [];
  String? labelFilter;
  List<String> notebooks = [];
  String? notebookFilter;

  ActivityLog? _activityLog;
  Future<ActivityLog> get activityLog async =>
      _activityLog ??= await ActivityLog.instance();

  Future<void> _log(String action, {String? detail, String? entityId}) async {
    try {
      await (await activityLog)
          .record(action, detail: detail, entityId: entityId);
    } catch (_) {
      // Never let logging block a note edit.
    }
  }

  /// Free-text filter for the note list. Empty means "show everything".
  String query = '';

  void setTagFilter(String? tag) {
    tagFilter = tag;
    notifyListeners();
  }

  void setLabelFilter(String? label) {
    labelFilter = label;
    notifyListeners();
  }

  void setNotebookFilter(String? notebook) {
    notebookFilter = notebook;
    notifyListeners();
  }

  Future<void> setLabels(Note n, List<String> next) {
    final clean = next.map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    return save(n.copyWith(labels: clean));
  }

  Future<void> setNotebook(Note n, String? notebook) {
    final clean = notebook?.trim();
    return save(clean == null || clean.isEmpty
        ? n.copyWith(clearNotebook: true)
        : n.copyWith(notebook: clean));
  }

  void setQuery(String value) {
    final next = value.trim();
    if (next == query) return;
    query = next;
    notifyListeners();
  }

  List<Note> get visible {
    var list = _notes;
    if (tagFilter != null) {
      list = list.where((n) => n.tag == tagFilter).toList();
    }
    if (labelFilter != null) {
      list = list.where((n) => n.labels.contains(labelFilter)).toList();
    }
    if (notebookFilter != null) {
      list = list.where((n) => n.notebook == notebookFilter).toList();
    }
    if (query.isNotEmpty) {
      // A locked note's title, body and tag must not leak through a search
      // result. It reappears, still masked, once the search is cleared.
      list = list.where((n) => !n.locked).toList();
      list = filterByQuery(
          list,
          query,
          (n) => [
                n.title,
                LinkParser.strip(n.plainBody),
                n.tag,
                n.notebook,
                ...n.labels,
                ...n.attachments.map((a) => a.fileName),
              ]);
    }
    // Newest first, independent of pin state or the order the DB returned.
    final ordered = List<Note>.from(list)
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return ordered;
  }

  /// Called after any local mutation so the sync layer can push promptly.
  VoidCallback? onLocalChange;

  Future<void> load() async {
    _notes = await _db.allNotes();
    _archived = await _db.archivedNotes();
    tags = await _db.distinctNoteTags();
    labels = await _db.distinctLabels();
    notebooks = await _db.distinctNotebooks();
    if (tagFilter != null && !tags.contains(tagFilter)) tagFilter = null;
    if (labelFilter != null && !labels.contains(labelFilter)) {
      labelFilter = null;
    }
    if (notebookFilter != null && !notebooks.contains(notebookFilter)) {
      notebookFilter = null;
    }
    notifyListeners();
  }

  Future<void> add(Note n) async {
    await _db.upsertNote(n);
    unawaited(_log('Created note', detail: n.title, entityId: n.id));
    await load();
    onLocalChange?.call();
  }

  Future<void> save(Note n) async {
    await _db.upsertNote(n);
    unawaited(_log('Updated note', detail: n.title, entityId: n.id));
    await load();
    onLocalChange?.call();
  }

  /// Add a file that the UI has already copied into app storage. Attaching it
  /// marks the note dirty so its metadata travels with the next note sync.
  Future<void> addAttachment(Note n, NoteAttachment attachment) =>
      save(n.copyWith(attachments: [...n.attachments, attachment]));

  /// Remove one attachment and delete its local bytes. The note stays saved
  /// even if the file is already missing (e.g. it came from another device).
  Future<void> removeAttachment(Note n, String attachmentId) async {
    final target = n.attachments.where((a) => a.id == attachmentId).toList();
    if (target.isEmpty) return;
    await attachments.deleteAll(target);
    await save(n.copyWith(
        attachments:
            n.attachments.where((a) => a.id != attachmentId).toList()));
  }

  /// Archive a note so it leaves the list but stays recoverable.
  Future<void> remove(Note n) async {
    await _db.upsertNote(n.copyWith(
      deleted: true,
      archivedAt: DateTime.now().toUtc(),
    ));
    await load();
    onLocalChange?.call();
  }

  Future<void> restore(Note n) async {
    await _db.upsertNote(n.copyWith(deleted: false, clearArchivedAt: true));
    await load();
    onLocalChange?.call();
  }

  /// Delete one archived note for good, leaving a tombstone for sync.
  Future<void> purge(Note n) async {
    await attachments.deleteAll(n.attachments);
    await _db.upsertNote(n.copyWith(deleted: true, clearArchivedAt: true));
    await load();
    onLocalChange?.call();
  }

  Future<void> emptyArchive() async {
    if (_archived.isEmpty) return;
    for (final note in _archived) {
      await attachments.deleteAll(note.attachments);
    }
    await _db.emptyNoteArchive();
    await load();
    onLocalChange?.call();
  }

  /// Pins or unpins a note. Unlike [setLocked] this is synced data, so it goes
  /// through the normal save path and marks the row dirty.
  Future<void> setPinned(Note n, bool pinned) async {
    if (n.pinned == pinned) return;
    await save(n.copyWith(pinned: pinned));
  }

  /// Locks or unlocks a note. Device-local and sync-neutral, so this does not
  /// notify [onLocalChange].
  Future<void> setLocked(Note n, bool locked) async {
    await _db.setNoteLocked(n.id, locked);
    await load();
  }

  /// Clears every note lock, called when app lock is turned off.
  Future<void> clearAllLocks() async {
    await _db.clearNoteLocks();
    await load();
  }
}
