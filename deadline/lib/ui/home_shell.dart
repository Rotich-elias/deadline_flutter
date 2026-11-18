import 'package:flutter/material.dart';

import '../data/notes_store.dart';
import '../data/task_store.dart';
import '../services/app_lock_service.dart';
import '../services/location_alerts.dart';
import '../services/note_import.dart';
import '../sync/sync_service.dart';
import '../theme.dart';
import 'calendar_page.dart';
import 'my_day_page.dart';
import 'note_form_sheet.dart';
import 'notes_list_page.dart';
import 'powered_by_footer.dart';
import 'task_list_page.dart';

/// Bottom-nav switch between the four top-level sections: deadlines (the
/// original app), notes (freeform, no due date), a month calendar over the
/// deadlines and a My Day focus view. Each tab keeps its own state across
/// switches via [IndexedStack].
class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.store,
    required this.notesStore,
    required this.sync,
    required this.appTheme,
    required this.appLock,
    this.quickNote = false,
    this.pendingDraft = false,
  });

  final TaskStore store;
  final NotesStore notesStore;
  final SyncService sync;
  final AppTheme appTheme;
  final AppLockService appLock;

  /// True when this launch came from the "Quick note" home-screen shortcut.
  final bool quickNote;

  /// True when a camera capture killed the activity with an unsaved note draft.
  final bool pendingDraft;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  bool _draining = false;
  late bool _pendingQuickNote = widget.quickNote;
  late bool _pendingDraft = widget.pendingDraft;
  late int _seenQuickNoteRequests = SharedNotesInbox.instance.quickNoteRequests;

  @override
  void initState() {
    super.initState();
    SharedNotesInbox.instance.addListener(_onInboxChanged);
    SharedNotesInbox.instance.start();
    _drainSharedNotes();
    widget.appLock.addListener(_onLockChanged);
    LocationAlerts.lastError.addListener(_onBridgeError);
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeOpenQuickNote());
  }

  @override
  void dispose() {
    SharedNotesInbox.instance.removeListener(_onInboxChanged);
    widget.appLock.removeListener(_onLockChanged);
    LocationAlerts.lastError.removeListener(_onBridgeError);
    super.dispose();
  }

  void _onLockChanged() => _maybeOpenQuickNote();

  /// Location alerts are changed by the task store rather than a page, so
  /// their permission errors surface here instead of being swallowed.
  void _onBridgeError() {
    final message = LocationAlerts.lastError.value;
    if (message == null || !mounted) return;
    LocationAlerts.lastError.value = null;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// The shortcut (or a draft interrupted by the camera) opens a note form,
  /// but only after the user has passed the app-lock gate. Pending shares are
  /// drained first by initState.
  Future<void> _maybeOpenQuickNote() async {
    if ((!_pendingQuickNote && !_pendingDraft) || !mounted) return;
    if (widget.appLock.enabled && widget.appLock.locked) return;
    _pendingQuickNote = false;
    _pendingDraft = false;
    setState(() => _index = 1);
    final note = await showNoteForm(
      context,
      existingTags: widget.notesStore.tags,
      existingLabels: widget.notesStore.labels,
      appLock: widget.appLock,
    );
    if (note != null) await widget.notesStore.add(note);
  }

  /// The launcher shortcut also works while the app is already running: native
  /// pushes a `quickNote` event, which arrives here through the shared inbox.
  void _onInboxChanged() {
    _drainSharedNotes();
    final requests = SharedNotesInbox.instance.quickNoteRequests;
    if (requests > _seenQuickNoteRequests) {
      _seenQuickNoteRequests = requests;
      _pendingQuickNote = true;
    }
    _maybeOpenQuickNote();
  }

  /// Imports notes shared in from another app (Samsung Notes' "Text file"
  /// share lands here) and jumps to the Notes tab so the result is visible.
  Future<void> _drainSharedNotes() async {
    if (_draining) return;
    _draining = true;
    var imported = 0;
    var duplicates = 0;
    var blank = 0;
    try {
      while (true) {
        final texts = SharedNotesInbox.instance.take();
        if (texts.isEmpty) break;
        final outcome = await NoteImport.importAll(widget.notesStore, texts);
        imported += outcome.imported;
        duplicates += outcome.duplicates;
        blank += outcome.blank;
      }
    } finally {
      _draining = false;
    }

    if (!mounted || (imported == 0 && duplicates == 0 && blank == 0)) return;
    if (imported > 0) setState(() => _index = 1);

    final message = imported == 0 && blank == 0
        ? 'Those notes are already in your app'
        : 'Imported $imported note${imported == 1 ? '' : 's'} from Samsung Notes'
            '${duplicates > 0 ? ' · $duplicates already there' : ''}'
            '${blank > 0 ? ' · skipped $blank empty file${blank == 1 ? '' : 's'}' : ''}';
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
            appLock: widget.appLock,
          ),
          NotesListPage(
            store: widget.notesStore,
            taskStore: widget.store,
            sync: widget.sync,
            appLock: widget.appLock,
          ),
          CalendarPage(store: widget.store),
          MyDayPage(store: widget.store),
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
              NavigationDestination(
                icon: Icon(Icons.calendar_month_outlined),
                selectedIcon: Icon(Icons.calendar_month),
                label: 'Calendar',
              ),
              NavigationDestination(
                icon: Icon(Icons.today_outlined),
                selectedIcon: Icon(Icons.today),
                label: 'My Day',
              ),
            ],
          ),
        ],
      ),
    );
  }
}
