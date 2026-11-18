import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/notes_store.dart';
import '../data/task_store.dart';
import '../models/attachment.dart';
import '../models/note.dart';
import '../models/task.dart';
import '../services/app_lock_service.dart';
import '../services/attachments.dart';
import '../services/platform_bridge.dart';
import '../theme.dart';
import '../utils/linking.dart';
import '../utils/markup.dart';
import '../utils/rich_text.dart';
import 'note_form_sheet.dart';
import 'note_lock.dart';
import 'paper_page.dart';
import 'task_form_sheet.dart';

/// Full-page read view for a single note, opened from [NotesListPage].
/// Stays open across edits (and closes itself if the note is deleted)
/// since it looks the note up live by id rather than holding a snapshot.
class NoteViewPage extends StatelessWidget {
  const NoteViewPage({
    super.key,
    required this.store,
    required this.noteId,
    required this.appLock,
    this.taskStore,
  });

  final NotesStore store;
  final String noteId;
  final AppLockService appLock;

  /// Supplied by the Notes tab so `[[tasks:...]]` links can open a deadline.
  final TaskStore? taskStore;

  static final AttachmentService _attachments = AttachmentService();

  Future<void> _openFile(BuildContext context, NoteAttachment file) async {
    final error = await _attachments.open(file);
    if (!context.mounted) return;
    if (error != null) _say(context, error);
  }

  Future<void> _edit(BuildContext context, Note note) async {
    final n = await showNoteForm(
      context,
      existing: note,
      existingTags: store.tags,
      existingLabels: store.labels,
      appLock: appLock,
    );
    if (n != null) await store.save(n);
  }

  Future<void> _toggleLock(BuildContext context, Note note) async {
    // A note lock only needs a PIN, not the app-wide lock. If no PIN exists
    // yet, create one here without turning app lock on.
    if (!await ensureNotePin(context, appLock)) return;
    if (!context.mounted) return;

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

  void _toast(BuildContext context, String message) {
    if (context.mounted) _say(context, message);
  }

  Future<void> _toggleChecklistLine(Note note, int lineIndex) async {
    final body = note.body?.trim() ?? '';
    final updated = toggleChecklistLineAt(body, lineIndex);
    if (updated == body) return;
    await store.save(note.copyWith(body: updated));
  }

  Future<void> _openNote(BuildContext context, String id) async {
    final target = store.notes.where((n) => n.id == id).firstOrNull;
    if (target == null) {
      _toast(context, 'That note is no longer available.');
      return;
    }
    if (target.locked && !await confirmNoteAccess(context, appLock)) return;
    if (!context.mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => NoteViewPage(
        store: store,
        noteId: target.id,
        appLock: appLock,
        taskStore: taskStore,
      ),
    ));
  }

  Future<void> _openTask(
    BuildContext context,
    String? id,
    String? title,
  ) async {
    final tasks = taskStore?.tasks ?? const <Task>[];
    Task? target;
    if (id != null) {
      for (final task in tasks) {
        if (task.id == id) {
          target = task;
          break;
        }
      }
    }
    target ??= tasks
        .where(
            (t) => t.title.toLowerCase() == (title ?? '').toLowerCase().trim())
        .firstOrNull;
    if (target == null) {
      _toast(context, 'That deadline is no longer available.');
      return;
    }
    final edited = await showTaskForm(
      context,
      existing: target,
      existingTags: taskStore?.tags ?? const [],
      existingLabels: taskStore?.labels ?? const [],
      collaborationEnabled: false,
    );
    if (edited != null) await taskStore?.save(edited);
  }

  /// Web addresses written in a note (including URLs imported from Samsung
  /// Notes) open in the browser through the same bridge as the About link.
  Future<void> _openLink(BuildContext context, String url) async {
    final opened = await PlatformBridge.openUrl(url);
    if (!opened && context.mounted) {
      _say(context, 'Could not open $url');
    }
  }

