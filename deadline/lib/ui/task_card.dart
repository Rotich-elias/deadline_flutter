import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/task.dart';
import '../theme.dart';
import '../utils/urgency.dart';

class TaskCard extends StatelessWidget {
  const TaskCard({
    super.key,
    required this.task,
    required this.onToggle,
    required this.onEdit,
  });

  final Task task;
  final VoidCallback onToggle;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final u = urgencyOf(task);
    final c = u.color;
    final pressure = pressureOf(task);
    final dim = task.done;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      decoration: BoxDecoration(
        color: Ink0.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: u == Urgency.overdue ? c.withOpacity(0.45) : Ink0.line,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onEdit,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // The rail is the whole point: colour = how close this is.
                Container(width: 5, color: dim ? Ink0.line : c),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if ((task.tag ?? '').trim().isNotEmpty) ...[
                          _TagPill(text: task.tag!.trim(), color: c, dim: dim),
                          const SizedBox(height: 5),
                        ],
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                task.title,
                                style: TextStyle(
                                  fontSize: 16,
                                  height: 1.25,
                                  fontWeight: FontWeight.w600,
                                  color: dim ? Ink0.muted : Ink0.text,
                                  decoration: dim
                                      ? TextDecoration.lineThrough
                                      : TextDecoration.none,
                                  decorationColor: Ink0.muted,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (!dim) _CountdownChip(text: countdownOf(task), color: c),
                          ],
                        ),
                        if ((task.notes ?? '').trim().isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            task.notes!.trim(),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 13, color: Ink0.muted, height: 1.3),
                          ),
                        ],
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Icon(Icons.schedule,
                                size: 14,
                                color: dim ? Ink0.muted : c.withOpacity(0.9)),
                            const SizedBox(width: 5),
                            Text(
                              _whenLabel(task.dueLocal),
                              style: TextStyle(
                                  fontSize: 12.5,
                                  color: Ink0.muted,
                                  letterSpacing: 0.1),
                            ),
                            if (task.repeat != Repeat.none) ...[
                              const SizedBox(width: 8),
                              Icon(Icons.repeat,
                                  size: 13,
                                  color: dim ? Ink0.muted : c.withOpacity(0.9)),
                            ],
                            if (task.dirty) ...[
                              const SizedBox(width: 8),
                              Icon(Icons.cloud_off,
                                  size: 13, color: Ink0.muted),
                            ],
                          ],
                        ),
                        if (!dim) ...[
                          const SizedBox(height: 9),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(3),
                            child: LinearProgressIndicator(
                              value: pressure,
                              minHeight: 3,
                              backgroundColor: Ink0.line,
                              valueColor: AlwaysStoppedAnimation(c),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Center(
                    child: IconButton(
                      onPressed: onToggle,
                      tooltip: task.done ? 'Reopen' : 'Mark done',
                      icon: Icon(
                        task.done
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                        color: task.done ? Ink0.muted : c,
                        size: 26,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _whenLabel(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final that = DateTime(d.year, d.month, d.day);
    final days = that.difference(today).inDays;
    final time = DateFormat('h:mm a').format(d);

    if (days == 0) return 'Today, $time';
    if (days == 1) return 'Tomorrow, $time';
    if (days == -1) return 'Yesterday, $time';
    if (days > 1 && days < 7) return '${DateFormat('EEEE').format(d)}, $time';
    return '${DateFormat('EEE d MMM').format(d)}, $time';
  }
}

class _TagPill extends StatelessWidget {
  const _TagPill({required this.text, required this.color, required this.dim});
  final String text;
  final Color color;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.6,
        color: dim ? Ink0.muted : color,
      ),
    );
  }
}

class _CountdownChip extends StatelessWidget {
  const _CountdownChip({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: color,
          letterSpacing: 0.2,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}
