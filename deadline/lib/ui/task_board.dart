import 'package:flutter/material.dart';

import '../data/task_store.dart';
import '../models/task.dart';
import '../theme.dart';
import 'task_card.dart';

/// A category-based Kanban board. Columns are real synced categories, so a
/// drag between columns is an ordinary task edit (and travels with sync).
/// Tasks with no category live in the first "Uncategorised" column.
class TaskBoard extends StatelessWidget {
  const TaskBoard({
    super.key,
    required this.store,
    required this.tasks,
    required this.onEdit,
    required this.onToggle,
    required this.onPin,
    required this.showCollaboration,
  });

  final TaskStore store;
  final List<Task> tasks;
  final ValueChanged<Task> onEdit;
  final void Function(Task) onToggle;
  final void Function(Task) onPin;
  final bool showCollaboration;

  @override
  Widget build(BuildContext context) {
    final columns = <String?>[null, ...store.categories];
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      itemCount: columns.length,
      separatorBuilder: (_, __) => const SizedBox(width: 12),
      itemBuilder: (context, index) {
        final category = columns[index];
        final inColumn =
            tasks.where((t) => t.category == category).toList(growable: false);
        return _BoardColumn(
          title: category ?? 'Uncategorised',
          count: inColumn.length,
          tasks: inColumn,
          category: category,
          store: store,
          onEdit: onEdit,
          onToggle: onToggle,
          onPin: onPin,
          showCollaboration: showCollaboration,
        );
      },
    );
  }
}

class _BoardColumn extends StatelessWidget {
  const _BoardColumn({
    required this.title,
    required this.count,
    required this.tasks,
    required this.category,
    required this.store,
    required this.onEdit,
    required this.onToggle,
    required this.onPin,
    required this.showCollaboration,
  });

  final String title;
  final int count;
  final List<Task> tasks;
  final String? category;
  final TaskStore store;
  final ValueChanged<Task> onEdit;
  final void Function(Task) onToggle;
  final void Function(Task) onPin;
  final bool showCollaboration;

  @override
  Widget build(BuildContext context) {
    return DragTarget<Task>(
      key: Key('board-column-$title'),
      onAcceptWithDetails: (details) =>
          store.setCategory(details.data, category),
      builder: (context, candidates, rejected) {
        final highlighted = candidates.isNotEmpty;
        return Container(
          width: 288,
          decoration: BoxDecoration(
            color: highlighted ? Ink0.surfaceHi : Ink0.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: highlighted ? const Color(0xFFE4C441) : Ink0.line,
              width: highlighted ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                          color: Ink0.muted,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Ink0.surfaceHi,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text('$count',
                          style: TextStyle(fontSize: 11, color: Ink0.muted)),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: tasks.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(14),
                        child: Text(
                          'Drop a deadline here',
                          style: TextStyle(fontSize: 12, color: Ink0.muted),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                        itemCount: tasks.length,
                        itemBuilder: (context, index) {
                          final task = tasks[index];
                          return Draggable<Task>(
                            key: ValueKey('board-drag-${task.id}'),
                            data: task,
                            feedback: Material(
                              color: Colors.transparent,
                              child: SizedBox(
                                width: 260,
                                child: TaskCard(
                                  task: task,
                                  onToggle: () {},
                                  onEdit: () {},
                                  onPin: () {},
                                  showCollaboration: showCollaboration,
                                ),
                              ),
                            ),
                            childWhenDragging: Opacity(
                              opacity: 0.35,
                              child: TaskCard(
                                task: task,
                                onToggle: () => onToggle(task),
                                onEdit: () => onEdit(task),
                                onPin: () => onPin(task),
                                showCollaboration: showCollaboration,
                              ),
                            ),
                            child: TaskCard(
                              task: task,
                              onToggle: () => onToggle(task),
                              onEdit: () => onEdit(task),
                              onPin: () => onPin(task),
                              showCollaboration: showCollaboration,
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}
