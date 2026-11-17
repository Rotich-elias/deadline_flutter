import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/notes_store.dart';
import '../models/attachment.dart';
import '../models/note.dart';
import '../services/app_lock_service.dart';
import '../services/attachments.dart';
import '../theme.dart';
import '../utils/markup.dart';
import '../utils/rich_text.dart';
import 'app_lock_settings.dart';
import 'note_form_sheet.dart';
import 'note_lock.dart';

/// Full-page read view for a single note, opened from [NotesListPage].
/// Stays open across edits (and closes itself if the note is deleted)
/// since it looks the note up live by id rather than holding a snapshot.
class NoteViewPage extends StatelessWidget {
  const NoteViewPage({
    super.key,
    required this.store,
    required this.noteId,
    required this.appLock,
  });

  final NotesStore store;
  final String noteId;
  final AppLockService appLock;

  static final AttachmentService _attachments = AttachmentService();

  Future<void> _openFile(BuildContext context, NoteAttachment file) async {
    final error = await _attachments.open(file);
    if (!context.mounted) return;
    if (error != null) _say(context, error);
  }

  Future<void> _edit(BuildContext context, Note note) async {
    final n =
        await showNoteForm(context, existing: note, existingTags: store.tags);
    if (n != null) await store.save(n);
  }

  Future<void> _toggleLock(BuildContext context, Note note) async {
    if (!appLock.enabled) {
      final setUp = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: Ink0.surface,
          title: const Text('Set up app lock first'),
          content: const Text(
            'A note lock uses the app PIN. Turn on app lock, then lock this '
            'note from this button.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Not now'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Set up'),
            ),
          ],
        ),
      );
      if (setUp == true && context.mounted) {
        await showAppLockSettings(context, appLock, store);
      }
      return;
    }

    if (note.locked && !await confirmNoteAccess(context, appLock)) return;

    await store.setLocked(note, !note.locked);
    if (!context.mounted) return;
    _say(context, note.locked ? 'Note unlocked' : 'Note locked');
  }

  static void _say(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _toggleChecklistLine(Note note, int lineIndex) async {
    final body = note.body?.trim() ?? '';
    final updated = toggleChecklistLineAt(body, lineIndex);
    if (updated == body) return;
    await store.save(note.copyWith(body: updated));
  }

  Widget _noteBody(Note note) {
    final base = TextStyle(fontSize: 15.5, height: 1.55, color: Ink0.text);
    const highlight = Color(0xFFE4C441);
    final lines = note.body!.trim().split('\n');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < lines.length; i++) ...[
          _noteLine(note, lines[i], i, base, highlight),
        ],
      ],
    );
  }

  Widget _noteLine(
      Note note, String line, int index, TextStyle base, Color highlight) {
    final check = parseChecklistLine(line.trimLeft());
    final span = buildRichSpan(
      check?.text ?? line,
      base: base,
      highlight: highlight,
      bullet: Ink0.muted,
    );
    if (check == null) {
      if (line.trim().isEmpty) {
        return SizedBox(height: (base.fontSize ?? 15) * (base.height ?? 1.5));
      }
      return SelectableText.rich(span);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 34,
            height: 34,
            child: Checkbox(
              key: Key('note-checklist-box-$index'),
              value: check.checked,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
              activeColor: Ink0.text,
              checkColor: Ink0.surface,
              onChanged: (_) => _toggleChecklistLine(note, index),
            ),
          ),
          const SizedBox(width: 2),
          Expanded(child: SelectableText.rich(span)),
        ],
      ),
    );
  }

  Future<void> _delete(BuildContext context, Note note) async {
    await store.remove(note);
    if (!context.mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('Moved "${note.title}" to archive'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => store.restore(note),
        ),
      ));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        Note? found;
        for (final candidate in store.notes) {
          if (candidate.id == noteId) {
            found = candidate;
            break;
          }
        }
        if (found == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (Navigator.of(context).canPop()) Navigator.of(context).pop();
          });
          return const Scaffold(body: SizedBox.shrink());
        }
        final note = found;
        return Scaffold(
          appBar: AppBar(
            actions: [
              IconButton(
                tooltip: note.pinned ? 'Unpin' : 'Pin to top',
                icon: Icon(
                  note.pinned ? Icons.push_pin : Icons.push_pin_outlined,
                  color: note.pinned ? const Color(0xFFE4C441) : Ink0.muted,
                ),
                onPressed: () => store.setPinned(note, !note.pinned),
              ),
              IconButton(
                tooltip: note.locked ? 'Remove lock' : 'Lock note',
                icon: Icon(
                  note.locked ? Icons.lock : Icons.lock_open_outlined,
                  color: note.locked ? Ink0.text : Ink0.muted,
                ),
                onPressed: () => _toggleLock(context, note),
              ),
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => _edit(context, note),
              ),
              IconButton(
                tooltip: 'Move to archive',
                icon: const Icon(Icons.archive_outlined),
                onPressed: () => _delete(context, note),
              ),
              const SizedBox(width: 4),
            ],
          ),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if ((note.tag ?? '').trim().isNotEmpty) ...[
                    Text(
                      note.tag!.trim().toUpperCase(),
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                        color: Ink0.muted,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  Text(
                    note.title,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                      color: Ink0.text,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        DateFormat('d MMM yyyy, h:mm a')
                            .format(note.updatedAt.toLocal()),
                        style: TextStyle(fontSize: 12.5, color: Ink0.muted),
                      ),
                      if (note.dirty) ...[
                        const SizedBox(width: 8),
                        Icon(Icons.cloud_off, size: 13, color: Ink0.muted),
                      ],
                    ],
                  ),
                  if ((note.body ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 20),
                    _noteBody(note),
                  ],
                  if (note.hasAttachments) ...[
                    const SizedBox(height: 22),
                    Text('ATTACHMENTS',
                        style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                            color: Ink0.muted)),
                    const SizedBox(height: 4),
                    for (final file in note.attachments)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          switch (file.kind) {
                            AttachmentKind.image => Icons.image_outlined,
                            AttachmentKind.pdf => Icons.picture_as_pdf_outlined,
                            AttachmentKind.audio => Icons.audiotrack_outlined,
                            AttachmentKind.document =>
                              Icons.description_outlined,
                          },
                          size: 20,
                          color: Ink0.muted,
                        ),
                        title: Text(file.fileName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 13.5, color: Ink0.text)),
                        subtitle: Text(
                          file.availableLocally
                              ? file.sizeLabel
                              : 'Not downloaded on this device',
                          style: TextStyle(fontSize: 11.5, color: Ink0.muted),
                        ),
                        onTap: file.availableLocally
                            ? () => _openFile(context, file)
                            : null,
                      ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
