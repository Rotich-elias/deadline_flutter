import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:open_file/open_file.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../models/attachment.dart';

const _uuid = Uuid();

/// Copies picked files into the app's own documents directory so the bytes
/// survive the picker's cache being cleared. Only metadata goes into note sync;
/// a note opened on another device shows a "not downloaded" placeholder.
class AttachmentService {
  AttachmentService({Future<Directory> Function()? documentsDirectory})
      : _documentsDirectory =
            documentsDirectory ?? getApplicationDocumentsDirectory;

  final Future<Directory> Function() _documentsDirectory;

  /// Keep individual files manageable for a mobile app with no file sync yet.
  static const int maxFileBytes = 50 * 1024 * 1024;

  static const List<String> allowedExtensions = [
    'png',
    'jpg',
    'jpeg',
    'gif',
    'webp',
    'heic',
    'pdf',
    'mp3',
    'm4a',
    'aac',
    'wav',
    'ogg',
    'opus',
    'doc',
    'docx',
    'txt',
    'rtf',
    'odt',
  ];

  Future<Directory> _attachmentDirectory(String noteId) async {
    final dir = Directory(
        p.join((await _documentsDirectory()).path, 'attachments', noteId));
    await dir.create(recursive: true);
    return dir;
  }

  static String _mimeFor(String fileName) {
    final ext = p.extension(fileName).toLowerCase().replaceFirst('.', '');
    const types = <String, String>{
      'png': 'image/png',
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'gif': 'image/gif',
      'webp': 'image/webp',
      'heic': 'image/heic',
      'pdf': 'application/pdf',
      'mp3': 'audio/mpeg',
      'm4a': 'audio/mp4',
      'aac': 'audio/aac',
      'wav': 'audio/wav',
      'ogg': 'audio/ogg',
      'opus': 'audio/ogg',
      'txt': 'text/plain',
      'rtf': 'application/rtf',
      'doc': 'application/msword',
      'docx':
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'odt': 'application/vnd.oasis.opendocument.text',
    };
    return types[ext] ?? 'application/octet-stream';
  }

  static String _safeName(String name) {
    final base = p.basename(name).replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return base.isEmpty ? 'file' : base.substring(0, base.length.clamp(0, 80));
  }

  /// Opens the system file picker. Returns null when the user cancels.
  Future<List<PlatformFile>?> pickFiles() async {
    final result = await FilePicker.pickFiles(
      dialogTitle: 'Attach to note',
      type: FileType.custom,
      allowedExtensions: allowedExtensions,
      allowMultiple: true,
      withReadStream: true,
    );
    return result?.files.where((f) => f.name.trim().isNotEmpty).toList();
  }

  /// Copy one picked file into app storage and build its metadata.
  Future<NoteAttachment> importFile(
    String noteId,
    PlatformFile file, {
    int maxBytes = maxFileBytes,
  }) async {
    if (file.size > maxBytes) {
      throw const AttachmentTooLargeException();
    }

    final id = _uuid.v4();
    final dir = await _attachmentDirectory(noteId);
    final storedName = '${id}_${_safeName(file.name)}';
    final destination = p.join(dir.path, storedName);

    final stream = file.readStream;
    if (stream != null) {
      final sink = File(destination).openWrite();
      try {
        await sink.addStream(stream);
      } finally {
        await sink.close();
      }
    } else if (file.path != null) {
      await File(file.path!).copy(destination);
    } else if (file.bytes != null) {
      await File(destination).writeAsBytes(file.bytes!);
    } else {
      throw const AttachmentReadException();
    }

    final mime = _mimeFor(file.name);
    return NoteAttachment(
      id: id,
      noteId: noteId,
      fileName: p.basename(file.name),
      mime: mime,
      kind: attachmentKind(mime, file.name),
      size: file.size,
      createdAt: DateTime.now().toUtc(),
      localPath: p.join('attachments', noteId, storedName),
    );
  }

  Future<bool> exists(NoteAttachment attachment) async {
    final path = attachment.localPath;
    if (path == null) return false;
    return File(p.join((await _documentsDirectory()).path, path)).exists();
  }

  /// Returns a user-facing error, or null when the file was handed to an app.
  Future<String?> open(NoteAttachment attachment) async {
    if (!await exists(attachment)) return 'This file is not on this device.';
    final result = await OpenFile.open(
        p.join((await _documentsDirectory()).path, attachment.localPath!));
    return result.type == ResultType.done ? null : result.message;
  }

  Future<void> delete(NoteAttachment attachment) async {
    final path = attachment.localPath;
    if (path == null) return;
    final file = File(p.join((await _documentsDirectory()).path, path));
    if (await file.exists()) await file.delete();
  }

  Future<void> deleteAll(Iterable<NoteAttachment> attachments) async {
    for (final attachment in attachments) {
      await delete(attachment);
    }
  }
}

class AttachmentTooLargeException implements Exception {
  const AttachmentTooLargeException();

  @override
  String toString() => 'Files must be smaller than 50 MB.';
}

class AttachmentReadException implements Exception {
  const AttachmentReadException();

  @override
  String toString() => 'Could not read that file.';
}
