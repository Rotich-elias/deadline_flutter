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
    required this.onPin,
    this.showCollaboration = false,
  });

  final Task task;
  final VoidCallback onToggle;
  final VoidCallback onEdit;
  final VoidCallback onPin;
  final bool showCollaboration;

  Color get _priorityColor => switch (task.priority) {
        Priority.high => const Color(0xFFFF6B6B),
        Priority.medium => const Color(0xFFFFA51F),
        Priority.low => const Color(0xFF5C8DEF),
        Priority.none => Ink0.muted,
      };

  String get _shortPriority => switch (task.priority) {
        Priority.high => 'HIGH',
        Priority.medium => 'MED',
        Priority.low => 'LOW',
        Priority.none => '',
      };

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
          color: task.pinned
              ? const Color(0xFFE4C441).withValues(alpha: 0.5)
              : (u == Urgency.overdue ? c.withValues(alpha: 0.45) : Ink0.line),
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
                            if (!dim)
                              _CountdownChip(text: countdownOf(task), color: c),
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
                        if (task.hasChecklist) ...[
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Icon(Icons.check_box_outlined,
                                  size: 14, color: dim ? Ink0.muted : c),
                              const SizedBox(width: 6),
                              Text(
                                '${task.checklistDone}/${task.checklist.length} steps',
                                style:
                                    TextStyle(fontSize: 12, color: Ink0.muted),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: LinearProgressIndicator(
                                  value: task.checklistDone /
                                      task.checklist.length,
                                  minHeight: 3,
                                  backgroundColor: Ink0.line,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                      dim ? Ink0.muted : c),
                                ),
                              ),
                            ],
                          ),
                        ],
                        if (showCollaboration &&
                            (task.assignedTo != null || task.hasComments)) ...[
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 10,
                            runSpacing: 4,
                            children: [
                              if (task.assignedTo != null &&
                                  task.assignedTo!.trim().isNotEmpty)
                                _CollabPill(
                                  icon: Icons.person_outline,
                                  label: task.assignedTo!.trim(),
                                  color: c,
                                  dim: dim,
                                ),
                              if (task.hasComments)
                                _CollabPill(
                                  icon: Icons.chat_bubble_outline,
                                  label: '${task.comments.length}',
                                  color: c,
                                  dim: dim,
                                ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Icon(Icons.schedule,
                                size: 14,
                                color: dim
                                    ? Ink0.muted
                                    : c.withValues(alpha: 0.9)),
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
                                  color: dim
                                      ? Ink0.muted
                                      : c.withValues(alpha: 0.9)),
                            ],
                            if (task.priority != Priority.none) ...[
                              const SizedBox(width: 8),
                              Icon(Icons.flag_outlined,
                                  size: 13, color: _priorityColor),
                              const SizedBox(width: 3),
                              Text(
                                _shortPriority,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: _priorityColor,
                                ),
                              ),
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
                  padding: const EdgeInsets.only(right: 4),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        onPressed: onPin,
                        tooltip: task.pinned ? 'Unpin' : 'Pin to top',
                        visualDensity: VisualDensity.compact,
                        icon: Icon(
                          task.pinned
                              ? Icons.push_pin
                              : Icons.push_pin_outlined,
                          size: 20,
                          color: task.pinned
                              ? const Color(0xFFE4C441)
                              : Ink0.muted,
                        ),
                      ),
                      IconButton(
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
                    ],
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
        color: color.withValues(alpha: 0.14),
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

class _CollabPill extends StatelessWidget {
  const _CollabPill({
    required this.icon,
    required this.label,
    required this.color,
    required this.dim,
  });

  final IconData icon;
  final String label;
  final Color color;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Ink0.surfaceHi,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: dim ? Ink0.muted : color),
          const SizedBox(width: 5),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 120),
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.5, color: Ink0.muted),
            ),
          ),
        ],
      ),
    );
  }
}
