import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/note.dart';
import '../theme.dart';
import 'paper_page.dart';

class NoteCard extends StatelessWidget {
  const NoteCard({
    super.key,
    required this.note,
    required this.onEdit,
    this.pageNumber,
  });

  final Note note;
  final VoidCallback onEdit;

  /// Shown as "PAGE n" in the corner when the list supplies an index.
  final int? pageNumber;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onEdit,
          borderRadius: BorderRadius.circular(11),
          child: PaperPage(
            pageNumber: pageNumber,
            pinned: note.pinned,
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (note.locked) ...[
                  Row(
                    children: [
                      Icon(Icons.lock_outline, size: 16, color: Ink0.muted),
                      const SizedBox(width: 7),
                      Text(
                        'Locked note',
                        style: TextStyle(
                          fontSize: 16,
                          height: 1.25,
                          fontWeight: FontWeight.w600,
                          color: Ink0.text,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Tap to unlock',
                    style: TextStyle(
                        fontSize: 13, color: Ink0.muted, height: 1.35),
                  ),
                ] else ...[
                  if ((note.tag ?? '').trim().isNotEmpty) ...[
                    Text(
                      note.tag!.trim().toUpperCase(),
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                        color: Ink0.muted,
                      ),
                    ),
                    const SizedBox(height: 5),
                  ],
                  Text(
                    note.title,
                    style: TextStyle(
                      fontSize: 16,
                      height: 1.25,
                      fontWeight: FontWeight.w600,
                      color: Ink0.text,
                    ),
                  ),
                  if (note.plainBody.trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      note.plainBody.trim(),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 13.5, color: Ink0.muted, height: 1.35),
                    ),
                  ],
                ],
                if (note.hasAttachments) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.attach_file, size: 13, color: Ink0.muted),
                      const SizedBox(width: 5),
                      Text(
                        '${note.attachments.length} '
                        '${note.attachments.length == 1 ? 'file' : 'files'}',
                        style: TextStyle(fontSize: 12, color: Ink0.muted),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 10),
                Row(
                  children: [
                    Text(
                      DateFormat('d MMM, h:mm a')
                          .format(note.updatedAt.toLocal()),
                      style: TextStyle(fontSize: 12, color: Ink0.muted),
                    ),
                    if (note.pinned) ...[
                      const SizedBox(width: 8),
                      const Icon(Icons.push_pin,
                          size: 13, color: Color(0xFFE4C441)),
                    ],
                    if (note.dirty) ...[
                      const SizedBox(width: 8),
                      Icon(Icons.cloud_off, size: 13, color: Ink0.muted),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
