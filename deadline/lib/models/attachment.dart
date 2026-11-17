import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// Broad category used for icons and grouping. Derived from the MIME type (or
/// the file extension when the platform cannot tell us) so it travels in sync
/// metadata without needing another table lookup.
enum AttachmentKind { image, pdf, audio, document }

AttachmentKind _kindOrDefault(Object? raw, String mime, String fileName) =>
    raw is int && raw >= 0 && raw < AttachmentKind.values.length
        ? AttachmentKind.values[raw]
        : attachmentKind(mime, fileName);

AttachmentKind attachmentKind(String mime, String fileName) {
  final type = mime.toLowerCase();
  if (type.startsWith('image/')) return AttachmentKind.image;
  if (type == 'application/pdf' || fileName.toLowerCase().endsWith('.pdf')) {
    return AttachmentKind.pdf;
  }
  if (type.startsWith('audio/')) return AttachmentKind.audio;
  return AttachmentKind.document;
}

/// One file attached to a note.
///
/// The bytes stay in this device's app storage. [toJson] deliberately omits
/// [localPath]: a synced note on another device carries the filename and size
/// so the user can see that a file exists, but it cannot open a file that was
/// never copied there. Such an attachment has a null [localPath].
class NoteAttachment {
  const NoteAttachment({
    required this.id,
    required this.noteId,
    required this.fileName,
    required this.mime,
    required this.kind,
    required this.size,
    required this.createdAt,
    this.localPath,
  });

  factory NoteAttachment.create({
    required String noteId,
    required String fileName,
    required String mime,
    required int size,
    required String localPath,
  }) {
    return NoteAttachment(
      id: _uuid.v4(),
      noteId: noteId,
      fileName: fileName,
      mime: mime,
      kind: attachmentKind(mime, fileName),
      size: size,
      createdAt: DateTime.now().toUtc(),
      localPath: localPath,
    );
  }

  final String id;
  final String noteId;
  final String fileName;
  final String mime;
  final AttachmentKind kind;
  final int size;
  final DateTime createdAt;

  /// Path inside the app's documents directory, or null on another device.
  final String? localPath;

  bool get availableLocally => localPath != null;

  NoteAttachment copyWith({String? localPath, bool clearLocalPath = false}) =>
      NoteAttachment(
        id: id,
        noteId: noteId,
        fileName: fileName,
        mime: mime,
        kind: kind,
        size: size,
        createdAt: createdAt,
        localPath: clearLocalPath ? null : (localPath ?? this.localPath),
      );

  String get sizeLabel {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).round()} KB';
    return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Map<String, Object?> toRow() => {
        'id': id,
        'note_id': noteId,
        'file_name': fileName,
        'mime': mime,
        'kind': kind.index,
        'size': size,
        'created_at': createdAt.millisecondsSinceEpoch,
        'local_path': localPath,
      };

  factory NoteAttachment.fromRow(Map<String, Object?> r) => NoteAttachment(
        id: r['id'] as String,
        noteId: r['note_id'] as String,
        fileName: r['file_name'] as String,
        mime: (r['mime'] as String?) ?? 'application/octet-stream',
        kind: _kindOrDefault(
            r['kind'], (r['mime'] as String?) ?? '', r['file_name'] as String),
        size: (r['size'] as int?) ?? 0,
        createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int,
            isUtc: true),
        localPath: r['local_path'] as String?,
      );

  /// Sync payload: metadata only. [localPath] and [noteId] are device-local —
  /// the id already belongs to the enclosing note in the sync payload.
  Map<String, dynamic> toJson() => {
        'id': id,
        'file_name': fileName,
        'mime': mime,
        'kind': kind.index,
        'size': size,
        'created_at': createdAt.toIso8601String(),
      };

  factory NoteAttachment.fromJson(Map<String, dynamic> j, String noteId) {
    final fileName = (j['file_name'] ?? j['fileName'] ?? 'file').toString();
    final mime = (j['mime'] ?? 'application/octet-stream').toString();
    return NoteAttachment(
      id: (j['id'] ?? '').toString(),
      noteId: noteId,
      fileName: fileName,
      mime: mime,
      kind: _kindOrDefault(j['kind'], mime, fileName),
      size: (j['size'] as num?)?.toInt() ?? 0,
      createdAt:
          DateTime.tryParse((j['created_at'] ?? '').toString())?.toUtc() ??
              DateTime.now().toUtc(),
      localPath: null,
    );
  }
}
