import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/notes_store.dart';
import '../data/task_store.dart';
import '../models/note.dart';
import '../models/task.dart';
import '../theme.dart';

/// Everything the user deleted, kept recoverable instead of being purged.
///
/// Deleting from either list archives the item: it leaves the list and its
/// reminders stop, but it sits here until it is restored, deleted forever, or
/// the whole archive is emptied. Both kinds live on one page behind tabs so
/// there is a single place to look.
class ArchivePage extends StatelessWidget {
  const ArchivePage({
    super.key,
    required this.taskStore,
    required this.notesStore,
  });

  final TaskStore taskStore;
  final NotesStore notesStore;

  Future<void> _restoreTask(BuildContext context, Task task) async {
    await taskStore.restore(task);
    if (!context.mounted) return;
    _say(context, 'Restored "${task.title}"');
  }

  Future<void> _restoreNote(BuildContext context, Note note) async {
    final title = _noteTitle(note);
    await notesStore.restore(note);
    if (!context.mounted) return;
    _say(context, 'Restored "$title"');
  }

  static String _noteTitle(Note note) =>
      note.locked ? 'Locked note' : note.title;

  Future<void> _purgeTask(BuildContext context, Task task) async {
    if (!await _confirmDelete(context, task.title)) return;
    await taskStore.purge(task);
    if (!context.mounted) return;
    _say(context, 'Deleted "${task.title}" forever');
  }

  Future<void> _purgeNote(BuildContext context, Note note) async {
    if (!await _confirmDelete(context, _noteTitle(note))) return;
    await notesStore.purge(note);
    if (!context.mounted) return;
    _say(context, 'Deleted "${_noteTitle(note)}" forever');
  }