  Future<void> _followTarget(BuildContext context, String target) async {
    final link = LinkParser.parse('[[$target]]').firstOrNull;
    if (link != null) await _follow(context, link);
  }

  Future<void> _follow(BuildContext context, NoteLink link) async {
    if (link.isTask) {
      await _openTask(context, null, link.target);
      return;
    }
    for (final note in store.notes) {
      if (note.title.toLowerCase() == link.target.toLowerCase().trim()) {
        await _openNote(context, note.id);
        return;
      }
    }
    _toast(context, 'No note titled "${link.target}" yet.');
  }

  Future<void> _followBacklink(BuildContext context, Backlink link) async {
    if (link.sourceIsTask) {
      await _openTask(context, link.sourceId, link.sourceTitle);
    } else {
      await _openNote(context, link.sourceId);
    }
  }

  Widget _noteBody(BuildContext context, Note note) {
    final base = TextStyle(fontSize: 15.5, height: 1.55, color: Ink0.text);
    const highlight = Color(0xFFE4C441);
    final lines = note.body!.trim().split('\n');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < lines.length; i++) ...[
          _noteLine(context, note, lines[i], i, base, highlight),
        ],
      ],
    );
  }

  Widget _noteLine(BuildContext context, Note note, String line, int index,
      TextStyle base, Color highlight) {
    final check = parseChecklistLine(line.trimLeft());
    final span = buildRichSpan(
      check?.text ?? line,
      base: base,
      highlight: highlight,
      bullet: Ink0.muted,
      onUrlTap: (url) => _openLink(context, url),
      onWikiTap: (target) => _followTarget(context, target),
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
        final outgoing = LinkParser.parse(note.body);
        final backlinks = BacklinkIndex(
          store.notes,
          taskStore?.tasks ?? const <Task>[],
        ).forTarget(note.title, isTask: false);
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
                  if ((note.notebook ?? '').trim().isNotEmpty) ...[
                    Row(
                      children: [
                        Icon(Icons.book_outlined, size: 13, color: Ink0.muted),
                        const SizedBox(width: 4),
                        Text(
                          note.notebook!.trim().toUpperCase(),
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                            color: Ink0.muted,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
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
                  if (note.labels.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      children: [
                        for (final label in note.labels)
                          Chip(
                            key: Key('note-label-$label'),
                            label: Text(label,
                                style: const TextStyle(fontSize: 11.5)),
                            visualDensity: VisualDensity.compact,
                            side: BorderSide(color: Ink0.line),
                            backgroundColor: Ink0.surfaceHi,
                          ),
                      ],
                    ),
                  ],
                  if ((note.body ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: PaperPage(
                        padding: const EdgeInsets.fromLTRB(18, 20, 16, 20),
                        pinned: note.pinned,
                        child: _noteBody(context, note),
                      ),
                    ),
                  ],
                  if (outgoing.isNotEmpty) ...[
                    const SizedBox(height: 22),
                    Text('LINKS FROM THIS NOTE',
                        style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                            color: Ink0.muted)),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        for (final link in outgoing)
                          ActionChip(
                            key: Key('note-link-${link.target}'),
                            avatar: Icon(
                                link.isTask
                                    ? Icons.check_circle_outline
                                    : Icons.link,
                                size: 15),
                            label: Text(link.target),
                            onPressed: () => _follow(context, link),
                          ),
                      ],
                    ),
                  ],
                  if (backlinks.isNotEmpty) ...[
                    const SizedBox(height: 22),
                    Text('LINKED FROM',
                        style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                            color: Ink0.muted)),
                    const SizedBox(height: 4),
                    for (final link in backlinks)
                      ListTile(
                        key: Key('backlink-${link.sourceId}'),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          link.sourceIsTask
                              ? Icons.check_circle_outline
                              : Icons.sticky_note_2_outlined,
                          size: 18,
                          color: Ink0.muted,
                        ),
                        title: Text(link.sourceTitle,
                            style: TextStyle(fontSize: 13, color: Ink0.text)),
                        onTap: () => _followBacklink(context, link),
                      ),
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
