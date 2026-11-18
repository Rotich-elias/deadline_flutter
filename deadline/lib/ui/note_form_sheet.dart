import 'dart:async';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../models/attachment.dart';
import '../models/note.dart';
import '../services/app_lock_service.dart';
import '../services/attachments.dart';
import '../services/note_draft_service.dart';
import '../services/platform_bridge.dart';
import '../theme.dart';
import '../utils/list_continuation.dart';
import '../utils/markup.dart';
import '../utils/web_clip.dart';
import 'label_editor.dart';

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
  List<String> existingLabels = const [],
  AppLockService? appLock,
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
      existingLabels: existingLabels,
      appLock: appLock,
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
    this.existingLabels = const [],
    this.appLock,
  });
  final Note? existing;
  final List<String> existingTags;
  final String? initialTitle;
  final String? initialBody;
  final String? initialTag;
  final List<String> existingLabels;
  final AppLockService? appLock;

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
  late final TextEditingController _notebook =
      TextEditingController(text: widget.existing?.notebook ?? '');
  late List<String> _labels = [...?widget.existing?.labels];
  String _draftId = const Uuid().v4();
  final _drafts = NoteDraftService();
  final _attachments = AttachmentService();
  late final List<NoteAttachment> _files = [
    for (final a in widget.existing?.attachments ?? const <NoteAttachment>[]) a,
  ];
  final _addedFiles = <NoteAttachment>[];
  final _removedFiles = <NoteAttachment>[];
  final _listFormatter = ListContinuationFormatter();
  bool _saved = false;
  bool _recording = false;

  String? _error;

  @override
  void initState() {
    super.initState();
    // The toolbar checkbox follows the caret, which moves on both typing and
    // plain cursor moves.
    _body.addListener(_refreshChecklistState);
    // A previous camera hand-off may have killed the activity mid-draft.
    unawaited(_restoreInterruptedCapture());
  }

  Future<void> _restoreInterruptedCapture() async {
    final draft = await _drafts.take();
    final capturedPath = await PlatformBridge.takePendingCapture();
    if (!mounted) return;
    if (draft != null) {
      _draftId = draft.draftId;
      setState(() {
        _title.text = draft.title;
        _body.text = draft.body;
        _tag.text = draft.tag;
        _notebook.text = draft.notebook;
        _labels = draft.labels;
      });
    }
    if (capturedPath != null) await _importCaptured(capturedPath);
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
    _notebook.dispose();
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

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _appendText(String text) {
    if (text.trim().isEmpty) return;
    final existing = _body.text;
    final separator = existing.trim().isEmpty
        ? ''
        : existing.endsWith('\n')
            ? ''
            : '\n\n';
    final next = '$existing$separator$text';
    _body.value = _body.value.copyWith(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
    setState(() {});
  }

  void _insertLink() {
    final selection = _body.selection;
    final start = selection.start < 0 ? _body.text.length : selection.start;
    final end = selection.end < 0 ? start : selection.end;
    final selected = _body.text.substring(start, end).trim();
    final insertion = selected.isEmpty ? '[[ ]]' : '[[$selected]]';
    final next = _body.text.replaceRange(start, end, insertion);
    final caret = selected.isEmpty ? start + 2 : start + insertion.length;
    _body.value = _body.value.copyWith(
      text: next,
      selection: TextSelection.collapsed(offset: caret),
    );
    setState(() {});
  }

  Future<void> _importCaptured(String path) async {
    try {
      final attachment = await _attachments.importPath(
        widget.existing?.id ?? _draftId,
        path,
      );
      if (!mounted) {
        await _attachments.deleteAll([attachment]);
        return;
      }
      setState(() {
        _files.add(attachment);
        _addedFiles.add(attachment);
      });
    } catch (e) {
      _say('Could not attach the capture: $e');
    }
  }

  Future<void> _capturePhoto() async {
    // The camera is another app: Android may destroy this activity, and with
    // it the Dart form, before control comes back. Back up the draft and the
    // target path first, and hold off lock-on-background while we are away.
    await _drafts.save(NoteDraft(
      title: _title.text,
      body: _body.text,
      tag: _tag.text,
      notebook: _notebook.text,
      labels: List.unmodifiable(_labels),
      draftId: _draftId,
      existingId: widget.existing?.id,
    ));
    widget.appLock?.beginExternalCapture();
    String? path;
    try {
      path = await PlatformBridge.capturePhoto();
    } on CameraCaptureException catch (e) {
      if (mounted) _say(e.message);
      return;
    } catch (e) {
      if (mounted) _say('The camera could not open: $e');
      return;
    } finally {
      widget.appLock?.endExternalCapture();
      // If this form is still alive it owns the state, so the disk backup and
      // native cold-restart copy are no longer needed. If the activity died,
      // this never runs and the new form restores them instead.
      unawaited(_drafts.clear());
      unawaited(PlatformBridge.takePendingCapture());
    }
    if (path == null) {
      if (mounted) _say('No photo was taken.');
      return;
    }
    await _importCaptured(path);
  }

  Future<void> _toggleRecording() async {
    if (_recording) {
      final path = await PlatformBridge.stopAudioRecording();
      if (mounted) setState(() => _recording = false);
      if (path == null) {
        _say('The recording could not be saved.');
        return;
      }
      await _importCaptured(path);
      return;
    }
    final path = await PlatformBridge.startAudioRecording();
    if (path == null) {
      _say('Microphone permission is needed for voice notes.');
      return;
    }
    if (mounted) setState(() => _recording = true);
  }

  Future<void> _transcribe() async {
    final text = await PlatformBridge.transcribe();
    if (text == null || text.trim().isEmpty) {
      _say('Nothing was recognised. Try again in a quieter place.');
      return;
    }
    _appendText(text.trim());
  }

  Future<void> _clipWeb() async {
    final urlController = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Ink0.surface,
        title: const Text('Clip a web page'),
        content: TextField(
          controller: urlController,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration:
              const InputDecoration(hintText: 'https://example.com/article'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, urlController.text),
            child: const Text('Clip'),
          ),
        ],
      ),
    );
    if (url == null || url.trim().isEmpty) return;
    final clip = await WebClipper.clip(url);
    if (clip == null) {
      _say('Could not read that page. Check the address and connection.');
      return;
    }
    final site = clip.siteName == null ? '' : '\n${clip.siteName}';
    _appendText(
      '${clip.title}$site\n${clip.body}\n\nSource: ${clip.url}',
    );
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
    unawaited(_drafts.clear());
    _saved = true;
    final result = widget.existing == null
        ? Note(
            id: _draftId,
            title: title,
            body: body.isEmpty ? null : body,
            tag: tag.isEmpty ? null : tag,
            attachments: List.unmodifiable(_files),
            labels: _labels,
            notebook:
                _notebook.text.trim().isEmpty ? null : _notebook.text.trim(),
          )
        : widget.existing!.copyWith(
            title: title,
            body: body,
            tag: tag,
            clearTag: tag.isEmpty,
            attachments: List.unmodifiable(_files),
            labels: _labels,
            clearNotebook: _notebook.text.trim().isEmpty,
            notebook: _notebook.text.trim(),
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
                _FormatButton(
                    label: 'Link',
                    width: 48,
                    tooltip: 'Link to a note or [[tasks:deadline]]',
                    onTap: _insertLink),
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
            const SizedBox(height: 16),
            Text('Labels',
                style: TextStyle(
                    fontSize: 12,
                    color: Ink0.muted,
                    letterSpacing: 1.1,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            LabelEditor(
              labels: _labels,
              suggestions: widget.existingLabels,
              onChanged: (next) => setState(() => _labels = next),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _notebook,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                hintText: 'Notebook — optional',
                prefixIcon: Icon(Icons.book_outlined, size: 18),
              ),
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                TextButton.icon(
                  key: const Key('note-clip-web'),
                  onPressed: _clipWeb,
                  icon: const Icon(Icons.language, size: 16),
                  label: const Text('Clip URL'),
                ),
                TextButton.icon(
                  onPressed: _capturePhoto,
                  icon: const Icon(Icons.photo_camera_outlined, size: 16),
                  label: const Text('Photo'),
                ),
                TextButton.icon(
                  key: const Key('note-voice'),
                  onPressed: _toggleRecording,
                  icon: Icon(_recording ? Icons.stop_circle : Icons.mic_none,
                      size: 16, color: _recording ? Colors.red : null),
                  label: Text(_recording ? 'Stop recording' : 'Voice memo'),
                ),
                TextButton.icon(
                  key: const Key('note-transcribe'),
                  onPressed: _transcribe,
                  icon: const Icon(Icons.graphic_eq, size: 16),
                  label: const Text('Transcribe'),
                ),
              ],
            ),
            const SizedBox(height: 8),
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
    this.width = 36,
  });

  final String label;
  final String tooltip;
  final VoidCallback onTap;
  final bool bold;
  final bool italic;
  final bool underline;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: width,
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
