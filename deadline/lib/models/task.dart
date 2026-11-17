import 'dart:convert';

import 'package:uuid/uuid.dart';

import 'task_comment.dart';

const _uuid = Uuid();

/// One line of a task's checklist. Items are ordinary synced data: the id is
/// stable so a toggle on one device updates the same line on another, and the
/// done state resets when a repeating task spawns its next occurrence.
class ChecklistItem {
  const ChecklistItem({
    required this.id,
    required this.title,
    this.done = false,
  });

  factory ChecklistItem.create(String title) =>
      ChecklistItem(id: _uuid.v4(), title: title);

  final String id;
  final String title;
  final bool done;

  ChecklistItem copyWith({String? title, bool? done}) => ChecklistItem(
        id: id,
        title: title ?? this.title,
        done: done ?? this.done,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'done': done,
      };

  factory ChecklistItem.fromJson(Map<String, dynamic> j) => ChecklistItem(
        id: (j['id'] ?? '').toString(),
        title: (j['title'] ?? '').toString(),
        done: j['done'] == true || j['done'] == 1,
      );

  @override
  String toString() => '$title${done ? ' ✓' : ''}';
}

/// A place-based reminder. Stored as JSON inside the task row, so it travels
/// with the task like checklist items and comments. The native Android layer
/// turns it into a geofence when the app runs.
class LocationAlert {
  const LocationAlert({
    required this.label,
    required this.latitude,
    required this.longitude,
    this.radiusMeters = 200,
  });

  final String label;
  final double latitude;
  final double longitude;
  final double radiusMeters;

  Map<String, dynamic> toJson() => {
        'label': label,
        'latitude': latitude,
        'longitude': longitude,
        'radius_meters': radiusMeters,
      };

