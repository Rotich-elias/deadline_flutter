import 'package:flutter/material.dart';

import '../data/notes_store.dart';
import '../data/task_store.dart';
import '../models/note.dart';
import '../sync/sync_service.dart';
import '../theme.dart';
import 'archive_page.dart';
import 'note_import_ui.dart';
import 'note_card.dart';
import 'note_form_sheet.dart';
import 'note_view_page.dart';
import 'search_field.dart';
import 'sync_button.dart';
import 'tag_filter_row.dart';

class NotesListPage extends StatefulWidget {
  const NotesListPage({
    super.key,
    required this.store,
    required this.taskStore,
    required this.sync,
  });

  final NotesStore store;
  final TaskStore taskStore;
  final SyncService sync;

  @override
  State<NotesListPage> createState() => _NotesListPageState();
}

class _NotesListPageState extends State<NotesListPage> {
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  bool _searching = false;

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    setState(() {
      _searching = !_searching;
      if (!_searching) {
        _searchController.clear();
        widget.store.setQuery('');
      }
    });
    if (_searching) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _searchFocus.requestFocus());
    } else {
      _searchFocus.unfocus();
    }
  }

  void _openArchive(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) =>
          ArchivePage(taskStore: widget.taskStore, notesStore: widget.store),
    ));
  }

  Future<void> _create(BuildContext context) async {
    final n = await showNoteForm(context, existingTags: widget.store.tags);
    if (n != null) await widget.store.add(n);
  }

  void _openImportHelp(BuildContext context) => showSamsungImportHelp(context);

  void _pasteNote(BuildContext context) =>
      showPasteNoteDialog(context, widget.store);

  void _open(BuildContext context, Note note) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => NoteViewPage(store: widget.store, noteId: note.id),
    ));
  }

  Future<void> _delete(BuildContext context, Note note) async {
    await widget.store.remove(note);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('Moved "${note.title}" to archive'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => widget.store.restore(note),
        ),
      ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: Listenable.merge([widget.store, widget.sync]),
          builder: (context, _) {
            final notes = widget.store.visible;
            return Column(
              children: [
                _Header(
                  store: widget.store,
                  sync: widget.sync,
                  searching: _searching,
                  onToggleSearch: _toggleSearch,
                  onOpenArchive: () => _openArchive(context),
                  onImportHelp: () => _openImportHelp(context),
                  onPasteNote: () => _pasteNote(context),
                ),
                if (_searching)
                  SearchField(
                    controller: _searchController,
                    focusNode: _searchFocus,
                    hintText: 'Search notes',
                    onChanged: widget.store.setQuery,
                  ),
                if (widget.store.tags.isNotEmpty)
                  TagFilterRow(
                    tags: widget.store.tags,
                    selected: widget.store.tagFilter,
                    onSelect: widget.store.setTagFilter,
                  ),
                Expanded(
                  child: notes.isEmpty
                      ? _Empty(query: widget.store.query)
                      : RefreshIndicator(
                          onRefresh: widget.sync.syncNow,
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
                                    child: const Icon(Icons.archive_outlined,
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
  const _Header({
    required this.store,
    required this.sync,
    required this.searching,
    required this.onToggleSearch,
    required this.onOpenArchive,
    required this.onImportHelp,
    required this.onPasteNote,
  });
  final NotesStore store;
  final SyncService sync;
  final bool searching;
  final VoidCallback onToggleSearch;
  final VoidCallback onOpenArchive;
  final VoidCallback onImportHelp;
  final VoidCallback onPasteNote;

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
          IconButton(
            tooltip: searching ? 'Close search' : 'Search',
            onPressed: onToggleSearch,
            icon:
                Icon(searching ? Icons.close : Icons.search, color: Ink0.muted),
          ),
          IconButton(
            tooltip: 'Archive',
            onPressed: onOpenArchive,
            icon: Icon(Icons.archive_outlined, color: Ink0.muted),
          ),
          SyncButton(sync: sync),
          PopupMenuButton<String>(
            tooltip: 'Import notes',
            icon: Icon(Icons.more_vert, color: Ink0.muted),
            onSelected: (value) {
              switch (value) {
                case 'help':
                  onImportHelp();
                case 'paste':
                  onPasteNote();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'help',
                child: Text('Import from Samsung Notes'),
              ),
              PopupMenuItem(value: 'paste', child: Text('Paste a note')),
            ],
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.query});

  final String query;

  bool get _searching => query.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(_searching ? Icons.search_off : Icons.sticky_note_2_outlined,
                size: 44, color: Ink0.muted),
            const SizedBox(height: 14),
            Text(
              _searching ? 'No matches' : 'No notes yet',
              style: TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w600, color: Ink0.text),
            ),
            const SizedBox(height: 6),
            Text(
              _searching
                  ? 'Nothing matches “$query”. Try another word, or clear '
                      'the search.'
                  : 'Anything worth remembering that doesn\'t need a deadline '
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
