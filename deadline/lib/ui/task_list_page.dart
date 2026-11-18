import 'package:flutter/material.dart';

import '../data/notes_store.dart';
import '../data/task_store.dart';
import '../models/task.dart';
import '../services/app_lock_service.dart';
import '../sync/collaboration_api.dart';
import '../sync/sync_service.dart';
import '../theme.dart';
import '../utils/urgency.dart';
import 'about_page.dart';
import 'activity_log_page.dart';
import 'app_lock_settings.dart';
import 'archive_page.dart';
import 'privacy_page.dart';
import 'shared_lists_page.dart';
import 'task_board.dart';
import 'search_field.dart';
import 'settings_sheet.dart';
import 'sync_button.dart';
import 'tag_filter_row.dart';
import 'task_card.dart';
import 'task_form_sheet.dart';

class TaskListPage extends StatefulWidget {
  const TaskListPage({
    super.key,
    required this.store,
    required this.notesStore,
    required this.sync,
    required this.appTheme,
    required this.appLock,
  });

  final TaskStore store;
  final NotesStore notesStore;
  final SyncService sync;
  final AppTheme appTheme;
  final AppLockService appLock;

  @override
  State<TaskListPage> createState() => _TaskListPageState();
}

class _TaskListPageState extends State<TaskListPage> {
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  bool _searching = false;
  bool _board = false;

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
          ArchivePage(taskStore: widget.store, notesStore: widget.notesStore),
    ));
  }

  /// Collaboration metadata travels through the Laravel sync endpoint. Offline
  /// and Drive users must not see controls that would silently never sync.
  bool get _collaborationEnabled => widget.sync.method == SyncMethod.server;

  Future<void> _create(BuildContext context) async {
    final t = await showTaskForm(context,
        existingTags: widget.store.tags,
        existingLabels: widget.store.labels,
        collaborationEnabled: _collaborationEnabled);
    if (t != null) await widget.store.add(t);
  }

  Future<void> _edit(BuildContext context, Task task) async {
    final t = await showTaskForm(context,
        existing: task,
        existingTags: widget.store.tags,
        existingLabels: widget.store.labels,
        collaborationEnabled: _collaborationEnabled);
    if (t != null) await widget.store.save(t);
  }

  Future<void> _delete(BuildContext context, Task task) async {
    await widget.store.remove(task);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('Moved "${task.title}" to archive'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => widget.store.restore(task),
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
            final tasks = widget.store.visible;
            return Column(
              children: [
                _Header(
                  store: widget.store,
                  sync: widget.sync,
                  appTheme: widget.appTheme,
                  appLock: widget.appLock,
                  notesStore: widget.notesStore,
                  searching: _searching,
                  onToggleSearch: _toggleSearch,
                  onToggleView: () => setState(() => _board = !_board),
                  boardView: _board,
                  onOpenArchive: () => _openArchive(context),
                ),
                if (_searching)
                  SearchField(
                    controller: _searchController,
                    focusNode: _searchFocus,
                    hintText: 'Search deadlines',
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
                if (widget.store.categories.isNotEmpty)
                  TagFilterRow(
                    tags: widget.store.categories,
                    selected: widget.store.categoryFilter,
                    onSelect: widget.store.setCategoryFilter,
                  ),
                Expanded(
                  child: tasks.isEmpty
                      ? _Empty(query: widget.store.query)
                      : RefreshIndicator(
                          onRefresh: widget.sync.syncNow,
                          child: _board
                              ? TaskBoard(
                                  store: widget.store,
                                  tasks: tasks,
                                  onEdit: (t) => _edit(context, t),
                                  onToggle: (t) {
                                    widget.store.toggleDone(t);
                                  },
                                  onPin: (t) {
                                    widget.store.setPinned(t, !t.pinned);
                                  },
                                  showCollaboration: _collaborationEnabled,
                                )
                              : _buildList(context, tasks),
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
        label: const Text('Add task'),
      ),
    );
  }

  Widget _buildList(BuildContext context, List<Task> tasks) {
    // Pinned tasks lead with their own group; the rest keep the urgency
    // buckets. A header appears only where the group changes.
    final items = <Widget>[];
    final pinnedCount = tasks.where((t) => t.pinned).length;
    Urgency? current;
    var inPinned = false;

    for (final t in tasks) {
      if (t.pinned != inPinned) {
        inPinned = t.pinned;
        current = null;
        if (inPinned) {
          items.add(_GroupHeader(
            label: 'Pinned',
            color: const Color(0xFFE4C441),
            count: pinnedCount,
          ));
        }
      }
      if (!inPinned) {
        final u = urgencyOf(t);
        if (u != current) {
          current = u;
          items.add(_GroupHeader(
            label: u.label,
            color: u.color,
            count: tasks.where((x) => !x.pinned && urgencyOf(x) == u).length,
          ));
        }
      }
      items.add(Dismissible(
        key: ValueKey(t.id),
        direction: DismissDirection.endToStart,
        background: Container(
          alignment: Alignment.centerRight,
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
          padding: const EdgeInsets.only(right: 20),
          decoration: BoxDecoration(
            color: const Color(0xFF3A1A22),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(Icons.archive_outlined, color: Color(0xFFFF6B6B)),
        ),
        onDismissed: (_) => _delete(context, t),
        child: TaskCard(
          task: t,
          onToggle: () => widget.store.toggleDone(t),
          onEdit: () => _edit(context, t),
          onPin: () => widget.store.setPinned(t, !t.pinned),
          showCollaboration: _collaborationEnabled,
        ),
      ));
    }

    return ListView(
      padding: const EdgeInsets.only(top: 4, bottom: 96),
      physics: const AlwaysScrollableScrollPhysics(),
      children: items,
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.store,
    required this.sync,
    required this.appTheme,
    required this.appLock,
    required this.notesStore,
    required this.searching,
    required this.onToggleSearch,
    required this.onToggleView,
    required this.boardView,
    required this.onOpenArchive,
  });
  final TaskStore store;
  final SyncService sync;
  final AppTheme appTheme;
  final AppLockService appLock;
  final NotesStore notesStore;
  final bool searching;
  final VoidCallback onToggleSearch;
  final VoidCallback onToggleView;
  final bool boardView;
  final VoidCallback onOpenArchive;

  @override
  Widget build(BuildContext context) {
    final overdue = store.overdueCount;
    final open = store.openCount;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 8, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Deadlines',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                    color: Ink0.text,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Text('$open open',
                        style: TextStyle(fontSize: 13, color: Ink0.muted)),
                    if (overdue > 0) ...[
                      Text(' · ',
                          style: TextStyle(fontSize: 13, color: Ink0.muted)),
                      Text('$overdue overdue',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Urgency.overdue.color)),
                    ],
                  ],
                ),
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
            tooltip: boardView ? 'List view' : 'Board view',
            onPressed: onToggleView,
            icon: Icon(
                boardView
                    ? Icons.view_list_outlined
                    : Icons.view_kanban_outlined,
                color: Ink0.muted),
          ),
          IconButton(
            tooltip: 'Archive',
            onPressed: onOpenArchive,
            icon: Icon(Icons.archive_outlined, color: Ink0.muted),
          ),
          SyncButton(sync: sync),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, color: Ink0.muted),
            color: Ink0.surfaceHi,
            onSelected: (v) async {
              if (v == 'completed') {
                store.toggleShowCompleted();
              } else if (v == 'sync') {
                showSyncSettings(context, sync);
              } else if (v == 'digest') {
                showDigestSettings(context, store);
              } else if (v == 'appearance') {
                showAppearanceSettings(context, appTheme);
              } else if (v == 'applock') {
                showAppLockSettings(context, appLock);
              } else if (v == 'about') {
                Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => const AboutPage(),
                ));
              } else if (v == 'privacy') {
                Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => const PrivacyPolicyPage(),
                ));
              } else if (v == 'activity') {
                final navigator = Navigator.of(context);
                final log = await store.activityLog;
                navigator.push(MaterialPageRoute<void>(
                  builder: (_) => ActivityLogPage(log: log),
                ));
              } else if (v == 'shared') {
                Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => SharedListsPage(
                    api: CollaborationApi(
                      baseUrl: sync.baseUrl,
                      token: sync.token,
                    ),
                    store: store,
                  ),
                ));
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'completed',
                child: Text(
                    store.showCompleted ? 'Hide completed' : 'Show completed'),
              ),
              const PopupMenuItem(
                  value: 'digest', child: Text('Reminders & digest')),
              const PopupMenuItem(
                  value: 'activity', child: Text('Activity log')),
              if (sync.method == SyncMethod.server && sync.configured)
                const PopupMenuItem(
                    value: 'shared', child: Text('Shared lists')),
              const PopupMenuItem(value: 'sync', child: Text('Sync settings')),
              const PopupMenuItem(
                  value: 'appearance', child: Text('Appearance')),
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
              const PopupMenuItem(value: 'about', child: Text('About')),
              const PopupMenuItem(
                  value: 'privacy', child: Text('Privacy policy')),
            ],
          ),
        ],
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader(
      {required this.label, required this.color, required this.count});
  final String label;
  final Color color;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(21, 16, 20, 6),
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 9),
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.3,
              color: Ink0.muted,
            ),
          ),
          const SizedBox(width: 8),
          Text('$count', style: TextStyle(fontSize: 11.5, color: Ink0.line)),
          const SizedBox(width: 10),
          Expanded(child: Divider(height: 1, color: Ink0.line)),
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
            Icon(_searching ? Icons.search_off : Icons.event_available,
                size: 44, color: Urgency.week.color.withValues(alpha: 0.6)),
            const SizedBox(height: 14),
            Text(
              _searching ? 'No matches' : 'Nothing due',
              style: TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w600, color: Ink0.text),
            ),
            const SizedBox(height: 6),
            Text(
              _searching
                  ? 'Nothing matches “$query”. Try another word, or clear '
                      'the search.'
                  : 'Add an assignment or lab and it will sit at the top of '
                      'the list as the date gets close.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, color: Ink0.muted, height: 1.45),
            ),
          ],
        ),
      ),
    );
  }
}
