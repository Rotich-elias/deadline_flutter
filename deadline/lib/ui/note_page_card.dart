import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/note.dart';
import '../theme.dart';
import 'paper_page.dart';

/// A notebook-style thumbnail used by the Notes "Pages" grid.
class NotePageCard extends StatelessWidget {
  const NotePageCard({
    super.key,
    required this.note,
    required this.onEdit,
    required this.pageNumber,
  });

  final Note note;
  final VoidCallback onEdit;
  final int pageNumber;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(11),
        child: PaperPage(
          pageNumber: pageNumber,
          pinned: note.pinned,
          minHeight: 236,
          padding: const EdgeInsets.fromLTRB(16, 20, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (note.locked) ...[
                const Icon(Icons.lock_outline, size: 20),
                const SizedBox(height: 10),
                const Text(
                  'Locked note',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text('Tap to unlock',
                    style: TextStyle(fontSize: 11.5, color: Ink0.muted)),
              ] else ...[
                if ((note.tag ?? '').trim().isNotEmpty)
                  Text(
                    note.tag!.trim().toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                      color: Ink0.muted,
                    ),
                  ),
                if ((note.tag ?? '').trim().isNotEmpty)
                  const SizedBox(height: 6),
                Text(
                  note.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.25,
                    fontWeight: FontWeight.w700,
                    color: Ink0.text,
                  ),
                ),
                const SizedBox(height: 8),
                Divider(height: 1, color: Ink0.line),
                const SizedBox(height: 8),
                if (note.plainBody.trim().isNotEmpty)
                  Text(
                    note.plainBody.trim(),
                    maxLines: 6,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.45,
                      color: Ink0.muted,
                    ),
                  ),
              ],
              const Spacer(),
              Row(
                children: [
                  Flexible(
                    child: Text(
                      DateFormat('d MMM').format(note.updatedAt.toLocal()),
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 10.5, color: Ink0.muted),
                    ),
                  ),
                  if (note.hasAttachments) ...[
                    const SizedBox(width: 4),
                    Icon(Icons.attach_file, size: 12, color: Ink0.muted),
                  ],
                  if (note.pinned) ...[
                    const SizedBox(width: 4),
                    const Icon(Icons.push_pin,
                        size: 12, color: Color(0xFFE4C441)),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
