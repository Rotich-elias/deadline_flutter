import 'dart:io';
import 'dart:typed_data';

import 'package:deadline/data/local_db.dart';
import 'package:deadline/data/notes_store.dart';
import 'package:deadline/models/attachment.dart';
import 'package:deadline/models/note.dart';
import 'package:deadline/services/attachments.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';

/// NotesStore only needs a handful of LocalDb methods; this in-memory stand-in
/// keeps the tests free of a real database while still exercising save/load.
class _MemoryNotesDb extends LocalDb {
  final Map<String, Note> notes = {};

  @override
  Future<List<Note>> allNotes() async =>
      notes.values.where((n) => !n.deleted).toList();

  @override
  Future<List<Note>> archivedNotes() async =>
      notes.values.where((n) => n.archived).toList();

  @override
  Future<List<String>> distinctNoteTags() async => notes.values
      .where((n) => !n.deleted && n.tag != null && n.tag!.isNotEmpty)
      .map((n) => n.tag!)
      .toList();

  @override
  Future<void> upsertNote(Note n) async => notes[n.id] = n;

  @override
  Future<void> emptyNoteArchive() async {
    for (final note in notes.values.where((n) => n.archived)) {
      notes[note.id] = note.copyWith(clearArchivedAt: true);
    }
  }
}

