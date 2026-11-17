import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/task_store.dart';
import '../models/task.dart';
import '../theme.dart';
import '../utils/my_day.dart';
import '../utils/urgency.dart';
import 'task_form_sheet.dart';

/// A deliberately small focus view: overdue work, today's remaining deadlines
/// and anything pinned for later. It reads the same [TaskStore] as the main
/// list, so completing or editing here updates reminders, search and sync.
class MyDayPage extends StatefulWidget {
  const MyDayPage({super.key, required this.store});

  final TaskStore store;

  @override
  State<MyDayPage> createState() => _MyDayPageState();
}

class _MyDayPageState extends State<MyDayPage> {
  Future<void> _edit(BuildContext context, Task task) async {
    final edited = await showTaskForm(
      context,
      existing: task,
      existingTags: widget.store.tags,
    );
    if (edited != null) await widget.store.save(edited);
  }

  Future<void> _create(BuildContext context) async {
    final now = DateTime.now();
    final due = DateTime(now.year, now.month, now.day, 9);
    final created = await showTaskForm(
      context,
      existingTags: widget.store.tags,
      initialDue: due,
    );
    if (created != null) await widget.store.add(created);
  }

  Widget _sectionTitle(String label, int count, Color color) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 14, 4, 5),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Ink0.muted,
            ),
          ),
          const SizedBox(width: 6),
          Text('$count', style: TextStyle(fontSize: 11, color: Ink0.muted)),
        ],
      ),
    );
  }

  Widget _taskRow(Task task) {
    final parts = <String>[
      DateFormat('h:mm a').format(task.dueLocal),
      countdownOf(task),
    ];
    if (task.tag != null && task.tag!.isNotEmpty) parts.add(task.tag!);
    // Keep editing on the text only, so tapping the checkbox cannot also open
    // the task form underneath it.
    void open() => _edit(context, task);

    return Card(
      color: Ink0.surface,
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 3),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Ink0.line),
      ),
      child: ListTile(
        leading: Icon(Icons.circle, size: 9, color: urgencyOf(task).color),
        title: InkWell(
          onTap: open,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  task.title,
                  style: TextStyle(
                    fontSize: 14,
                    color: task.done ? Ink0.muted : Ink0.text,
                    decoration: task.done ? TextDecoration.lineThrough : null,
                  ),
                ),
              ),
              if (task.pinned)
                const Padding(
                  padding: EdgeInsets.only(left: 6),
                  child:
                      Icon(Icons.push_pin, size: 14, color: Color(0xFFE4C441)),
                ),
            ],
          ),
        ),
        subtitle: InkWell(
          onTap: open,
          child: Text(
            parts.join(' · '),
            style: TextStyle(fontSize: 12, color: Ink0.muted),
          ),
        ),
        trailing: Checkbox(
          value: task.done,
          onChanged: (_) => widget.store.toggleDone(task),
        ),
      ),
    );
  }

  Widget _emptyState(MyDayGroups groups) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline,
                size: 52, color: Urgency.week.color),
            const SizedBox(height: 14),
            Text(
              'All clear for today',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: Ink0.text,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              groups.completedToday > 0
                  ? '${groups.completedToday} already done. Overdue, today\'s '
                      'deadlines and pinned tasks will show up here.'
                  : 'Overdue deadlines, today\'s work and pinned tasks will '
                      'show up here.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Ink0.muted),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: widget.store,
          builder: (context, _) {
            final groups = groupMyDay(widget.store.tasks, now: now);
            final subtitle = DateFormat('EEEE, d MMM').format(now) +
                (groups.completedToday > 0
                    ? ' · ${groups.completedToday} done today'
                    : '');
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'My Day',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                color: Ink0.text,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              subtitle,
                              style:
                                  TextStyle(fontSize: 12.5, color: Ink0.muted),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 11, vertical: 6),
                        decoration: BoxDecoration(
                          color: Ink0.surfaceHi,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${groups.total} open',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Ink0.text),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: groups.isEmpty
                      ? _emptyState(groups)
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 96),
                          children: [
                            if (groups.overdue.isNotEmpty) ...[
                              _sectionTitle('Overdue', groups.overdue.length,
                                  Urgency.overdue.color),
                              for (final task in groups.overdue) _taskRow(task),
                            ],
                            if (groups.today.isNotEmpty) ...[
                              _sectionTitle('Today', groups.today.length,
                                  Urgency.today.color),
                              for (final task in groups.today) _taskRow(task),
                            ],
                            if (groups.pinned.isNotEmpty) ...[
                              _sectionTitle('Pinned', groups.pinned.length,
                                  const Color(0xFFE4C441)),
                              for (final task in groups.pinned) _taskRow(task),
                            ],
                          ],
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
        label: const Text('Add for today'),
      ),
    );
  }
}
