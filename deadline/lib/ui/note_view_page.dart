import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/notes_store.dart';
import '../models/note.dart';
import '../theme.dart';
import 'note_form_sheet.dart';

/// Full-page read view for a single note, opened from [NotesListPage].
/// Stays open across edits (and closes itself if the note is deleted)
/// since it looks the note up live by id rather than holding a snapshot.
class NoteViewPage extends StatelessWidget {
  const NoteViewPage({super.key, required this.store, required this.noteId});

  final NotesStore store;
  final String noteId;

  Future<void> _edit(BuildContext context, Note note) async {
    final n = await showNoteForm(context, existing: note, existingTags: store.tags);
    if (n != null) await store.save(n);
  }

  Future<void> _delete(BuildContext context, Note note) async {
    await store.remove(note);
    if (!context.mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('Removed "${note.title}"'),
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
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => _edit(context, note),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
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
                    SelectableText(
                      note.body!.trim(),
                      style: TextStyle(
                          fontSize: 15.5, height: 1.55, color: Ink0.text),
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
