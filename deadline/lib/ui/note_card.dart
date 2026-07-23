import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/note.dart';
import '../theme.dart';

class NoteCard extends StatelessWidget {
  const NoteCard({super.key, required this.note, required this.onEdit});

  final Note note;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      decoration: BoxDecoration(
        color: Ink0.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Ink0.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onEdit,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if ((note.tag ?? '').trim().isNotEmpty) ...[
                  Text(
                    note.tag!.trim().toUpperCase(),
                    style: const TextStyle(
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
                  style: const TextStyle(
                    fontSize: 16,
                    height: 1.25,
                    fontWeight: FontWeight.w600,
                    color: Ink0.text,
                  ),
                ),
                if ((note.body ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    note.body!.trim(),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13.5, color: Ink0.muted, height: 1.35),
                  ),
                ],
                const SizedBox(height: 10),
                Row(
                  children: [
                    Text(
                      DateFormat('d MMM, h:mm a').format(note.updatedAt.toLocal()),
                      style: const TextStyle(fontSize: 12, color: Ink0.muted),
                    ),
                    if (note.dirty) ...[
                      const SizedBox(width: 8),
                      const Icon(Icons.cloud_off, size: 13, color: Ink0.muted),
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
