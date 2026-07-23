import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// How a task recreates itself after it's marked done.
enum Repeat { none, daily, weekly, monthly }

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
        Repeat.monthly => DateTime(from.year, from.month + 1, from.day,
            from.hour, from.minute),
      };
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
  }) {
    return Task(
      id: _uuid.v4(),
      title: title,
      notes: notes,
      tag: tag,
      repeat: repeat,
      reminderMinutes: reminderMinutes,
      dueAt: dueAtLocal.toUtc(),
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
  bool deleted;

  /// True when this copy has local changes the server has not seen.
  bool dirty;

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
    List<int>? reminderMinutes,
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
      reminderMinutes: reminderMinutes ?? this.reminderMinutes,
      updatedAt: updatedAt ?? DateTime.now().toUtc(),
    );
  }

  static List<int> _parseReminders(Object? raw) {
    final s = (raw as String?) ?? '';
    if (s.isEmpty) return List.of(defaultReminderMinutes);
    return s.split(',').map(int.parse).toList();
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
        repeat: Repeat.values[(r['repeat'] as int?) ?? 0],
        reminderMinutes: _parseReminders(r['reminders']),
      );

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
      };

  factory Task.fromJson(Map<String, dynamic> j) => Task(
        id: j['id'] as String,
        title: (j['title'] ?? '') as String,
        notes: j['notes'] as String?,
        tag: j['tag'] as String?,
        dueAt: DateTime.parse(j['due_at'] as String).toUtc(),
        done: j['done'] == true || j['done'] == 1,
        deleted: j['deleted'] == true || j['deleted'] == 1,
        updatedAt: DateTime.parse(j['updated_at'] as String).toUtc(),
        repeat: Repeat.values[(j['repeat'] as int?) ?? 0],
        dirty: false,
      );
}
