import 'package:flutter/foundation.dart';

import '../models/note.dart';
import '../utils/search.dart';
import 'local_db.dart';

/// Holds the visible note list. Simpler than TaskStore — nothing here is a
/// function of "now", so there's no ticker.
class NotesStore extends ChangeNotifier {
  NotesStore(this._db);

  final LocalDb _db;

  List<Note> _notes = [];
  List<Note> get notes => List.unmodifiable(_notes);

  /// Deleted notes the user can still bring back, newest deletion first.
  List<Note> _archived = [];
  List<Note> get archived => List.unmodifiable(_archived);

  List<String> tags = [];
  String? tagFilter;

  /// Free-text filter for the note list. Empty means "show everything".
  String query = '';

  void setTagFilter(String? tag) {
    tagFilter = tag;
    notifyListeners();
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
    if (query.isNotEmpty) {
      list = filterByQuery(list, query, (n) => [n.title, n.body, n.tag]);
    }
    return list;
  }

  /// Called after any local mutation so the sync layer can push promptly.
  VoidCallback? onLocalChange;

  Future<void> load() async {
    _notes = await _db.allNotes();
    _archived = await _db.archivedNotes();
    tags = await _db.distinctNoteTags();
    if (tagFilter != null && !tags.contains(tagFilter)) tagFilter = null;
    notifyListeners();
  }

  Future<void> add(Note n) async {
    await _db.upsertNote(n);
    await load();
    onLocalChange?.call();
  }

  Future<void> save(Note n) async {
    await _db.upsertNote(n);
    await load();
    onLocalChange?.call();
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
    await _db.upsertNote(n.copyWith(deleted: true, clearArchivedAt: true));
    await load();
    onLocalChange?.call();
  }

  Future<void> emptyArchive() async {
    if (_archived.isEmpty) return;
    await _db.emptyNoteArchive();
    await load();
    onLocalChange?.call();
  }
}
