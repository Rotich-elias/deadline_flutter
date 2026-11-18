import 'package:flutter/material.dart';

import '../data/notes_store.dart';
import '../data/task_store.dart';
import '../models/note.dart';
import '../services/app_lock_service.dart';
import '../sync/sync_service.dart';
import '../theme.dart';
import 'about_page.dart';
import 'activity_log_page.dart';
import 'app_lock_settings.dart';
import 'archive_page.dart';
import 'note_import_ui.dart';
import 'note_card.dart';
import 'note_form_sheet.dart';
import 'note_lock.dart';
import 'note_view_page.dart';
import 'search_field.dart';
import 'sync_button.dart';
import 'tag_filter_row.dart';
import 'template_picker.dart';

class NotesListPage extends StatefulWidget {
  const NotesListPage({
    super.key,
    required this.store,
    required this.taskStore,
    required this.sync,
    required this.appLock,
  });

  final NotesStore store;
  final TaskStore taskStore;
  final SyncService sync;
  final AppLockService appLock;

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
    final n = await showNoteForm(
      context,
      existingTags: widget.store.tags,
      existingLabels: widget.store.labels,
      appLock: widget.appLock,
    );
    if (n != null) await widget.store.add(n);
  }

  Future<void> _createFromTemplate(BuildContext context) async {
    final template = await showTemplatePicker(context);
    if (template == null || !context.mounted) return;
    final draft = template.apply();
    final n = await showNoteForm(
      context,
      existingTags: widget.store.tags,
      existingLabels: widget.store.labels,
      initialTitle: draft.title,
      initialBody: draft.body,
      initialTag: draft.tag,
      appLock: widget.appLock,
    );
    if (n != null) await widget.store.add(n);
  }

  void _openImportHelp(BuildContext context) => showSamsungImportHelp(context);

  void _pasteNote(BuildContext context) =>
      showPasteNoteDialog(context, widget.store);

  Future<void> _open(BuildContext context, Note note) async {
    if (note.locked && !await confirmNoteAccess(context, widget.appLock)) {
      return;
    }
    if (!context.mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => NoteViewPage(
        store: widget.store,
        noteId: note.id,
        appLock: widget.appLock,
        taskStore: widget.taskStore,
      ),
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
                  appLock: widget.appLock,
                  searching: _searching,
                  onToggleSearch: _toggleSearch,
                  onOpenArchive: () => _openArchive(context),
                  onTemplates: () => _createFromTemplate(context),
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
                if (widget.store.labels.isNotEmpty)
                  TagFilterRow(
                    tags: widget.store.labels,
                    selected: widget.store.labelFilter,
                    onSelect: widget.store.setLabelFilter,
                  ),
                if (widget.store.notebooks.isNotEmpty)
                  TagFilterRow(
                    tags: widget.store.notebooks,
                    selected: widget.store.notebookFilter,
                    onSelect: widget.store.setNotebookFilter,
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
    required this.appLock,
    required this.searching,
    required this.onToggleSearch,
    required this.onOpenArchive,
    required this.onTemplates,
    required this.onImportHelp,
    required this.onPasteNote,
  });
  final NotesStore store;
  final SyncService sync;
  final AppLockService appLock;
  final bool searching;
  final VoidCallback onToggleSearch;
  final VoidCallback onOpenArchive;
  final VoidCallback onTemplates;
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
            tooltip: 'Notes menu',
            icon: Icon(Icons.more_vert, color: Ink0.muted),
            onSelected: (value) async {
              switch (value) {
                case 'help':
                  onImportHelp();
                case 'templates':
                  onTemplates();
                case 'paste':
                  onPasteNote();
                case 'applock':
                  showAppLockSettings(context, appLock, store);
                case 'about':
                  Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => const AboutPage(),
                  ));
                case 'activity':
                  final navigator = Navigator.of(context);
                  final log = await store.activityLog;
                  navigator.push(MaterialPageRoute<void>(
                    builder: (_) => ActivityLogPage(log: log),
                  ));
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'help',
                child: Text('Import from Samsung Notes'),
              ),
              const PopupMenuItem(
                value: 'templates',
                child: Text('Start from a template'),
              ),
              const PopupMenuItem(value: 'paste', child: Text('Paste a note')),
              const PopupMenuItem(
                  value: 'activity', child: Text('Activity log')),
              const PopupMenuItem(value: 'about', child: Text('About')),
              PopupMenuItem(
                value: 'applock',
                child: Row(
                  children: [
                    Icon(
                      appLock.enabled ? Icons.lock : Icons.lock_open_outlined,
                      size: 17,
                      color: Ink0.muted,
                    ),
                    const SizedBox(width: 10),
                    const Text('App lock'),
                  ],
                ),
              ),
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
