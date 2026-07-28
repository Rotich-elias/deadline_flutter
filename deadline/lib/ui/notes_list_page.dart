import 'package:flutter/material.dart';

import '../data/notes_store.dart';
import '../models/note.dart';
import '../sync/sync_service.dart';
import '../theme.dart';
import 'note_card.dart';
import 'note_form_sheet.dart';
import 'note_view_page.dart';
import 'sync_button.dart';
import 'tag_filter_row.dart';

class NotesListPage extends StatelessWidget {
  const NotesListPage({super.key, required this.store, required this.sync});

  final NotesStore store;
  final SyncService sync;

  Future<void> _create(BuildContext context) async {
    final n = await showNoteForm(context, existingTags: store.tags);
    if (n != null) await store.add(n);
  }

  void _open(BuildContext context, Note note) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => NoteViewPage(store: store, noteId: note.id),
    ));
  }

  Future<void> _delete(BuildContext context, Note note) async {
    await store.remove(note);
    if (!context.mounted) return;
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
    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: Listenable.merge([store, sync]),
          builder: (context, _) {
            final notes = store.visible;
            return Column(
              children: [
                _Header(store: store, sync: sync),
                if (store.tags.isNotEmpty)
                  TagFilterRow(
                    tags: store.tags,
                    selected: store.tagFilter,
                    onSelect: store.setTagFilter,
                  ),
                Expanded(
                  child: notes.isEmpty
                      ? const _Empty()
                      : RefreshIndicator(
                          onRefresh: sync.syncNow,
                          child: ListView(
                            padding: const EdgeInsets.only(top: 8, bottom: 96),
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                              for (final n in notes)
                                Dismissible(
                                  key: ValueKey(n.id),
                                  direction: DismissDirection.endToStart,
                                  background: Container(
                                    alignment: Alignment.centerRight,
                                    margin: const EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 5),
                                    padding: const EdgeInsets.only(right: 20),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF3A1A22),
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: const Icon(Icons.delete_outline,
                                        color: Color(0xFFFF6B6B)),
                                  ),
                                  onDismissed: (_) => _delete(context, n),
                                  child: NoteCard(
                                    note: n,
                                    onEdit: () => _open(context, n),
                                  ),
                                ),
                            ],
                          ),
                        ),
                ),
              ],
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _create(context),
        icon: const Icon(Icons.add),
        label: const Text('Add note'),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.store, required this.sync});
  final NotesStore store;
  final SyncService sync;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 8, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Notes',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                    color: Ink0.text,
                  ),
                ),
                const SizedBox(height: 3),
                Text('${store.notes.length} saved',
                    style: TextStyle(fontSize: 13, color: Ink0.muted)),
              ],
            ),
          ),
          SyncButton(sync: sync),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.sticky_note_2_outlined, size: 44, color: Ink0.muted),
            const SizedBox(height: 14),
            Text(
              'No notes yet',
              style: TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w600, color: Ink0.text),
            ),
            const SizedBox(height: 6),
            Text(
              'Anything worth remembering that doesn\'t need a deadline '
              'goes here.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, color: Ink0.muted, height: 1.45),
            ),
          ],
        ),
      ),
    );
  }
}
