import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/task_store.dart';
import '../models/task.dart';
import '../theme.dart';
import '../utils/calendar.dart';
import '../utils/urgency.dart';
import 'task_form_sheet.dart';

/// A local month grid over the deadlines already in [TaskStore]. Tapping a day
/// selects it; the list underneath shows that day's tasks and can toggle or
/// edit them. No device-calendar permission or sync change is involved.
class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key, required this.store});

  final TaskStore store;

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  DateTime _month = startOfMonth(DateTime.now());
  DateTime _selected = startOfDay(DateTime.now());

  void _shiftMonth(int months) =>
      setState(() => _month = addMonths(_month, months));

  void _goToday() {
    final today = startOfDay(DateTime.now());
    setState(() {
      _month = startOfMonth(today);
      _selected = today;
    });
  }

  void _select(DateTime day) => setState(() {
        _selected = day;
        if (day.month != _month.month || day.year != _month.year) {
          _month = startOfMonth(day);
        }
      });

  Future<void> _edit(BuildContext context, Task task) async {
    final edited = await showTaskForm(
      context,
      existing: task,
      existingTags: widget.store.tags,
    );
    if (edited != null) await widget.store.save(edited);
  }

  Future<void> _createHere(BuildContext context) async {
    final due = DateTime(_selected.year, _selected.month, _selected.day, 9);
    final created = await showTaskForm(
      context,
      existingTags: widget.store.tags,
      initialDue: due,
    );
    if (created != null) await widget.store.add(created);
  }

  @override
  Widget build(BuildContext context) {
    final today = startOfDay(DateTime.now());
    final screen = MediaQuery.of(context).size;
    const horizontalPadding = 8.0;
    const aspectRatio = 0.82;
    final cellWidth = (screen.width - horizontalPadding * 2) / 7;
    final desiredGridHeight = 6 * cellWidth / aspectRatio;
    final maxGridHeight =
        (screen.height - 240).clamp(0.0, double.infinity).toDouble();
    final gridHeight =
        desiredGridHeight < maxGridHeight ? desiredGridHeight : maxGridHeight;
    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: widget.store,
          builder: (context, _) {
            final tasks = widget.store.tasks;
            final days = calendarGrid(_month);
            final selectedTasks = tasksOn(tasks, _selected);
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: 'Previous month',
                        icon: const Icon(Icons.chevron_left),
                        onPressed: () => _shiftMonth(-1),
                      ),
                      Expanded(
                        child: Center(
                          child: Text(
                            DateFormat('MMMM y').format(_month),
                            style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: Ink0.text),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Next month',
                        icon: const Icon(Icons.chevron_right),
                        onPressed: () => _shiftMonth(1),
                      ),
                      TextButton(
                        onPressed: _goToday,
                        child: const Text('Today'),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      for (final label in const [
                        'Mon',
                        'Tue',
                        'Wed',
                        'Thu',
                        'Fri',
                        'Sat',
                        'Sun'
                      ])
                        Expanded(
                          child: Center(
                            child: Text(label,
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Ink0.muted)),
                          ),
                        ),
                    ],
                  ),
                ),
                SizedBox(
                  height: gridHeight,
                  child: GridView.builder(
                    key: const Key('calendar-grid'),
                    padding: const EdgeInsets.symmetric(
                        horizontal: horizontalPadding),
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 7,
                      mainAxisExtent: gridHeight / 6,
                    ),
                    itemCount: days.length,
                    itemBuilder: (context, index) {
                      final day = days[index];
                      final dayTasks = tasksOn(tasks, day);
                      final inMonth =
                          day.month == _month.month && day.year == _month.year;
                      final selected = sameDay(day, _selected);
                      final isToday = sameDay(day, today);
                      final cue = dayTasks.isEmpty
                          ? null
                          : urgencyOf(openFirst(dayTasks).first).color;
                      return InkWell(
                        key: Key(
                            'calendar-day-${day.year}-${day.month}-${day.day}'),
                        onTap: () => _select(day),
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          margin: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: selected ? Ink0.surfaceHi : null,
                            borderRadius: BorderRadius.circular(10),
                            border: isToday
                                ? Border.all(color: Ink0.text, width: 1.2)
                                : null,
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                '${day.day}',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: inMonth ? Ink0.text : Ink0.muted,
                                  fontWeight: isToday
                                      ? FontWeight.w700
                                      : FontWeight.w400,
                                ),
                              ),
                              const SizedBox(height: 4),
                              if (cue != null)
                                Container(
                                  key: Key(
                                      'calendar-event-dot-${day.year}-${day.month}-${day.day}'),
                                  width: 12,
                                  height: 12,
                                  decoration: BoxDecoration(
                                      color: cue, shape: BoxShape.circle),
                                ),
                              if (dayTasks.length > 1)
                                Text('${dayTasks.length}',
                                    style: TextStyle(
                                        fontSize: 9, color: Ink0.muted)),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                        child: Text(
                          DateFormat('EEEE, d MMM').format(_selected),
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Ink0.text),
                        ),
                      ),
                      Expanded(
                        child: selectedTasks.isEmpty
                            ? Center(
                                child: Text('No deadlines on this day',
                                    style: TextStyle(
                                        fontSize: 13, color: Ink0.muted)),
                              )
                            : ListView.separated(
                                padding: const EdgeInsets.only(bottom: 96),
                                itemCount: selectedTasks.length,
                                separatorBuilder: (_, __) =>
                                    const Divider(height: 1, indent: 20),
                                itemBuilder: (context, index) {
                                  final task = selectedTasks[index];
                                  final when = DateFormat('h:mm a')
                                      .format(task.dueLocal);
                                  return ListTile(
                                    onTap: () => _edit(context, task),
                                    leading: Icon(Icons.circle,
                                        size: 9, color: urgencyOf(task).color),
                                    trailing: Checkbox(
                                      value: task.done,
                                      onChanged: (_) =>
                                          widget.store.toggleDone(task),
                                    ),
                                    title: Text(
                                      task.title,
                                      style: TextStyle(
                                        fontSize: 14,
                                        color:
                                            task.done ? Ink0.muted : Ink0.text,
                                        decoration: task.done
                                            ? TextDecoration.lineThrough
                                            : null,
                                      ),
                                    ),
                                    subtitle: Text(
                                      task.tag == null
                                          ? when
                                          : '$when · ${task.tag}',
                                      style: TextStyle(
                                          fontSize: 12, color: Ink0.muted),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _createHere(context),
        icon: const Icon(Icons.add),
        label: const Text('Deadline here'),
      ),
    );
  }
}
