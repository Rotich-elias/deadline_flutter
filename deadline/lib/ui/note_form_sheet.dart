import 'package:flutter/material.dart';

import '../models/note.dart';
import '../theme.dart';

/// Returns the saved note, or null if the sheet was dismissed.
/// Pass [existing] to edit; leave it out to create. [existingTags] powers
/// the tag suggestion chips.
Future<Note?> showNoteForm(
  BuildContext context, {
  Note? existing,
  List<String> existingTags = const [],
}) {
  return showModalBottomSheet<Note>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Ink0.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _NoteForm(existing: existing, existingTags: existingTags),
  );
}

class _NoteForm extends StatefulWidget {
  const _NoteForm({this.existing, required this.existingTags});
  final Note? existing;
  final List<String> existingTags;

  @override
  State<_NoteForm> createState() => _NoteFormState();
}

class _NoteFormState extends State<_NoteForm> {
  late final TextEditingController _title =
      TextEditingController(text: widget.existing?.title ?? '');
  late final TextEditingController _body =
      TextEditingController(text: widget.existing?.body ?? '');
  late final TextEditingController _tag =
      TextEditingController(text: widget.existing?.tag ?? '');

  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _tag.dispose();
    super.dispose();
  }

  void _submit() {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Give the note a title so you recognise it later.');
      return;
    }
    final body = _body.text.trim();
    final tag = _tag.text.trim();
    final result = widget.existing == null
        ? Note.create(
            title: title,
            body: body.isEmpty ? null : body,
            tag: tag.isEmpty ? null : tag,
          )
        : widget.existing!.copyWith(
            title: title,
            body: body,
            tag: tag,
            clearTag: tag.isEmpty,
          );
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
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
              editing ? 'Edit note' : 'New note',
              style: const TextStyle(
                  fontSize: 19, fontWeight: FontWeight.w700, color: Ink0.text),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _title,
              autofocus: !editing,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(hintText: 'Title'),
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
              controller: _body,
              maxLines: 8,
              minLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(hintText: 'Write something…'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _tag,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(hintText: 'Tag — optional'),
              onChanged: (_) => setState(() {}),
            ),
            if (tagSuggestions.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final t in tagSuggestions)
                    ActionChip(
                      label: Text(t, style: const TextStyle(fontSize: 12.5)),
                      onPressed: () {
                        _tag.text = t;
                        setState(() {});
                      },
                      backgroundColor: Ink0.surfaceHi,
                      side: const BorderSide(color: Ink0.line),
                      labelStyle: const TextStyle(color: Ink0.text),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20)),
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
                child: Text(editing ? 'Save changes' : 'Add note',
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
