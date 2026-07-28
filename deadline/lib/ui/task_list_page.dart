import 'package:flutter/material.dart';

import '../data/task_store.dart';
import '../models/task.dart';
import '../sync/sync_service.dart';
import '../theme.dart';
import '../utils/urgency.dart';
import 'settings_sheet.dart';
import 'sync_button.dart';
import 'tag_filter_row.dart';
import 'task_card.dart';
import 'task_form_sheet.dart';

class TaskListPage extends StatelessWidget {
  const TaskListPage({
    super.key,
    required this.store,
    required this.sync,
    required this.appTheme,
  });

  final TaskStore store;
  final SyncService sync;
  final AppTheme appTheme;

  Future<void> _create(BuildContext context) async {
    final t = await showTaskForm(context, existingTags: store.tags);
    if (t != null) await store.add(t);
  }

  Future<void> _edit(BuildContext context, Task task) async {
    final t = await showTaskForm(context,
        existing: task, existingTags: store.tags);
    if (t != null) await store.save(t);
  }

  Future<void> _delete(BuildContext context, Task task) async {
    await store.remove(task);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('Removed "${task.title}"'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => store.restore(task),
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
            final tasks = store.visible;
            return Column(
              children: [
                _Header(store: store, sync: sync, appTheme: appTheme),
                if (store.tags.isNotEmpty)
                  TagFilterRow(
                    tags: store.tags,
                    selected: store.tagFilter,
                    onSelect: store.setTagFilter,
                  ),
                Expanded(
                  child: tasks.isEmpty
                      ? const _Empty()
                      : RefreshIndicator(
                          onRefresh: sync.syncNow,
                          child: _buildList(context, tasks),
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
    // Tasks arrive sorted by due date, so a group header is needed only where
    // the urgency bucket changes.
    final items = <Widget>[];
    Urgency? current;

    for (final t in tasks) {
      final u = urgencyOf(t);
      if (u != current) {
        current = u;
        items.add(_GroupHeader(
          label: u.label,
          color: u.color,
          count: tasks.where((x) => urgencyOf(x) == u).length,
        ));
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
          child: const Icon(Icons.delete_outline, color: Color(0xFFFF6B6B)),
        ),
        onDismissed: (_) => _delete(context, t),
        child: TaskCard(
          task: t,
          onToggle: () => store.toggleDone(t),
          onEdit: () => _edit(context, t),
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
  const _Header(
      {required this.store, required this.sync, required this.appTheme});
  final TaskStore store;
  final SyncService sync;
  final AppTheme appTheme;

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
                        style:
                            TextStyle(fontSize: 13, color: Ink0.muted)),
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
          SyncButton(sync: sync),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, color: Ink0.muted),
            color: Ink0.surfaceHi,
            onSelected: (v) {
              if (v == 'completed') {
                store.toggleShowCompleted();
              } else if (v == 'sync') {
                showSyncSettings(context, sync);
              } else if (v == 'digest') {
                showDigestSettings(context, store);
              } else if (v == 'appearance') {
                showAppearanceSettings(context, appTheme);
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'completed',
                child: Text(store.showCompleted
                    ? 'Hide completed'
                    : 'Show completed'),
              ),
              const PopupMenuItem(
                  value: 'digest', child: Text('Daily digest')),
              const PopupMenuItem(value: 'sync', child: Text('Sync settings')),
              const PopupMenuItem(
                  value: 'appearance', child: Text('Appearance')),
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
          Text('$count',
              style: TextStyle(fontSize: 11.5, color: Ink0.line)),
          const SizedBox(width: 10),
          Expanded(child: Divider(height: 1, color: Ink0.line)),
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
            Icon(Icons.event_available,
                size: 44, color: Urgency.week.color.withOpacity(0.6)),
            const SizedBox(height: 14),
            Text(
              'Nothing due',
              style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: Ink0.text),
            ),
            const SizedBox(height: 6),
            Text(
              'Add an assignment or lab and it will sit at the top of the '
              'list as the date gets close.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, color: Ink0.muted, height: 1.45),
            ),
          ],
        ),
      ),
    );
  }
}
