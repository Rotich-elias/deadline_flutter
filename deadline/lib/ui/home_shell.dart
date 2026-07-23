import 'package:flutter/material.dart';

import '../data/notes_store.dart';
import '../data/task_store.dart';
import '../sync/sync_service.dart';
import '../theme.dart';
import 'notes_list_page.dart';
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
  });

  final TaskStore store;
  final NotesStore notesStore;
  final SyncService sync;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          TaskListPage(store: widget.store, sync: widget.sync),
          NotesListPage(store: widget.notesStore, sync: widget.sync),
        ],
      ),
      bottomNavigationBar: NavigationBar(
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
    );
  }
}
