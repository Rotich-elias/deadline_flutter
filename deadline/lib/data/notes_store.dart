import 'package:flutter/foundation.dart';

import '../models/note.dart';
import 'local_db.dart';

/// Holds the visible note list. Simpler than TaskStore — nothing here is a
/// function of "now", so there's no ticker.
class NotesStore extends ChangeNotifier {
  NotesStore(this._db);

  final LocalDb _db;

  List<Note> _notes = [];
  List<Note> get notes => List.unmodifiable(_notes);

  List<String> tags = [];
  String? tagFilter;

  void setTagFilter(String? tag) {
    tagFilter = tag;
    notifyListeners();
  }

  List<Note> get visible => tagFilter == null
      ? _notes
      : _notes.where((n) => n.tag == tagFilter).toList();

  /// Called after any local mutation so the sync layer can push promptly.
  VoidCallback? onLocalChange;

  Future<void> load() async {
    _notes = await _db.allNotes();
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

  Future<void> remove(Note n) async {
    await _db.upsertNote(n.copyWith(deleted: true));
    await load();
    onLocalChange?.call();
  }

  Future<void> restore(Note n) async {
    await _db.upsertNote(n.copyWith(deleted: false));
    await load();
    onLocalChange?.call();
  }
}
