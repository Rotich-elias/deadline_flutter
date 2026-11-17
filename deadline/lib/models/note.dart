import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// A freeform note — no due date, no urgency, nothing to schedule. Just
/// something to remember, sitting next to the deadlines.
class Note {
  Note({
    required this.id,
    required this.title,
    this.body,
    this.tag,
    this.deleted = false,
    this.dirty = true,
    this.archivedAt,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now().toUtc();

  factory Note.create({required String title, String? body, String? tag}) {
    return Note(id: _uuid.v4(), title: title, body: body, tag: tag);
  }

  final String id;
  String title;
  String? body;
  String? tag;
  DateTime updatedAt;

  /// Tombstone, same purpose as on [Task]: travels to the server as a
  /// flagged row rather than a deletion, then purges locally once
  /// acknowledged. While the note is still in the archive [archivedAt] is set;
  /// clearing it turns the row into a purgable tombstone.
  bool deleted;

  /// When the user deleted this note, if it is being kept in the archive.
  /// Device-local: never synced, so every device keeps its own archive.
  DateTime? archivedAt;

  /// True when this note sits in the archive rather than waiting to be purged.
  bool get archived => deleted && archivedAt != null;

  /// True when this copy has local changes the server has not seen.
  bool dirty;

  Note copyWith({
    String? title,
    String? body,
    bool clearTag = false,
    String? tag,
    bool? deleted,
    bool? dirty,
    DateTime? archivedAt,
    bool clearArchivedAt = false,
    DateTime? updatedAt,
  }) {
    return Note(
      id: id,
      title: title ?? this.title,
      body: body ?? this.body,
      tag: clearTag ? null : (tag ?? this.tag),
      deleted: deleted ?? this.deleted,
      dirty: dirty ?? true,
      archivedAt: clearArchivedAt ? null : (archivedAt ?? this.archivedAt),
      updatedAt: updatedAt ?? DateTime.now().toUtc(),
    );
  }

  Map<String, Object?> toRow() => {
        'id': id,
        'title': title,
        'body': body,
        'tag': tag,
        'updated_at': updatedAt.millisecondsSinceEpoch,
        'deleted': deleted ? 1 : 0,
        'dirty': dirty ? 1 : 0,
        'archived_at': archivedAt?.millisecondsSinceEpoch,
      };

  factory Note.fromRow(Map<String, Object?> r) => Note(
        id: r['id'] as String,
        title: r['title'] as String,
        body: r['body'] as String?,
        tag: r['tag'] as String?,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(r['updated_at'] as int,
            isUtc: true),
        deleted: (r['deleted'] as int) == 1,
        dirty: (r['dirty'] as int) == 1,
        archivedAt: r['archived_at'] is int
            ? DateTime.fromMillisecondsSinceEpoch(r['archived_at'] as int,
                isUtc: true)
            : null,
      );

  /// [archivedAt] is intentionally absent: the archive is device-local, so a
  /// remote copy can only know that this note was deleted, not when this
  /// device archived it. [fromJson] uses the delete's `updated_at` instead.
  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'body': body,
        'tag': tag,
        'deleted': deleted,
        'updated_at': updatedAt.toIso8601String(),
      };

  factory Note.fromJson(Map<String, dynamic> j) {
    final deleted = j['deleted'] == true || j['deleted'] == 1;
    final updatedAt = DateTime.parse(j['updated_at'] as String).toUtc();
    return Note(
      id: j['id'] as String,
      title: (j['title'] ?? '') as String,
      body: j['body'] as String?,
      tag: j['tag'] as String?,
      deleted: deleted,
      updatedAt: updatedAt,
      // A delete made on another device should be recoverable here too.
      archivedAt: deleted ? updatedAt : null,
      dirty: false,
    );
  }
}