void main() {
  Directory? tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('deadline_attach_test_');
  });

  tearDown(() async {
    if (tempDir != null && await tempDir!.exists()) {
      await tempDir!.delete(recursive: true);
    }
  });

  AttachmentService service() =>
      AttachmentService(documentsDirectory: () async => tempDir!);

  Future<NoteAttachment> importBytes(
    AttachmentService attachments,
    String noteId,
    String name,
    List<int> bytes,
  ) =>
      attachments.importFile(
        noteId,
        PlatformFile(
            name: name, size: bytes.length, bytes: Uint8List.fromList(bytes)),
      );

  NoteAttachment localAttachment({
    String id = 'att-1',
    String name = 'scan.pdf',
    String path = 'attachments/note-1/att-1_scan.pdf',
    int size = 2048,
  }) =>
      NoteAttachment(
        id: id,
        noteId: 'note-1',
        fileName: name,
        mime: 'application/pdf',
        kind: AttachmentKind.pdf,
        size: size,
        createdAt: DateTime.utc(2026, 11, 17, 12),
        localPath: path,
      );

  group('attachment metadata', () {
    test('kind comes from MIME, with an extension fallback', () {
      expect(attachmentKind('image/png', 'photo'), AttachmentKind.image);
      expect(attachmentKind('application/pdf', 'scan.pdf'), AttachmentKind.pdf);
      expect(attachmentKind('audio/mpeg', 'voice'), AttachmentKind.audio);
      expect(
          attachmentKind('text/plain', 'notes.txt'), AttachmentKind.document);
      expect(attachmentKind('application/octet-stream', 'X.PDF'),
          AttachmentKind.pdf);
    });

    test('human-readable sizes', () {
      expect(localAttachment(size: 512).sizeLabel, '512 B');
      expect(localAttachment(size: 2048).sizeLabel, '2 KB');
      expect(localAttachment(size: 2 * 1024 * 1024).sizeLabel, '2.0 MB');
    });

    test('row round trip keeps the local path and timestamp', () {
      final a = localAttachment();
      final copy = NoteAttachment.fromRow(a.toRow());
      expect(copy.localPath, a.localPath);
      expect(copy.noteId, a.noteId);
      expect(copy.kind, AttachmentKind.pdf);
      expect(copy.createdAt, a.createdAt);
    });

    test('sync JSON is metadata only — no path, no note id', () {
      final json = localAttachment().toJson();
      expect(json.containsKey('local_path'), isFalse);
      expect(json.containsKey('note_id'), isFalse);
      expect(json['file_name'], 'scan.pdf');

      final remote = NoteAttachment.fromJson(json, 'note-1');
      expect(remote.localPath, isNull);
      expect(remote.availableLocally, isFalse);
      expect(remote.kind, AttachmentKind.pdf);
    });

    test('notes survive a row round trip with their files', () {
      final note = Note(
        id: 'note-1',
        title: 'Receipts',
        attachments: [localAttachment()],
      );
      final copy = Note.fromRow(note.toRow());
      expect(copy.attachments, hasLength(1));
      expect(copy.attachments.single.localPath,
          'attachments/note-1/att-1_scan.pdf');
      expect(copy.attachments.single.createdAt, DateTime.utc(2026, 11, 17, 12));
    });

    test('legacy rows without the column have no attachments', () {
      final note = Note(id: 'note-1', title: 'Old');
      final row = note.toRow()..remove('attachments');
      expect(Note.fromRow(row).attachments, isEmpty);
    });

    test('a remote note carries metadata but no local paths', () {
      final note = Note(
          id: 'note-1', title: 'Receipts', attachments: [localAttachment()]);
      final remote = Note.fromJson(note.toJson());
      expect(remote.attachments, hasLength(1));
      expect(remote.attachments.single.availableLocally, isFalse);
    });
  });

  group('sync merge protects local files', () {
    test('an older payload with no attachments keeps the local ones', () {
      final local =
          Note(id: 'note-1', title: 'Old', attachments: [localAttachment()]);
      final remote = Note.fromJson({
        'id': 'note-1',
        'title': 'Newer title',
        'deleted': false,
        'updated_at': '2026-11-17T13:00:00.000Z',
      });
      final merged = remote.withLocalAttachmentsFrom(local);
      expect(merged.title, 'Newer title');
      expect(merged.attachments.single.localPath, isNotNull);
      expect(merged.dirty, isFalse);
      expect(merged.updatedAt, remote.updatedAt);
    });

    test('matching attachments keep their path after a pull', () {
      final local = Note(
          id: 'note-1', title: 'Receipts', attachments: [localAttachment()]);
      final remote = Note.fromJson(local.toJson());
      final merged = remote.withLocalAttachmentsFrom(local);
      expect(merged.attachments.single.localPath,
          local.attachments.single.localPath);
    });

    test('a file removed elsewhere is dropped from this device too', () {
      final local = Note(
          id: 'note-1',
          title: 'Receipts',
          attachments: [localAttachment(), localAttachment(id: 'att-2')]);
      final remote = Note.fromJson(local.copyWith(
        attachments: [local.attachments.first],
      ).toJson());
      final merged = remote.withLocalAttachmentsFrom(local);
      expect(merged.attachments.map((a) => a.id), ['att-1']);
    });
  });

  group('attachment service', () {
    test('imports bytes into app storage and can delete them', () async {
      final attachments = service();
      final a = await importBytes(
          attachments, 'note-1', 'receipt.txt', 'hello'.codeUnits);

      expect(a.fileName, 'receipt.txt');
      expect(a.mime, 'text/plain');
      expect(a.kind, AttachmentKind.document);
      expect(await attachments.exists(a), isTrue);
      expect(await File('${tempDir!.path}/${a.localPath}').readAsString(),
          'hello');

      await attachments.delete(a);
      expect(await attachments.exists(a), isFalse);
    });

    test('unsafe names are made safe', () async {
      final a =
          await importBytes(service(), 'note-1', '../evil name?.pdf', [1]);
      expect(a.fileName, 'evil name?.pdf');
      expect(a.localPath, isNot(contains('..')));
      expect(a.localPath, contains('_evil_name_.pdf'));
      expect(a.kind, AttachmentKind.pdf);
    });

    test('oversized files are rejected without being written', () async {
      await expectLater(
        service().importFile(
          'note-1',
          PlatformFile(
              name: 'big.bin', size: AttachmentService.maxFileBytes + 1),
        ),
        throwsA(isA<AttachmentTooLargeException>()),
      );
      expect(await Directory('${tempDir!.path}/attachments/note-1').exists(),
          isFalse);
    });
  });

  group('notes store', () {
    test('adding, searching and removing attachments', () async {
      final attachments = service();
      final db = _MemoryNotesDb();
      final store = NotesStore(db, attachments: attachments);
      final note = Note(id: 'note-1', title: 'Receipts', body: 'keep this');
      await store.add(note);

      final file =
          await importBytes(attachments, note.id, 'invoice.pdf', [1, 2]);
      await store.addAttachment(store.notes.single, file);
      expect(store.notes.single.attachments, hasLength(1));
      expect(store.notes.single.dirty, isTrue);

      store.setQuery('invoice');
      expect(store.visible, hasLength(1));
      store.setQuery('nothing-matches');
      expect(store.visible, isEmpty);
      store.setQuery('');

      await store.removeAttachment(store.notes.single, file.id);
      expect(store.notes.single.attachments, isEmpty);
      expect(await attachments.exists(file), isFalse);
    });

    test('purging a note deletes its local files', () async {
      final attachments = service();
      final db = _MemoryNotesDb();
      final store = NotesStore(db, attachments: attachments);
      final note = Note(id: 'note-1', title: 'To bin');
      await store.add(note);
      final file = await importBytes(attachments, note.id, 'old.txt', [7]);
      await store.addAttachment(store.notes.single, file);
      await store.remove(store.notes.single);

      await store.purge(store.archived.single);
      expect(await attachments.exists(file), isFalse);
      expect(db.notes['note-1']!.deleted, isTrue);
      expect(db.notes['note-1']!.archivedAt, isNull);
    });
  });
}
