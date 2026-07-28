import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/task.dart';
import '../theme.dart';

/// Returns the saved task, or null if the sheet was dismissed.
/// Pass [existing] to edit; leave it out to create. [existingTags] powers
/// the tag suggestion chips.
Future<Task?> showTaskForm(
  BuildContext context, {
  Task? existing,
  List<String> existingTags = const [],
}) {
  return showModalBottomSheet<Task>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Ink0.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _TaskForm(existing: existing, existingTags: existingTags),
  );
}

class _TaskForm extends StatefulWidget {
  const _TaskForm({this.existing, required this.existingTags});
  final Task? existing;
  final List<String> existingTags;

  @override
  State<_TaskForm> createState() => _TaskFormState();
}

class _TaskFormState extends State<_TaskForm> {
  late final TextEditingController _title =
      TextEditingController(text: widget.existing?.title ?? '');
  late final TextEditingController _notes =
      TextEditingController(text: widget.existing?.notes ?? '');
  late final TextEditingController _tag =
      TextEditingController(text: widget.existing?.tag ?? '');
  late DateTime _due = widget.existing?.dueLocal ?? _defaultDue();
  late Repeat _repeat = widget.existing?.repeat ?? Repeat.none;
  late final Set<int> _reminders =
      (widget.existing?.reminderMinutes ?? defaultReminderMinutes).toSet();

  String? _error;

  static DateTime _defaultDue() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day + 1, 9);
  }

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    _tag.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _due,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (d == null) return;
    setState(() => _due = DateTime(d.year, d.month, d.day, _due.hour, _due.minute));
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_due),
    );
    if (t == null) return;
    setState(() =>
        _due = DateTime(_due.year, _due.month, _due.day, t.hour, t.minute));
  }

  void _quick(DateTime when) => setState(() => _due = when);

  void _toggleReminder(int minutes) {
    setState(() {
      if (_reminders.contains(minutes)) {
        _reminders.remove(minutes);
      } else {
        _reminders.add(minutes);
      }
    });
  }

  void _submit() {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Give the task a name so you recognise it later.');
      return;
    }
    final notes = _notes.text.trim();
    final tag = _tag.text.trim();
    final reminders = _reminders.toList()..sort();
    final result = widget.existing == null
        ? Task.create(
            title: title,
            dueAtLocal: _due,
            notes: notes.isEmpty ? null : notes,
            tag: tag.isEmpty ? null : tag,
            repeat: _repeat,
            reminderMinutes: reminders.isEmpty ? [] : reminders,
          )
        : widget.existing!.copyWith(
            title: title,
            notes: notes,
            tag: tag,
            clearTag: tag.isEmpty,
            dueAtLocal: _due,
            repeat: _repeat,
            reminderMinutes: reminders,
          );
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final editing = widget.existing != null;
    final tagSuggestions =
        widget.existingTags.where((t) => t != _tag.text).toList();

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 18,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: Ink0.line,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              editing ? 'Edit task' : 'New task',
              style: TextStyle(
                  fontSize: 19, fontWeight: FontWeight.w700, color: Ink0.text),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _title,
              autofocus: !editing,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'e.g. ICT3052 forensics report',
              ),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!,
                  style: const TextStyle(
                      color: Color(0xFFFF6B6B), fontSize: 12.5)),
            ],
            const SizedBox(height: 10),
            TextField(
              controller: _notes,
              maxLines: 3,
              minLines: 2,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Notes — unit code, submission link, what is left',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _tag,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                hintText: 'Tag — e.g. ICT3052',
              ),
              onChanged: (_) => setState(() {}),
            ),
            if (tagSuggestions.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final t in tagSuggestions)
                    _Quick(label: t, onTap: () {
                      _tag.text = t;
                      setState(() {});
                    }),
                ],
              ),
            ],
            const SizedBox(height: 18),
            Text('Due',
                style: TextStyle(
                    fontSize: 12,
                    color: Ink0.muted,
                    letterSpacing: 1.1,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _PickerButton(
                    icon: Icons.calendar_today,
                    label: DateFormat('EEE d MMM y').format(_due),
                    onTap: _pickDate,
                  ),
                ),
                const SizedBox(width: 10),
                _PickerButton(
                  icon: Icons.access_time,
                  label: DateFormat('h:mm a').format(_due),
                  onTap: _pickTime,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _Quick(
                  label: 'Tonight 9pm',
                  onTap: () => _quick(today.add(const Duration(hours: 21))),
                ),
                _Quick(
                  label: 'Tomorrow 9am',
                  onTap: () =>
                      _quick(today.add(const Duration(days: 1, hours: 9))),
                ),
                _Quick(
                  label: 'In 3 days',
                  onTap: () =>
                      _quick(today.add(const Duration(days: 3, hours: 17))),
                ),
                _Quick(
                  label: 'Next week',
                  onTap: () =>
                      _quick(today.add(const Duration(days: 7, hours: 17))),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text('Repeats',
                style: TextStyle(
                    fontSize: 12,
                    color: Ink0.muted,
                    letterSpacing: 1.1,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final r in Repeat.values)
                  _SelectableChip(
                    label: r.label,
                    selected: _repeat == r,
                    onTap: () => setState(() => _repeat = r),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            Text('Remind me',
                style: TextStyle(
                    fontSize: 12,
                    color: Ink0.muted,
                    letterSpacing: 1.1,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final m in reminderPresets)
                  _SelectableChip(
                    label: _reminderLabel(m),
                    selected: _reminders.contains(m),
                    onTap: () => _toggleReminder(m),
                  ),
              ],
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _submit,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(editing ? 'Save changes' : 'Add task',
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _reminderLabel(int minutes) {
    if (minutes >= 24 * 60) {
      final days = minutes ~/ (24 * 60);
      return days == 1 ? '1 day before' : '$days days before';
    }
    if (minutes >= 60) {
      final hours = minutes ~/ 60;
      return hours == 1 ? '1 hour before' : '$hours hours before';
    }
    return '$minutes min before';
  }
}

class _PickerButton extends StatelessWidget {
  const _PickerButton(
      {required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: Ink0.surfaceHi,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: Ink0.muted),
            const SizedBox(width: 8),
            Text(label,
                style: TextStyle(fontSize: 14, color: Ink0.text)),
          ],
        ),
      ),
    );
  }
}

class _Quick extends StatelessWidget {
  const _Quick({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(label, style: const TextStyle(fontSize: 12.5)),
      onPressed: onTap,
      backgroundColor: Ink0.surfaceHi,
      side: BorderSide(color: Ink0.line),
      labelStyle: TextStyle(color: Ink0.text),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    );
  }
}

class _SelectableChip extends StatelessWidget {
  const _SelectableChip(
      {required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 12.5)),
      selected: selected,
      onSelected: (_) => onTap(),
      backgroundColor: Ink0.surfaceHi,
      selectedColor: Ink0.line,
      side: BorderSide(color: selected ? Colors.transparent : Ink0.line),
      labelStyle: TextStyle(color: Ink0.text),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    );
  }
}