  factory LocationAlert.fromJson(Object? raw) {
    if (raw is! Map) return const LocationAlert(label: '', latitude: 0, longitude: 0);
    final map = Map<String, dynamic>.from(raw);
    return LocationAlert(
      label: (map['label'] ?? '').toString(),
      latitude: (map['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (map['longitude'] as num?)?.toDouble() ?? 0,
      radiusMeters: (map['radius_meters'] as num?)?.toDouble() ?? 200,
    );
  }

  @override
  String toString() => label;
}

/// How a task recreates itself after it's marked done.
enum Repeat { none, daily, weekly, monthly }

/// How important a task is, independently of how soon it is due. Urgency is
/// calculated from the deadline; priority is set by the user and is synced.
enum Priority { none, low, medium, high }

extension PriorityLabel on Priority {
  String get label => switch (this) {
        Priority.none => 'None',
        Priority.low => 'Low',
        Priority.medium => 'Medium',
        Priority.high => 'High',
      };
}

extension RepeatRule on Repeat {
  String get label => switch (this) {
        Repeat.none => 'Does not repeat',
        Repeat.daily => 'Daily',
        Repeat.weekly => 'Weekly',
        Repeat.monthly => 'Monthly',
      };

  DateTime next(DateTime from) => switch (this) {
        Repeat.none => from,
        Repeat.daily => from.add(const Duration(days: 1)),
        Repeat.weekly => from.add(const Duration(days: 7)),
        Repeat.monthly => _nextMonthly(from),
      };

  /// Adds one calendar month, clamping to the last valid day so that a task
  /// due on 31 January repeats on 28/29 February rather than rolling into
  /// March. Keeps the input's UTC/local flag.
  DateTime _nextMonthly(DateTime from) {
    final year = from.month == 12 ? from.year + 1 : from.year;
    final month = from.month == 12 ? 1 : from.month + 1;
    final lastDay = DateTime.utc(year, month + 1, 0).day;
    final day = from.day > lastDay ? lastDay : from.day;
    return from.isUtc
        ? DateTime.utc(year, month, day, from.hour, from.minute)
        : DateTime(year, month, day, from.hour, from.minute);
  }
}

/// Minutes-before-due presets offered in the reminder picker.
const reminderPresets = <int>[10, 60, 24 * 60, 3 * 24 * 60, 7 * 24 * 60];
const defaultReminderMinutes = <int>[24 * 60, 60];

/// A single deadline.
///
/// Times are held in UTC and only converted to local when shown or when a
/// reminder is scheduled. [updatedAt] is the conflict-resolution key: on sync,
/// the newer of the two copies wins. [reminderMinutes] is device-local
/// scheduling data, not synced.
class Task {
  Task({
    required this.id,
    required this.title,
    required this.dueAt,
    this.notes,
    this.tag,
    this.done = false,
    this.deleted = false,
    this.dirty = true,
    this.repeat = Repeat.none,
    this.archivedAt,
    this.pinned = false,
    this.priority = Priority.none,
    this.checklist = const [],
    this.assignedTo,
    this.comments = const [],
    this.startAt,
    this.labels = const [],
    this.category,
    this.locationAlert,
    List<int>? reminderMinutes,
    DateTime? updatedAt,
  })  : reminderMinutes = reminderMinutes ?? defaultReminderMinutes,
        updatedAt = updatedAt ?? DateTime.now().toUtc();

  factory Task.create({
    required String title,
    required DateTime dueAtLocal,
    String? notes,
    String? tag,
    Repeat repeat = Repeat.none,
    List<int>? reminderMinutes,
    bool pinned = false,
    Priority priority = Priority.none,
    List<ChecklistItem>? checklist,
    String? assignedTo,
    List<TaskComment>? comments,
    DateTime? startAt,
    List<String>? labels,
    String? category,
    LocationAlert? locationAlert,
  }) {
    return Task(
      id: _uuid.v4(),
      title: title,
      notes: notes,
      tag: tag,
      repeat: repeat,
      reminderMinutes: reminderMinutes,
      dueAt: dueAtLocal.toUtc(),
      pinned: pinned,
      priority: priority,
      checklist: checklist ?? const [],
      assignedTo: assignedTo,
      comments: comments ?? const [],
      startAt: startAt,
      labels: labels ?? const [],
      category: category,
      locationAlert: locationAlert,
    );
  }

  final String id;
  String title;
  String? notes;
  String? tag;
  DateTime dueAt;
  bool done;
  DateTime updatedAt;
  Repeat repeat;

  /// Minutes-before-due offsets for local reminders, e.g. [1440, 60].
  List<int> reminderMinutes;

  /// Tombstone. Deletes have to travel to the server, so rows are flagged
  /// rather than removed, then purged once the server confirms them.
  ///
  /// While the row is still in the user's archive this stays `true` and
  /// [archivedAt] is set. Clearing [archivedAt] turns it into a tombstone,
  /// which is what makes a permanent delete travel to other devices.
  bool deleted;

  /// When the user deleted this task, if it is being kept in the archive.
  ///
  /// Device-local like [reminderMinutes]: it is never sent to the server, so
  /// each device keeps its own archive. A remote delete lands here with the
  /// remote `updatedAt` as its archive time.
  DateTime? archivedAt;

  /// True when this task sits in the archive rather than waiting to be purged.
  bool get archived => deleted && archivedAt != null;

  /// True when this copy has local changes the server has not seen.
  bool dirty;

  /// Pinned tasks sit in their own group at the top of the list. Unlike the
  /// lock flag on notes this is ordinary data, so it travels with sync.
  bool pinned;

  /// User-set importance, separate from the time-based urgency colour.
  Priority priority;

  /// Ordered subtasks. Stored as JSON on the task row and sent as a structured
  /// list in sync payloads; it never needs its own endpoint or table.
  List<ChecklistItem> checklist;

  /// Free-text collaborator label (an email is recommended). Stored on the
  /// task and synced like other ordinary task data; no account lookup in v1.
  String? assignedTo;

  /// Discussion on this task. New occurrences start empty, like checklists.
  List<TaskComment> comments;

  /// Optional scheduled start. A task can be worked on from [startAt] but is
  /// only late after [dueAt]; null means "no scheduled window".
  DateTime? startAt;

  /// Multiple free-form labels, in addition to the single legacy [tag].
  List<String> labels;

  /// The project/category this task belongs to.
  String? category;

  /// Optional place-based reminder, mirrored into Android geofences.
  LocationAlert? locationAlert;

  DateTime get startLocal => (startAt ?? dueAt).toLocal();
  bool get hasStartWindow => startAt != null;

  int get checklistDone => checklist.where((i) => i.done).length;
  bool get hasChecklist => checklist.isNotEmpty;
  bool get hasComments => comments.isNotEmpty;

  DateTime get dueLocal => dueAt.toLocal();
  Duration get remaining => dueAt.difference(DateTime.now().toUtc());
  bool get isOverdue => !done && remaining.isNegative;

  /// The next occurrence after this one is completed, or null if it doesn't repeat.
  Task? nextOccurrence() {
    if (repeat == Repeat.none) return null;
    return Task(
      id: _uuid.v4(),
      title: title,
      notes: notes,
      tag: tag,
      dueAt: repeat.next(dueAt),
      repeat: repeat,
      reminderMinutes: reminderMinutes,
      pinned: pinned,
      priority: priority,
      assignedTo: assignedTo,
      startAt: startAt == null ? null : repeat.next(startAt!),
      labels: labels,
      category: category,
      locationAlert: locationAlert,
      // A fresh occurrence starts with every box unchecked and no discussion.
      checklist: [for (final item in checklist) item.copyWith(done: false)],
      comments: const [],
    );
  }

  Task copyWith({
    String? title,
    String? notes,
    bool clearTag = false,
    String? tag,
    DateTime? dueAtLocal,
    bool? done,
    bool? deleted,
    bool? dirty,
    Repeat? repeat,
    DateTime? archivedAt,
    bool clearArchivedAt = false,
    List<int>? reminderMinutes,
    bool? pinned,
    Priority? priority,
    List<ChecklistItem>? checklist,
    bool clearAssignedTo = false,
    String? assignedTo,
    List<TaskComment>? comments,
    DateTime? startAt,
    bool clearStartAt = false,
    List<String>? labels,
    String? category,
    bool clearCategory = false,
    LocationAlert? locationAlert,
    bool clearLocationAlert = false,
    DateTime? updatedAt,
  }) {
    return Task(
      id: id,
      title: title ?? this.title,
      notes: notes ?? this.notes,
      tag: clearTag ? null : (tag ?? this.tag),
      dueAt: dueAtLocal?.toUtc() ?? dueAt,
      done: done ?? this.done,
      deleted: deleted ?? this.deleted,
      dirty: dirty ?? true,
      repeat: repeat ?? this.repeat,
      archivedAt: clearArchivedAt ? null : (archivedAt ?? this.archivedAt),
      reminderMinutes: reminderMinutes ?? this.reminderMinutes,
      pinned: pinned ?? this.pinned,
      priority: priority ?? this.priority,
      checklist: checklist ?? this.checklist,
      assignedTo: clearAssignedTo ? null : (assignedTo ?? this.assignedTo),
      comments: comments ?? this.comments,
      startAt: clearStartAt ? null : (startAt ?? this.startAt),
      labels: labels ?? this.labels,
      category: clearCategory ? null : (category ?? this.category),
      locationAlert:
          clearLocationAlert ? null : (locationAlert ?? this.locationAlert),
      updatedAt: updatedAt ?? DateTime.now().toUtc(),
    );
  }

  static List<int> _parseReminders(Object? raw) {
    final s = raw is String ? raw : '';
    if (s.isEmpty) return List.of(defaultReminderMinutes);

    final parsed = <int>[];
    for (final part in s.split(',')) {
      final value = int.tryParse(part.trim());
      // Ignore corrupt rows instead of crashing the whole list. A year is the
      // largest offset the picker can produce.
      if (value != null && value >= 0 && value <= 525600) {
        parsed.add(value);
      }
    }
    parsed.sort();
    return parsed.isEmpty ? List.of(defaultReminderMinutes) : parsed;
  }

  static Repeat _parseRepeat(Object? raw) {
    final index = raw is int ? raw : 0;
    return index >= 0 && index < Repeat.values.length
        ? Repeat.values[index]
        : Repeat.none;
  }

  static Priority _parsePriority(Object? raw) {
    final index = raw is int ? raw : (raw is num ? raw.toInt() : 0);
    return index >= 0 && index < Priority.values.length
        ? Priority.values[index]
        : Priority.none;
  }

  static bool _asBool(Object? raw) => raw == true || raw == 1;

  /// Labels are stored as a JSON array locally and travel as a structured
  /// list in sync payloads. Legacy rows without the column simply get [].
  static List<String> _parseLabels(Object? raw) {
    Iterable<dynamic> values;
    if (raw is String && raw.isNotEmpty) {
      try {
        values = jsonDecode(raw) as Iterable<dynamic>;
      } catch (_) {
        return const [];
      }
    } else if (raw is Iterable) {
      values = raw;
    } else {
      return const [];
    }
    final result = <String>{};
    for (final value in values) {
      final label = value.toString().trim();
      if (label.isNotEmpty) result.add(label);
    }
    return List.unmodifiable(result.toList()..sort());
  }

  static DateTime? _parseDate(Object? raw) {
    if (raw is int) return DateTime.fromMillisecondsSinceEpoch(raw, isUtc: true);
    if (raw is String && raw.isNotEmpty) {
      try {
        return DateTime.parse(raw).toUtc();
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  static LocationAlert? _parseLocationAlert(Object? raw) {
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is! Map || decoded.isEmpty) return null;
        return LocationAlert.fromJson(decoded);
      } catch (_) {
        return null;
      }
    }
    if (raw is Map && raw.isNotEmpty) return LocationAlert.fromJson(raw);
    return null;
  }

  static DateTime? _parseArchivedAt(Object? raw) =>
      raw is int ? DateTime.fromMillisecondsSinceEpoch(raw, isUtc: true) : null;

  /// Accepts both the JSON text stored in the local `checklist` column and the
  /// structured list received from sync, and survives corrupt/legacy payloads.
  static List<ChecklistItem> _parseChecklist(Object? raw) {
    Iterable<dynamic> values;
    if (raw is String && raw.isNotEmpty) {
      try {
        values = jsonDecode(raw) as Iterable<dynamic>;
      } catch (_) {
        return const [];
      }
    } else if (raw is Iterable) {
      values = raw;
    } else {
      return const [];
    }

    final items = <ChecklistItem>[];
    for (final value in values) {
      final map = value is Map<String, dynamic>
          ? value
          : value is Map
              ? Map<String, dynamic>.from(value)
              : null;
      if (map == null) continue;
      final item = ChecklistItem.fromJson(map);
      if (item.title.trim().isNotEmpty) items.add(item);
    }
    return List.unmodifiable(items);
  }

  /// Similar to [_parseChecklist]: accepts both the JSON text in the local
  /// column and the structured list from sync, ignoring corrupt entries.
  static List<TaskComment> _parseComments(Object? raw) {
    Iterable<dynamic> values;
    if (raw is String && raw.isNotEmpty) {
      try {
        values = jsonDecode(raw) as Iterable<dynamic>;
      } catch (_) {
        return const [];
      }
    } else if (raw is Iterable) {
      values = raw;
    } else {
      return const [];
    }

    final result = <TaskComment>[];
    for (final value in values) {
      final map = value is Map<String, dynamic>
          ? value
          : value is Map
              ? Map<String, dynamic>.from(value)
              : null;
      if (map == null) continue;
      final comment = TaskComment.fromJson(map);
      if (comment.body.trim().isNotEmpty) result.add(comment);
    }
    return List.unmodifiable(result);
  }

  Map<String, Object?> toRow() => {
        'id': id,
        'title': title,
        'notes': notes,
        'tag': tag,
        'due_at': dueAt.millisecondsSinceEpoch,
        'done': done ? 1 : 0,
        'updated_at': updatedAt.millisecondsSinceEpoch,
        'deleted': deleted ? 1 : 0,
        'dirty': dirty ? 1 : 0,
        'repeat': repeat.index,
        'reminders': reminderMinutes.join(','),
        'archived_at': archivedAt?.millisecondsSinceEpoch,
        'pinned': pinned ? 1 : 0,
        'priority': priority.index,
        'checklist': jsonEncode(checklist.map((i) => i.toJson()).toList()),
        'assigned_to': assignedTo,
        'comments': jsonEncode(comments.map((c) => c.toJson()).toList()),
        'start_at': startAt?.millisecondsSinceEpoch,
        'labels': jsonEncode(labels),
        'category': category,
        'location_alert':
            locationAlert == null ? null : jsonEncode(locationAlert.toJson()),
      };

  factory Task.fromRow(Map<String, Object?> r) => Task(
        id: r['id'] as String,
        title: r['title'] as String,
        notes: r['notes'] as String?,
        tag: r['tag'] as String?,
        dueAt: DateTime.fromMillisecondsSinceEpoch(r['due_at'] as int,
            isUtc: true),
        done: (r['done'] as int) == 1,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(r['updated_at'] as int,
            isUtc: true),
        deleted: (r['deleted'] as int) == 1,
        dirty: (r['dirty'] as int) == 1,
        repeat: _parseRepeat(r['repeat']),
        archivedAt: _parseArchivedAt(r['archived_at']),
        reminderMinutes: _parseReminders(r['reminders']),
        pinned: _asBool(r['pinned']),
        priority: _parsePriority(r['priority']),
        checklist: _parseChecklist(r['checklist']),
        assignedTo: r['assigned_to'] as String?,
        comments: _parseComments(r['comments']),
        startAt: _parseDate(r['start_at']),
        labels: _parseLabels(r['labels']),
        category: r['category'] as String?,
        locationAlert: _parseLocationAlert(r['location_alert']),
      );

  /// [archivedAt] is intentionally absent: the archive is device-local, so a
  /// remote copy can only know that this task was deleted, not when this
  /// device archived it. [fromJson] uses the delete's `updated_at` instead.
  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'notes': notes,
        'tag': tag,
        'due_at': dueAt.toIso8601String(),
        'done': done,
        'deleted': deleted,
        'updated_at': updatedAt.toIso8601String(),
        'repeat': repeat.index,
        'pinned': pinned,
        'priority': priority.index,
        'checklist': [for (final item in checklist) item.toJson()],
        'assigned_to': assignedTo,
        'comments': [for (final c in comments) c.toJson()],
        'start_at': startAt?.toIso8601String(),
        'labels': labels,
        'category': category,
        'location_alert': locationAlert?.toJson(),
      };

  factory Task.fromJson(Map<String, dynamic> j) {
    final deleted = j['deleted'] == true || j['deleted'] == 1;
    final updatedAt = DateTime.parse(j['updated_at'] as String).toUtc();
    return Task(
      id: j['id'] as String,
      title: (j['title'] ?? '') as String,
      notes: j['notes'] as String?,
      tag: j['tag'] as String?,
      dueAt: DateTime.parse(j['due_at'] as String).toUtc(),
      done: j['done'] == true || j['done'] == 1,
      deleted: deleted,
      updatedAt: updatedAt,
      // A delete made on another device should be recoverable here too.
      archivedAt: deleted ? updatedAt : null,
      repeat: _parseRepeat(j['repeat']),
      pinned: _asBool(j['pinned']),
      priority: _parsePriority(j['priority']),
      checklist: _parseChecklist(j['checklist']),
      assignedTo: j['assigned_to'] as String?,
      comments: _parseComments(j['comments']),
      startAt: _parseDate(j['start_at']),
      labels: _parseLabels(j['labels']),
      category: j['category'] as String?,
      locationAlert: _parseLocationAlert(j['location_alert']),
      dirty: false,
    );
  }
}
