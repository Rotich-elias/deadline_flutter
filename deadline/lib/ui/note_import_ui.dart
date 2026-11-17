import 'package:flutter/material.dart';

import '../data/notes_store.dart';
import '../services/note_import.dart';
import '../theme.dart';

/// Walks the user through exporting from Samsung Notes, since its database is
/// private to that app and cannot be read directly.
Future<void> showSamsungImportHelp(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: Ink0.surface,
      title: const Text('Import from Samsung Notes'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Samsung Notes keeps its notes private, so they have to be '
            'shared across. It takes a few taps:',
            style: TextStyle(fontSize: 13.5, color: Ink0.muted, height: 1.45),
          ),
          const SizedBox(height: 14),
          const _Step(
              number: '1', text: 'Open Samsung Notes and long-press one note.'),
          const _Step(
              number: '2', text: 'Tap All (or pick the notes you want).'),
          const _Step(number: '3', text: 'Tap Share, then Text file.'),
          const _Step(number: '4', text: 'Choose Deadlines&Notes.'),
          const SizedBox(height: 14),
          Text(
            'They appear on the Notes tab. Locked notes must be unlocked '
            'first, or copied and pasted with "Paste a note".',
            style: TextStyle(fontSize: 12, color: Ink0.muted, height: 1.4),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Got it'),
        ),
      ],
    ),
  );
}

class _Step extends StatelessWidget {
  const _Step({required this.number, required this.text});

  final String number;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20,
            height: 20,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Ink0.surfaceHi,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              number,
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700, color: Ink0.muted),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 13.5, color: Ink0.text, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

/// Fallback for notes that cannot be shared (locked notes, or a note copied
/// from anywhere else). Imports one note from the clipboard or typed text.
Future<bool> showPasteNoteDialog(BuildContext context, NotesStore store) async {
  final text = await showDialog<String>(
    context: context,
    builder: (_) => const _PasteNoteDialog(),
  );
  if (text == null || text.trim().isEmpty) return false;

  final outcome = await NoteImport.importAll(store, [SharedNote(text)]);
  if (!context.mounted) return outcome.imported > 0;

  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(outcome.imported > 0
          ? 'Note imported'
          : 'That note is already in your app'),
    ));
  return outcome.imported > 0;
}

class _PasteNoteDialog extends StatefulWidget {
  const _PasteNoteDialog();

  @override
  State<_PasteNoteDialog> createState() => _PasteNoteDialogState();
}

class _PasteNoteDialogState extends State<_PasteNoteDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Ink0.surface,
      title: const Text('Paste a note'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        minLines: 5,
        maxLines: 9,
        keyboardType: TextInputType.multiline,
        style: TextStyle(color: Ink0.text, fontSize: 14),
        decoration: InputDecoration(
          hintText:
              'The first line becomes the title.\nPaste the rest below it.',
          hintStyle: TextStyle(color: Ink0.muted, fontSize: 13),
          filled: true,
          fillColor: Ink0.surfaceHi,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('Import'),
        ),
      ],
    );
  }
}
