import 'dart:async';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../models/attachment.dart';
import '../models/note.dart';
import '../services/attachments.dart';
import '../theme.dart';
import '../utils/list_continuation.dart';
import '../utils/markup.dart';

/// Returns the saved note, or null if the sheet was dismissed.
/// Pass [existing] to edit; leave it out to create. [existingTags] powers
/// the tag suggestion chips. The initial* values pre-fill a new draft (used
/// by templates) and are ignored when [existing] is supplied.
Future<Note?> showNoteForm(
  BuildContext context, {
  Note? existing,
  List<String> existingTags = const [],
  String? initialTitle,
  String? initialBody,
  String? initialTag,
}) {
  return showModalBottomSheet<Note>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Ink0.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _NoteForm(
      existing: existing,
      existingTags: existingTags,
      initialTitle: initialTitle,
      initialBody: initialBody,
      initialTag: initialTag,
    ),
  );
}

class _NoteForm extends StatefulWidget {
  const _NoteForm({
    this.existing,
    required this.existingTags,
    this.initialTitle,
    this.initialBody,
    this.initialTag,
  });
  final Note? existing;
  final List<String> existingTags;
  final String? initialTitle;
  final String? initialBody;
  final String? initialTag;

  @override
  State<_NoteForm> createState() => _NoteFormState();
}

class _NoteFormState extends State<_NoteForm> {
  late final TextEditingController _title = TextEditingController(
      text: widget.existing?.title ?? widget.initialTitle ?? '');
  late final TextEditingController _body = TextEditingController(
      text: widget.existing?.body ?? widget.initialBody ?? '');
  late final TextEditingController _tag = TextEditingController(
      text: widget.existing?.tag ?? widget.initialTag ?? '');
  final _draftId = const Uuid().v4();
  final _attachments = AttachmentService();
  late final List<NoteAttachment> _files = [
    for (final a in widget.existing?.attachments ?? const <NoteAttachment>[]) a,
  ];
  final _addedFiles = <NoteAttachment>[];
  final _removedFiles = <NoteAttachment>[];
  final _listFormatter = ListContinuationFormatter();
  bool _saved = false;

  String? _error;

  @override
  void initState() {
    super.initState();
    // The toolbar checkbox follows the caret, which moves on both typing and
    // plain cursor moves.
    _body.addListener(_refreshChecklistState);
  }

