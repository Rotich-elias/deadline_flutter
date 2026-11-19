import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/task.dart';
import '../models/task_comment.dart';
import '../services/activity_log.dart';
import '../services/home_widget_service.dart';
import '../services/location_alerts.dart';
import '../services/notifications.dart';
import '../utils/search.dart';
import '../utils/urgency.dart';
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

  /// All labels in use (tasks and notes), plus the active multi-label filter.
  List<String> labels = [];
  String? labelFilter;

  /// Project/category filtering.
  List<String> categories = [];
  String? categoryFilter;

  ActivityLog? _activityLog;
  Future<ActivityLog> get activityLog async =>
      _activityLog ??= await ActivityLog.instance();

  Future<void> _log(String action, {String? detail, String? entityId}) async {
    try {
      await (await activityLog)
          .record(action, detail: detail, entityId: entityId);
    } catch (_) {
      // The audit trail must never block a user action.
    }
  }

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

  void setLabelFilter(String? label) {
    labelFilter = label;
    notifyListeners();
  }

  void setCategoryFilter(String? category) {
    categoryFilter = category;
    notifyListeners();
  }

  Future<void> setLabels(Task t, List<String> next) {
    final clean = next.map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    return save(t.copyWith(labels: clean));
  }

  Future<void> setCategory(Task t, String? category) {
    final clean = category?.trim();
    if (clean == t.category || (clean?.isEmpty ?? true)) {
      return clean == null || clean.isEmpty
          ? save(t.copyWith(clearCategory: true))
          : Future.value();
    }
    return save(t.copyWith(category: clean));
  }

  Future<void> setStartAt(Task t, DateTime? start) => save(start == null
      ? t.copyWith(clearStartAt: true)
      : t.copyWith(startAt: start.toUtc()));

  Future<void> setLocationAlert(Task t, LocationAlert? alert) =>
      save(alert == null
          ? t.copyWith(clearLocationAlert: true)
          : t.copyWith(locationAlert: alert));

  void setQuery(String value) {
    final next = value.trim();
    if (next == query) return;
    query = next;
    notifyListeners();
  }

  List<Task> get visible {
    var list = (showCompleted ? _tasks : _tasks.where((t) => !t.done)).toList();
    if (tagFilter != null) {
      list = list.where((t) => t.tag == tagFilter).toList();
    }
    if (labelFilter != null) {
      list = list.where((t) => t.labels.contains(labelFilter)).toList();
    }
    if (categoryFilter != null) {
      list = list.where((t) => t.category == categoryFilter).toList();
    }
    if (query.isNotEmpty) {
      list = filterByQuery(
          list,
          query,
          (t) => [
                t.title,
                t.notes,
                t.tag,
                t.category,
                ...t.labels,
                ...t.checklist.map((item) => item.title),
              ]);
    }

    // The database already puts pinned first and soonest first. Reorder here
    // so urgency stays the primary grouping and priority is the tie-breaker
    // inside each bucket — a high-priority task due next week should not
    // jump ahead of something overdue today.
    //
    // When completed tasks are shown they lead the list, newest completion
    // first, so the last thing finished is always on top.
    list.sort((a, b) {
      if (showCompleted) {
        if (a.done != b.done) return a.done ? -1 : 1;
        if (a.done && b.done) {
          final doneA = a.completedAt ?? a.updatedAt;
          final doneB = b.completedAt ?? b.updatedAt;
          return doneB.compareTo(doneA);
        }
      }
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      if (a.done != b.done) return a.done ? 1 : -1;
      final bucketA = urgencyOf(a).index;
      final bucketB = urgencyOf(b).index;
      if (bucketA != bucketB) return bucketA.compareTo(bucketB);
      if (a.priority.index != b.priority.index) {
        return b.priority.index.compareTo(a.priority.index);
      }
      return a.dueAt.compareTo(b.dueAt);
    });
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
    labels = await _db.distinctLabels();
    categories = await _db.distinctCategories();
    if (tagFilter != null && !tags.contains(tagFilter)) tagFilter = null;
    if (labelFilter != null && !labels.contains(labelFilter)) {
      labelFilter = null;
    }
    if (categoryFilter != null && !categories.contains(categoryFilter)) {
      categoryFilter = null;
    }
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

  /// Keep the native proximity alert aligned with the saved task. Failures are
  /// swallowed by [LocationAlerts] so a lost permission never blocks a save.
  Future<void> _syncAlert(Task? previous, Task next) async {
    if (next.locationAlert != null) {
      await LocationAlerts.register(next);
    } else if (previous?.locationAlert != null) {
      await LocationAlerts.unregister(next.id);
    }
  }

  Future<void> add(Task t) async {
    await _db.upsert(t);
    await Notifications.instance.scheduleFor(t);
    await _syncAlert(null, t);
    unawaited(_log('Created deadline', detail: t.title, entityId: t.id));
    await load();
    onLocalChange?.call();
  }

  Future<void> save(Task t) async {
    Task? previous;
    for (final existing in _tasks) {
      if (existing.id == t.id) {
        previous = existing;
        break;
      }
    }
    await _db.upsert(t);
    await Notifications.instance.scheduleFor(t);
    await _syncAlert(previous, t);
    unawaited(_log('Updated deadline', detail: t.title, entityId: t.id));
    await load();
    onLocalChange?.call();
  }

  /// Pins or unpins a task. Pin is synced data, so this goes through the normal
  /// save path and marks the row dirty.
  Future<void> setPinned(Task t, bool pinned) async {
    if (t.pinned == pinned) return;
    await save(t.copyWith(pinned: pinned));
  }

  Future<void> setAssignee(Task t, String? value) {
    final trimmed = value?.trim();
    final next = trimmed == null || trimmed.isEmpty ? null : trimmed;
    if (next == t.assignedTo) return Future.value();
    return save(t.copyWith(clearAssignedTo: next == null, assignedTo: next));
  }

  Future<void> addComment(Task t, String body, {String author = 'Me'}) {
    final comment = TaskComment.create(author: author, body: body);
    if (comment.body.isEmpty) return Future.value();
    return save(t.copyWith(comments: [...t.comments, comment]));
  }

  Future<void> removeComment(Task t, String id) => save(t.copyWith(
        comments: [
          for (final comment in t.comments)
            if (comment.id != id) comment,
        ],
      ));

  /// Checklist edits reuse the normal save path so they sync like any other
  /// task change. Each mutation replaces the whole list on the copy.
  Future<void> saveChecklist(Task t, List<ChecklistItem> checklist) =>
      save(t.copyWith(checklist: checklist));

  Future<void> addChecklistItem(Task t, String title) {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return Future.value();
    return saveChecklist(t, [...t.checklist, ChecklistItem.create(trimmed)]);
  }

  Future<void> toggleChecklistItem(Task t, String itemId) => saveChecklist(
        t,
        [
          for (final item in t.checklist)
            item.id == itemId ? item.copyWith(done: !item.done) : item,
        ],
      );

  Future<void> removeChecklistItem(Task t, String itemId) => saveChecklist(
        t,
        [
          for (final item in t.checklist)
            if (item.id != itemId) item
        ],
      );

  /// Marking a repeating task done also spawns its next occurrence.
  Future<void> toggleDone(Task t) async {
    final next = t.copyWith(done: !t.done);
    await _db.upsert(next);
    await Notifications.instance.scheduleFor(next);

    unawaited(_log(next.done ? 'Completed deadline' : 'Reopened deadline',
        detail: t.title, entityId: t.id));
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
    await LocationAlerts.unregister(t.id);
    unawaited(_log('Archived deadline', detail: t.title, entityId: t.id));
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
