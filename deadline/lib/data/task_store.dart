import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/task.dart';
import '../services/home_widget_service.dart';
import '../services/notifications.dart';
import '../utils/search.dart';
import 'local_db.dart';

/// Holds the visible task list and republishes it whenever the data or the
/// clock moves. The clock matters here: a card's colour is a function of "now",
/// so the list has to redraw even when nothing was edited.
class TaskStore extends ChangeNotifier {
  TaskStore(this._db, {bool startTicker = true}) {
    if (startTicker) {
      _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
        if (_tasks.isNotEmpty) notifyListeners();
      });
    }
  }

  final LocalDb _db;
  Timer? _ticker;

  List<Task> _tasks = [];
  List<Task> get tasks => List.unmodifiable(_tasks);

  /// Deleted tasks the user can still bring back, newest deletion first.
  List<Task> _archived = [];
  List<Task> get archived => List.unmodifiable(_archived);

  List<String> tags = [];
  String? tagFilter;

  /// Free-text filter for the deadline list. Empty means "show everything".
  String query = '';

  bool showCompleted = false;

  bool digestEnabled = true;
  int digestHour = 8;
  int digestMinute = 0;

  void toggleShowCompleted() {
    showCompleted = !showCompleted;
    notifyListeners();
  }

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

  List<Task> get visible {
    var list = showCompleted ? _tasks : _tasks.where((t) => !t.done).toList();
    if (tagFilter != null) {
      list = list.where((t) => t.tag == tagFilter).toList();
    }
    if (query.isNotEmpty) {
      list = filterByQuery(list, query, (t) => [t.title, t.notes, t.tag]);
    }
    return list;
  }

  int get openCount => _tasks.where((t) => !t.done).length;
  int get overdueCount => _tasks.where((t) => t.isOverdue).length;

  /// Called after any local mutation so the sync layer can push promptly.
  VoidCallback? onLocalChange;

  Future<void> load() async {
    _tasks = await _db.all();
    _archived = await _db.archivedTasks();
    tags = await _db.distinctTags();
    if (tagFilter != null && !tags.contains(tagFilter)) tagFilter = null;
    notifyListeners();
    unawaited(_refreshDigest());
    unawaited(HomeWidgetService.update(_tasks));
  }

  Future<void> loadDigestSettings() async {
    final prefs = await SharedPreferences.getInstance();
    digestEnabled = prefs.getBool('digest.enabled') ?? true;
    digestHour = prefs.getInt('digest.hour') ?? 8;
    digestMinute = prefs.getInt('digest.minute') ?? 0;
    notifyListeners();
  }

  Future<void> saveDigestSettings({
    required bool enabled,
    required int hour,
    required int minute,
  }) async {
    digestEnabled = enabled;
    digestHour = hour;
    digestMinute = minute;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('digest.enabled', enabled);
    await prefs.setInt('digest.hour', hour);
    await prefs.setInt('digest.minute', minute);
    notifyListeners();
    await _refreshDigest();
  }

  Future<void> _refreshDigest() async {
    await Notifications.instance.scheduleDigest(
      enabled: digestEnabled,
      hour: digestHour,
      minute: digestMinute,
      openCount: openCount,
      overdueCount: overdueCount,
    );
  }

  Future<void> add(Task t) async {
    await _db.upsert(t);
    await Notifications.instance.scheduleFor(t);
    await load();
    onLocalChange?.call();
  }

  Future<void> save(Task t) async {
    await _db.upsert(t);
    await Notifications.instance.scheduleFor(t);
    await load();
    onLocalChange?.call();
  }

  /// Marking a repeating task done also spawns its next occurrence.
  Future<void> toggleDone(Task t) async {
    final next = t.copyWith(done: !t.done);
    await _db.upsert(next);
    await Notifications.instance.scheduleFor(next);

    if (next.done) {
      final following = t.nextOccurrence();
      if (following != null) {
        await _db.upsert(following);
        await Notifications.instance.scheduleFor(following);
      }
    }

    await load();
    onLocalChange?.call();
  }

  /// Archive a task. It leaves the list and its reminders stop, but the row
  /// stays recoverable until it is permanently deleted.
  Future<void> remove(Task t) async {
    await _db.upsert(t.copyWith(
      deleted: true,
      archivedAt: DateTime.now().toUtc(),
    ));
    await Notifications.instance.cancelFor(t.id);
    await load();
    onLocalChange?.call();
  }

  Future<void> restore(Task t) async {
    final back = t.copyWith(deleted: false, clearArchivedAt: true);
    await _db.upsert(back);
    await Notifications.instance.scheduleFor(back);
    await load();
    onLocalChange?.call();
  }

  /// Delete one archived task for good. Clearing [Task.archivedAt] leaves a
  /// tombstone so the delete reaches the server and other devices.
  Future<void> purge(Task t) async {
    await _db.upsert(t.copyWith(deleted: true, clearArchivedAt: true));
    await load();
    onLocalChange?.call();
  }

  Future<void> emptyArchive() async {
    if (_archived.isEmpty) return;
    await _db.emptyTaskArchive();
    await load();
    onLocalChange?.call();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}
