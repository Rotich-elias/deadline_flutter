import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/task.dart';
import '../models/task_comment.dart';
import '../theme.dart';
import '../utils/smart_extract.dart';

/// Returns the saved task, or null if the sheet was dismissed.
/// Pass [existing] to edit; leave it out to create. [existingTags] powers
/// the tag suggestion chips. [initialDue] pre-fills a new task's due date,
/// used when creating one from a selected calendar day. [collaborationEnabled]
/// reveals the assignee and comment controls, which are only offered when the
/// app is configured for server sync.
Future<Task?> showTaskForm(
  BuildContext context, {
  Task? existing,
  List<String> existingTags = const [],
  DateTime? initialDue,
  bool collaborationEnabled = false,
}) {
  return showModalBottomSheet<Task>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Ink0.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _TaskForm(
      existing: existing,
      existingTags: existingTags,
      initialDue: initialDue,
      collaborationEnabled: collaborationEnabled,
    ),
  );
}

class _TaskForm extends StatefulWidget {
  const _TaskForm({
    this.existing,
    required this.existingTags,
    this.initialDue,
    this.collaborationEnabled = false,
  });
  final Task? existing;
  final List<String> existingTags;
  final DateTime? initialDue;
  final bool collaborationEnabled;

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
  late DateTime _due =
      widget.existing?.dueLocal ?? widget.initialDue ?? _defaultDue();
  late Repeat _repeat = widget.existing?.repeat ?? Repeat.none;
  late Priority _priority = widget.existing?.priority ?? Priority.none;
  late final Set<int> _reminders =
      (widget.existing?.reminderMinutes ?? defaultReminderMinutes).toSet();
  late final List<_ChecklistRow> _checklist = [
    for (final item in widget.existing?.checklist ?? const <ChecklistItem>[])
      _ChecklistRow(item),
  ];
  late final TextEditingController _assignee =
      TextEditingController(text: widget.existing?.assignedTo ?? '');
  late final TextEditingController _commentAuthor =
      TextEditingController(text: 'Me');
  final _commentBody = TextEditingController();
  late final List<TaskComment> _comments = [
    for (final comment in widget.existing?.comments ?? const <TaskComment>[])
      comment,
  ];

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
    _assignee.dispose();
    _commentAuthor.dispose();
    _commentBody.dispose();
    for (final row in _checklist) {
      row.dispose();
    }
    super.dispose();
  }

  void _addChecklistRow() => setState(() => _checklist.add(_ChecklistRow()));

  void _removeChecklistRow(int index) => setState(() {
        _checklist[index].dispose();
        _checklist.removeAt(index);
      });

  void _moveChecklistRow(int index, int delta) => setState(() {
        final target = index + delta;
        if (target < 0 || target >= _checklist.length) return;
        final row = _checklist.removeAt(index);
        _checklist.insert(target, row);
      });

  List<ChecklistItem> _checklistItems() => [
        for (final row in _checklist)
          if (row.controller.text.trim().isNotEmpty)
            ChecklistItem(
              id: row.id,
              title: row.controller.text.trim(),
              done: row.done,
            ),
      ];

  void _addComment() {
    final body = _commentBody.text.trim();
    if (body.isEmpty) return;
    setState(() {
      _comments.add(TaskComment.create(
        author: _commentAuthor.text,
        body: body,
      ));
      _commentBody.clear();
    });
  }

  void _removeComment(String id) =>
      setState(() => _comments.removeWhere((c) => c.id == id));

  Future<void> _pasteText() async {
    final draft = await showDialog<SmartDraft>(
      context: context,
      builder: (_) => const _SmartPasteDialog(),
    );
    if (draft == null || !mounted || draft.isEmpty) return;

    setState(() {
      if (draft.title.isNotEmpty) _title.text = draft.title;
      if (draft.notes != null) _notes.text = draft.notes!;
      if (draft.tag != null) _tag.text = draft.tag!;
      if (draft.due != null) _due = draft.due!;
      for (final row in _checklist) {
        row.dispose();
      }
      _checklist
        ..clear()
        ..addAll([
          for (final step in draft.checklist)
            _ChecklistRow()..controller.text = step,
        ]);
      _error = null;
    });
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _due,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (d == null) return;
    setState(
        () => _due = DateTime(d.year, d.month, d.day, _due.hour, _due.minute));
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
      setState(
          () => _error = 'Give the task a name so you recognise it later.');
      return;
    }
    final notes = _notes.text.trim();
    final tag = _tag.text.trim();
    final assignedTo = _assignee.text.trim();
    final reminders = _reminders.toList()..sort();
    final result = widget.existing == null
        ? Task.create(
            title: title,
            dueAtLocal: _due,
            notes: notes.isEmpty ? null : notes,
            tag: tag.isEmpty ? null : tag,
            repeat: _repeat,
            reminderMinutes: reminders.isEmpty ? [] : reminders,
            priority: _priority,
            checklist: _checklistItems(),
            assignedTo: assignedTo.isEmpty ? null : assignedTo,
            comments: _comments,
          )
        : widget.existing!.copyWith(
            title: title,
            notes: notes,
            tag: tag,
            clearTag: tag.isEmpty,
            dueAtLocal: _due,
            repeat: _repeat,
            reminderMinutes: reminders,
            priority: _priority,
            checklist: _checklistItems(),
            clearAssignedTo: assignedTo.isEmpty,
            assignedTo: assignedTo,
            comments: _comments,
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
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _pasteText,
                icon: const Icon(Icons.auto_fix_high, size: 16),
                label: const Text('Paste text to fill this form'),
              ),
            ),
            const SizedBox(height: 4),
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
                    _Quick(
                        label: t,
                        onTap: () {
                          _tag.text = t;
                          setState(() {});
                        }),
                ],
              ),
            ],
            const SizedBox(height: 18),
            Row(
              children: [
                Text('Checklist',
                    style: TextStyle(
                        fontSize: 12,
                        color: Ink0.muted,
                        letterSpacing: 1.1,
                        fontWeight: FontWeight.w600)),
                const SizedBox(width: 8),
                if (_checklist.isNotEmpty)
                  Text(
                    '${_checklist.where((r) => r.done).length}/${_checklist.length}',
                    style: TextStyle(fontSize: 12, color: Ink0.muted),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            for (var i = 0; i < _checklist.length; i++) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Checkbox(
                      value: _checklist[i].done,
                      onChanged: (value) =>
                          setState(() => _checklist[i].done = value ?? false),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _checklist[i].controller,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          hintText: 'Step — what needs doing?',
                          isDense: true,
                        ),
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 32,
                          height: 24,
                          child: IconButton(
                            icon: const Icon(Icons.arrow_upward, size: 16),
                            padding: EdgeInsets.zero,
                            onPressed:
                                i == 0 ? null : () => _moveChecklistRow(i, -1),
                          ),
                        ),
                        SizedBox(
                          width: 32,
                          height: 24,
                          child: IconButton(
                            icon: const Icon(Icons.arrow_downward, size: 16),
                            padding: EdgeInsets.zero,
                            onPressed: i == _checklist.length - 1
                                ? null
                                : () => _moveChecklistRow(i, 1),
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => _removeChecklistRow(i),
                    ),
                  ],
                ),
              ),
            ],
            TextButton.icon(
              onPressed: _addChecklistRow,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add step'),
            ),
            const SizedBox(height: 10),
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
            Text('Priority',
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
                for (final p in Priority.values)
                  _SelectableChip(
                    label: p.label,
                    selected: _priority == p,
                    onTap: () => setState(() => _priority = p),
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
            if (widget.collaborationEnabled) ...[
              const SizedBox(height: 18),
              Text('Collaboration',
                  style: TextStyle(
                      fontSize: 12,
                      color: Ink0.muted,
                      letterSpacing: 1.1,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              TextField(
                controller: _assignee,
                decoration: const InputDecoration(
                  hintText: 'Assignee — email or name',
                  prefixIcon: Icon(Icons.person_outline, size: 18),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 14),
              Text('Discussion',
                  style: TextStyle(
                      fontSize: 12,
                      color: Ink0.muted,
                      letterSpacing: 1.1,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              if (_comments.isEmpty)
                Text('No comments yet. Start the conversation below.',
                    style: TextStyle(fontSize: 12, color: Ink0.muted)),
              for (final comment in _comments)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.chat_bubble_outline,
                          size: 15, color: Ink0.muted),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${comment.author} · '
                              '${DateFormat('d MMM, h:mm a').format(comment.createdAt.toLocal())}',
                              style: TextStyle(fontSize: 11, color: Ink0.muted),
                            ),
                            const SizedBox(height: 2),
                            Text(comment.body,
                                style:
                                    TextStyle(fontSize: 13, color: Ink0.text)),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 16),
                        tooltip: 'Remove comment',
                        onPressed: () => _removeComment(comment.id),
                      ),
                    ],
                  ),
                ),
              Row(
                children: [
                  SizedBox(
                    width: 86,
                    child: TextField(
                      controller: _commentAuthor,
                      decoration: const InputDecoration(
                        hintText: 'As',
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _commentBody,
                      decoration: const InputDecoration(
                        hintText: 'Write a comment…',
                        isDense: true,
                      ),
                      onSubmitted: (_) => _addComment(),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.send, size: 18),
                    tooltip: 'Add comment',
                    onPressed: _addComment,
                  ),
                ],
              ),
            ],
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

/// Editable state for one checklist line in the form. The controller keeps
/// typing responsive while the id/done pair travels with the saved task.
class _ChecklistRow {
  _ChecklistRow([ChecklistItem? item])
      : id = item?.id ?? ChecklistItem.create('').id,
        done = item?.done ?? false,
        controller = TextEditingController(text: item?.title ?? '');

  final String id;
  bool done;
  final TextEditingController controller;

  void dispose() => controller.dispose();
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
            Text(label, style: TextStyle(fontSize: 14, color: Ink0.text)),
          ],
        ),
      ),
    );
  }
}

/// Small modal used by the paste button. The extracted result is returned to
/// the task form, which stays fully editable — nothing is saved here.
class _SmartPasteDialog extends StatefulWidget {
  const _SmartPasteDialog();

  @override
  State<_SmartPasteDialog> createState() => _SmartPasteDialogState();
}

class _SmartPasteDialogState extends State<_SmartPasteDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _extract() {
    final draft = extractSmartDraft(_controller.text);
    Navigator.of(context).pop(draft);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Ink0.surface,
      title: Text('Paste a message or note',
          style: TextStyle(fontSize: 17, color: Ink0.text)),
      content: SizedBox(
        width: double.maxFinite,
        child: TextField(
          controller: _controller,
          autofocus: true,
          maxLines: 8,
          minLines: 5,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            hintText: 'e.g. Submit report tomorrow 5pm #ICT3052\n'
                '- collect receipts\n- email lecturer',
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _extract,
          child: const Text('Extract'),
        ),
      ],
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    );
  }
}