  void _refreshChecklistState() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    // Removed files should not leave orphan bytes even on cancel; files
    // imported for a draft are only kept once the note has been saved.
    unawaited(_attachments.deleteAll(_removedFiles));
    if (!_saved) unawaited(_attachments.deleteAll(_addedFiles));
    _title.dispose();
    _body.removeListener(_refreshChecklistState);
    _body.dispose();
    _tag.dispose();
    super.dispose();
  }

  Future<void> _pickFiles() async {
    try {
      final picked = await _attachments.pickFiles();
      if (picked == null || picked.isEmpty) return;
      final imported = <NoteAttachment>[];
      for (final file in picked) {
        imported.add(await _attachments.importFile(
            widget.existing?.id ?? _draftId, file));
      }
      if (!mounted) {
        await _attachments.deleteAll(imported);
        return;
      }
      setState(() {
        _files.addAll(imported);
        _addedFiles.addAll(imported);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  void _removeFile(NoteAttachment file) {
    setState(() {
      _files.removeWhere((a) => a.id == file.id);
      _addedFiles.removeWhere((a) => a.id == file.id);
      _removedFiles.add(file);
    });
  }

  void _applyTag(String tag) {
    final selection = _body.selection;
    final result = toggleTag(
      _body.text,
      selection.start < 0 ? 0 : selection.start,
      selection.end < 0 ? 0 : selection.end,
      tag,
    );
    _body.value = _body.value.copyWith(
      text: result.text,
      selection: TextSelection(
        baseOffset: result.start,
        extentOffset: result.end,
      ),
    );
    setState(() {});
  }

  void _applyBullet() {
    final caret =
        _body.selection.baseOffset < 0 ? 0 : _body.selection.baseOffset;
    final result = toggleBullet(_body.text, caret);
    _body.value = _body.value.copyWith(
      text: result.text,
      selection: TextSelection.collapsed(offset: result.start),
    );
    setState(() {});
  }

  int get _bodyCaret =>
      _body.selection.baseOffset < 0 ? 0 : _body.selection.baseOffset;

  ({String prefix, bool checked, String spacing, String text})?
      get _currentChecklist {
    final bounds = lineBoundsAt(_body.text, _bodyCaret);
    return parseChecklistLine(_body.text.substring(bounds.start, bounds.end));
  }

  void _applyChecklist() {
    final result = toggleChecklistAtCaret(_body.text, _bodyCaret);
    _body.value = _body.value.copyWith(
      text: result.text,
      selection: TextSelection.collapsed(offset: result.start),
    );
    setState(() {});
  }

  void _submit() {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(
          () => _error = 'Give the note a title so you recognise it later.');
      return;
    }
    final body = _body.text.trim();
    final tag = _tag.text.trim();
    unawaited(_attachments.deleteAll(_removedFiles));
    _saved = true;
    final result = widget.existing == null
        ? Note(
            id: _draftId,
            title: title,
            body: body.isEmpty ? null : body,
            tag: tag.isEmpty ? null : tag,
            attachments: List.unmodifiable(_files),
          )
        : widget.existing!.copyWith(
            title: title,
            body: body,
            tag: tag,
            clearTag: tag.isEmpty,
            attachments: List.unmodifiable(_files),
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
              style: TextStyle(
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
            Text('Format',
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
                _FormatButton(
                    label: 'B',
                    tooltip: 'Bold',
                    bold: true,
                    onTap: () => _applyTag('b')),
                _FormatButton(
                    label: 'I',
                    tooltip: 'Italic',
                    italic: true,
                    onTap: () => _applyTag('i')),
                _FormatButton(
                    label: 'U',
                    tooltip: 'Underline',
                    underline: true,
                    onTap: () => _applyTag('u')),
                _FormatButton(
                    label: 'H',
                    tooltip: 'Highlight',
                    onTap: () => _applyTag('m')),
                _FormatButton(
                    label: '•', tooltip: 'Bullet point', onTap: _applyBullet),
                SizedBox(
                  width: 36,
                  height: 34,
                  child: Tooltip(
                    message: 'Checklist / tick line',
                    child: Checkbox(
                      key: const Key('note-checklist-checkbox'),
                      value: _currentChecklist?.checked ?? false,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                      activeColor: Ink0.text,
                      checkColor: Ink0.surface,
                      onChanged: (_) => _applyChecklist(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _body,
              maxLines: 8,
              minLines: 4,
              textCapitalization: TextCapitalization.sentences,
              inputFormatters: [_listFormatter],
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
                      side: BorderSide(color: Ink0.line),
                      labelStyle: TextStyle(color: Ink0.text),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20)),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 18),
            Row(
              children: [
                Text('Attachments',
                    style: TextStyle(
                        fontSize: 12,
                        color: Ink0.muted,
                        letterSpacing: 1.1,
                        fontWeight: FontWeight.w600)),
                const Spacer(),
                TextButton.icon(
                  onPressed: _pickFiles,
                  icon: const Icon(Icons.attach_file, size: 17),
                  label: const Text('Attach file'),
                ),
              ],
            ),
            if (_files.isEmpty)
              Text(
                  'Images, PDFs, recordings and documents stay on this device.',
                  style: TextStyle(fontSize: 12, color: Ink0.muted)),
            for (final file in _files)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading:
                    Icon(_fileIcon(file.kind), size: 20, color: Ink0.muted),
                title: Text(file.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: Ink0.text)),
                subtitle: Text(file.sizeLabel,
                    style: TextStyle(fontSize: 11.5, color: Ink0.muted)),
                trailing: IconButton(
                  tooltip: 'Remove attachment',
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => _removeFile(file),
                ),
              ),
            const SizedBox(height: 18),
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

IconData _fileIcon(AttachmentKind kind) => switch (kind) {
      AttachmentKind.image => Icons.image_outlined,
      AttachmentKind.pdf => Icons.picture_as_pdf_outlined,
      AttachmentKind.audio => Icons.audiotrack_outlined,
      AttachmentKind.document => Icons.description_outlined,
    };

class _FormatButton extends StatelessWidget {
  const _FormatButton({
    required this.label,
    required this.tooltip,
    required this.onTap,
    this.bold = false,
    this.italic = false,
    this.underline = false,
  });

  final String label;
  final String tooltip;
  final VoidCallback onTap;
  final bool bold;
  final bool italic;
  final bool underline;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 36,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Ink0.surfaceHi,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Ink0.line),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 15,
              color: Ink0.text,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
              fontStyle: italic ? FontStyle.italic : FontStyle.normal,
              decoration: underline ? TextDecoration.underline : null,
            ),
          ),
        ),
      ),
    );
  }
}
