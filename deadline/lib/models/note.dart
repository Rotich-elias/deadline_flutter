import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../utils/markup.dart';
import 'attachment.dart';

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
    this.locked = false,
    this.pinned = false,
    this.attachments = const [],
    this.labels = const [],
    this.notebook,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now().toUtc();

  factory Note.create({
    required String title,
    String? body,
    String? tag,
    bool locked = false,
    bool pinned = false,
    List<String>? labels,
    String? notebook,
  }) {
    return Note(
      id: _uuid.v4(),
      title: title,
      body: body,
      tag: tag,
      locked: locked,
      pinned: pinned,
      labels: labels ?? const [],
      notebook: notebook,
    );
  }

  final String id;
  String title;
  String? body;
  String? tag;
  DateTime updatedAt;

  /// Body with formatting tags removed, for previews, search and semantics.
  String get plainBody => stripMarkup(body);

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

  /// Device-local: the note is hidden behind the app PIN on this device.
  /// Never included in [toJson], so syncing to another device does not move
  /// the lock with the note.
  bool locked;

  /// Pinned notes sit at the top of the list. Unlike [locked] this is ordinary
  /// data, so it travels to the server along with the rest of the note.
  bool pinned;

  /// File metadata. The local path is stored in the row but left out of sync
  /// payloads, so another device sees the file but cannot open it.
  List<NoteAttachment> attachments;

  /// Multiple free-form labels in addition to the legacy single [tag].
  List<String> labels;

  /// Notebook this note belongs to, for grouping related notes together.
  String? notebook;

  bool get hasAttachments => attachments.isNotEmpty;

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
    bool? locked,
    bool? pinned,
    List<NoteAttachment>? attachments,
    List<String>? labels,
    String? notebook,
    bool clearNotebook = false,
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
      locked: locked ?? this.locked,
      pinned: pinned ?? this.pinned,
      attachments: attachments ?? this.attachments,
      labels: labels ?? this.labels,
      notebook: clearNotebook ? null : (notebook ?? this.notebook),
      updatedAt: updatedAt ?? DateTime.now().toUtc(),
    );
  }

  /// Applies a newer remote copy while keeping the lock this device set.
  /// [_reconcile] uses this so a sync pull never silently exposes a locked
  /// note; the returned copy stays non-dirty, exactly like the remote one.
  Note withLocalLockFrom(Note? local) {
    if (local == null || !local.locked) return this;
    return copyWith(locked: true, dirty: dirty, updatedAt: updatedAt);
  }

  /// A pull carries metadata but never file paths. Keep local files usable:
  /// restore the path for attachments already on this device, and never let an
  /// older payload with no attachment list drop them.
  Note withLocalAttachmentsFrom(Note? local) {
    if (local == null || local.attachments.isEmpty) return this;
    if (attachments.isEmpty) {
      return copyWith(
          attachments: local.attachments, dirty: dirty, updatedAt: updatedAt);
    }
    final byId = {
      for (final a in local.attachments)
        if (a.localPath != null) a.id: a.localPath!,
    };
    if (byId.isEmpty) return this;
    final merged = [
      for (final a in attachments) a.copyWith(localPath: byId[a.id]),
    ];
    return copyWith(attachments: merged, dirty: dirty, updatedAt: updatedAt);
  }

  static NoteAttachment _attachmentFromMap(Map value, String noteId) {
    final map = Map<String, dynamic>.from(value);
    // Rows use snake_case plus a numeric timestamp and keep the local path;
    // sync JSON has no note_id and no path at all.
    if (map.containsKey('note_id') || map.containsKey('local_path')) {
      return NoteAttachment.fromRow(map);
    }
    return NoteAttachment.fromJson(map, noteId);
  }

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

  static List<NoteAttachment> _parseAttachments(Object? raw, String noteId) {
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

    final result = <NoteAttachment>[];
    for (final value in values) {
      if (value is! Map) continue;
      result.add(_attachmentFromMap(value, noteId));
    }
    return List.unmodifiable(result);
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
        'locked': locked ? 1 : 0,
        'pinned': pinned ? 1 : 0,
        'attachments': jsonEncode(attachments.map((a) => a.toRow()).toList()),
        'labels': jsonEncode(labels),
        'notebook': notebook,
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
        locked: (r['locked'] as int?) == 1,
        pinned: (r['pinned'] as int?) == 1,
        archivedAt: r['archived_at'] is int
            ? DateTime.fromMillisecondsSinceEpoch(r['archived_at'] as int,
                isUtc: true)
            : null,
        attachments: _parseAttachments(r['attachments'], r['id'] as String),
        labels: _parseLabels(r['labels']),
        notebook: r['notebook'] as String?,
      );

  /// [archivedAt] is intentionally absent: the archive is device-local, so a
  /// remote copy can only know that this note was deleted, not when this
  /// device archived it. [fromJson] uses the delete's `updated_at` instead.
  /// [locked] is absent for the same reason: locking is per device. [pinned]
  /// is included — like a tag, it is ordinary data that should follow the note
  /// to other devices.
  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'body': body,
        'tag': tag,
        'deleted': deleted,
        'updated_at': updatedAt.toIso8601String(),
        'pinned': pinned,
        'attachments': [for (final a in attachments) a.toJson()],
        'labels': labels,
        'notebook': notebook,
      };

  factory Note.fromJson(Map<String, dynamic> j) {
    final deleted = j['deleted'] == true || j['deleted'] == 1;
    final updatedAt = DateTime.parse(j['updated_at'] as String).toUtc();
    final id = j['id'] as String;
    return Note(
      id: id,
      title: (j['title'] ?? '') as String,
      body: j['body'] as String?,
      tag: j['tag'] as String?,
      deleted: deleted,
      updatedAt: updatedAt,
      // A delete made on another device should be recoverable here too.
      archivedAt: deleted ? updatedAt : null,
      pinned: j['pinned'] == true || j['pinned'] == 1,
      attachments: _parseAttachments(j['attachments'], id),
      labels: _parseLabels(j['labels']),
      notebook: j['notebook'] as String?,
      dirty: false,
    );
  }
}