  Future<void> _empty(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Ink0.surface,
        title: const Text('Empty the archive?'),
        content: const Text(
          'Every archived deadline and note will be deleted for good. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child:
                const Text('Empty', style: TextStyle(color: Color(0xFFFF6B6B))),
          ),
        ],
      ),
    );
    if (ok != true) return;

    await taskStore.emptyArchive();
    await notesStore.emptyArchive();
    if (!context.mounted) return;
    _say(context, 'Archive emptied');
  }

  static Future<bool> _confirmDelete(BuildContext context, String title) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Ink0.surface,
        title: const Text('Delete forever?'),
        content: Text('"$title" will be gone for good. This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete',
                style: TextStyle(color: Color(0xFFFF6B6B))),
          ),
        ],
      ),
    );
    return ok == true;
  }

  static void _say(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: ListenableBuilder(
        listenable: Listenable.merge([taskStore, notesStore]),
        builder: (context, _) {
          final tasks = taskStore.archived;
          final notes = notesStore.archived;
          final hasAny = tasks.isNotEmpty || notes.isNotEmpty;

          return Scaffold(
            appBar: AppBar(
              title: Text(
                'Archive',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                  color: Ink0.text,
                ),
              ),
              actions: [
                IconButton(
                  tooltip: 'Empty archive',
                  onPressed: hasAny ? () => _empty(context) : null,
                  icon: const Icon(Icons.delete_sweep_outlined),
                ),
                const SizedBox(width: 4),
              ],
            ),
            body: SafeArea(
              top: false,
              child: Column(
                children: [
                  TabBar(
                    labelColor: Ink0.text,
                    unselectedLabelColor: Ink0.muted,
                    indicatorColor: Ink0.text,
                    dividerColor: Ink0.line,
                    tabs: [
                      Tab(
                          text:
                              'Deadlines${tasks.isEmpty ? '' : ' (${tasks.length})'}'),
                      Tab(
                          text:
                              'Notes${notes.isEmpty ? '' : ' (${notes.length})'}'),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _TaskArchive(
                          tasks: tasks,
                          onRestore: (t) => _restoreTask(context, t),
                          onDeleteForever: (t) => _purgeTask(context, t),
                        ),
                        _NoteArchive(
                          notes: notes,
                          onRestore: (n) => _restoreNote(context, n),
                          onDeleteForever: (n) => _purgeNote(context, n),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _TaskArchive extends StatelessWidget {
  const _TaskArchive({
    required this.tasks,
    required this.onRestore,
    required this.onDeleteForever,
  });

  final List<Task> tasks;
  final ValueChanged<Task> onRestore;
  final ValueChanged<Task> onDeleteForever;

  @override
  Widget build(BuildContext context) {
    if (tasks.isEmpty) {
      return const _EmptyArchive(
        icon: Icons.event_available,
        what: 'deadlines',
      );
    }

    return ListView(
      padding: const EdgeInsets.only(top: 8, bottom: 24),
      children: [
        for (final t in tasks)
          _ArchiveCard(
            title: t.title,
            tag: t.tag,
            subtitle: t.notes,
            archivedAt: t.archivedAt!,
            onRestore: () => onRestore(t),
            onDeleteForever: () => onDeleteForever(t),
          ),
      ],
    );
  }
}

class _NoteArchive extends StatelessWidget {
  const _NoteArchive({
    required this.notes,
    required this.onRestore,
    required this.onDeleteForever,
  });

  final List<Note> notes;
  final ValueChanged<Note> onRestore;
  final ValueChanged<Note> onDeleteForever;

  @override
  Widget build(BuildContext context) {
    if (notes.isEmpty) {
      return const _EmptyArchive(
        icon: Icons.sticky_note_2_outlined,
        what: 'notes',
      );
    }

    return ListView(
      padding: const EdgeInsets.only(top: 8, bottom: 24),
      children: [
        for (final n in notes)
          _ArchiveCard(
            title: n.locked ? 'Locked note' : n.title,
            tag: n.locked ? null : n.tag,
            subtitle: n.locked ? null : n.plainBody,
            locked: n.locked,
            archivedAt: n.archivedAt!,
            onRestore: () => onRestore(n),
            onDeleteForever: () => onDeleteForever(n),
          ),
      ],
    );
  }
}

class _ArchiveCard extends StatelessWidget {
  const _ArchiveCard({
    required this.title,
    required this.archivedAt,
    required this.onRestore,
    required this.onDeleteForever,
    this.tag,
    this.subtitle,
    this.locked = false,
  });

  final String title;
  final String? tag;
  final String? subtitle;
  final DateTime archivedAt;
  final VoidCallback onRestore;
  final VoidCallback onDeleteForever;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final trimmedTag = (tag ?? '').trim();
    final trimmedSubtitle = (subtitle ?? '').trim();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      decoration: BoxDecoration(
        color: Ink0.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Ink0.line),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (trimmedTag.isNotEmpty) ...[
                        Text(
                          trimmedTag.toUpperCase(),
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                            color: Ink0.muted,
                          ),
                        ),
                        const SizedBox(height: 5),
                      ],
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (locked) ...[
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Icon(Icons.lock_outline,
                                  size: 15, color: Ink0.muted),
                            ),
                            const SizedBox(width: 6),
                          ],
                          Expanded(
                            child: Text(
                              title,
                              style: TextStyle(
                                fontSize: 16,
                                height: 1.25,
                                fontWeight: FontWeight.w600,
                                color: Ink0.text,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (trimmedSubtitle.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          trimmedSubtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 13, color: Ink0.muted, height: 1.3),
                        ),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Delete forever',
                  onPressed: onDeleteForever,
                  icon: const Icon(Icons.delete_forever_outlined,
                      color: Color(0xFFFF6B6B)),
                ),
              ],
            ),
            Row(
              children: [
                Icon(Icons.history, size: 14, color: Ink0.muted),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    'Deleted ${DateFormat('d MMM yyyy, h:mm a').format(archivedAt.toLocal())}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: Ink0.muted),
                  ),
                ),
                TextButton(
                  onPressed: onRestore,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    minimumSize: const Size(0, 36),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Restore'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyArchive extends StatelessWidget {
  const _EmptyArchive({required this.icon, required this.what});

  final IconData icon;
  final String what;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 44, color: Ink0.muted),
            const SizedBox(height: 14),
            Text(
              'Nothing archived',
              style: TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w600, color: Ink0.text),
            ),
            const SizedBox(height: 6),
            Text(
              'Deleted $what land here, so you can bring them back if you '
              'change your mind.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, color: Ink0.muted, height: 1.45),
            ),
          ],
        ),
      ),
    );
  }
}
