import 'package:flutter/material.dart';

import '../data/notes_store.dart';
import '../data/task_store.dart';
import '../services/note_import.dart';
import '../sync/sync_service.dart';
import '../theme.dart';
import 'notes_list_page.dart';
import 'powered_by_footer.dart';
import 'task_list_page.dart';

/// Bottom-nav switch between the two top-level sections: deadlines (the
/// original app) and notes (freeform, no due date). Each tab keeps its own
/// state across switches via [IndexedStack].
class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.store,
    required this.notesStore,
    required this.sync,
    required this.appTheme,
  });

  final TaskStore store;
  final NotesStore notesStore;
  final SyncService sync;
  final AppTheme appTheme;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  bool _draining = false;

  @override
  void initState() {
    super.initState();
    SharedNotesInbox.instance.addListener(_drainSharedNotes);
    SharedNotesInbox.instance.start();
    _drainSharedNotes();
  }

  @override
  void dispose() {
    SharedNotesInbox.instance.removeListener(_drainSharedNotes);
    super.dispose();
  }

  /// Imports notes shared in from another app (Samsung Notes' "Text file"
  /// share lands here) and jumps to the Notes tab so the result is visible.
  Future<void> _drainSharedNotes() async {
    if (_draining) return;
    _draining = true;
    var imported = 0;
    var duplicates = 0;
    try {
      while (true) {
        final texts = SharedNotesInbox.instance.take();
        if (texts.isEmpty) break;
        final outcome = await NoteImport.importAll(widget.notesStore, texts);
        imported += outcome.imported;
        duplicates += outcome.duplicates;
      }
    } finally {
      _draining = false;
    }

    if (!mounted || (imported == 0 && duplicates == 0)) return;
    if (imported > 0) setState(() => _index = 1);

    final message = imported == 0
        ? 'Those notes are already in your app'
        : 'Imported $imported note${imported == 1 ? '' : 's'} from Samsung Notes';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          TaskListPage(
            store: widget.store,
            notesStore: widget.notesStore,
            sync: widget.sync,
            appTheme: widget.appTheme,
          ),
          NotesListPage(
            store: widget.notesStore,
            taskStore: widget.store,
            sync: widget.sync,
          ),
        ],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        // Stretch so the credit strip spans the full width and blends into the
        // navigation bar below it instead of hugging the text.
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ColoredBox(
            color: Ink0.surface,
            child: const PoweredByFooter(
              padding: EdgeInsets.only(top: 6, bottom: 0),
            ),
          ),
          NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            backgroundColor: Ink0.surface,
            indicatorColor: Ink0.line,
            height: 60,
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.event_note_outlined),
                selectedIcon: Icon(Icons.event_note),
                label: 'Deadlines',
              ),
              NavigationDestination(
                icon: Icon(Icons.sticky_note_2_outlined),
                selectedIcon: Icon(Icons.sticky_note_2),
                label: 'Notes',
              ),
            ],
          ),
        ],
      ),
    );
  }
}
