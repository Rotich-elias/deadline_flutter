import 'package:flutter/material.dart';

import '../theme.dart';
import '../utils/templates.dart';

/// Shows the built-in note structures. Returns the chosen template, or null
/// when the sheet was dismissed without a choice.
Future<NoteTemplate?> showTemplatePicker(BuildContext context) {
  return showModalBottomSheet<NoteTemplate>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Ink0.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const _TemplatePicker(),
  );
}

IconData _icon(String id) => switch (id) {
      'journal' => Icons.edit_note_outlined,
      'meeting' => Icons.groups_outlined,
      'project' => Icons.account_tree_outlined,
      'shopping' => Icons.shopping_bag_outlined,
      _ => Icons.notes_outlined,
    };

class _TemplatePicker extends StatelessWidget {
  const _TemplatePicker();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Start from a template',
                style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    color: Ink0.text)),
            const SizedBox(height: 5),
            Text(
                'Opens an editable draft — nothing is saved until you tap Save.',
                style: TextStyle(fontSize: 12.5, color: Ink0.muted)),
            const SizedBox(height: 14),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: builtInNoteTemplates.length,
                separatorBuilder: (_, __) => const SizedBox(height: 4),
                itemBuilder: (context, index) {
                  final template = builtInNoteTemplates[index];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Ink0.surfaceHi,
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child:
                          Icon(_icon(template.id), size: 20, color: Ink0.text),
                    ),
                    title: Text(template.title.replaceAll('{{date}}', 'today'),
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Ink0.text)),
                    subtitle: Text(template.description,
                        style: TextStyle(fontSize: 12, color: Ink0.muted)),
                    trailing:
                        Icon(Icons.chevron_right, size: 18, color: Ink0.muted),
                    onTap: () => Navigator.of(context).pop(template),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
