import 'package:flutter/material.dart';

import '../theme.dart';

/// Horizontal "All + one chip per tag" row. Shared between the deadlines and
/// notes tabs — each just wires it to its own store's tags/tagFilter.
class TagFilterRow extends StatelessWidget {
  const TagFilterRow({
    super.key,
    required this.tags,
    required this.selected,
    required this.onSelect,
  });

  final List<String> tags;
  final String? selected;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          TagChip(
            label: 'All',
            selected: selected == null,
            onTap: () => onSelect(null),
          ),
          for (final tag in tags) ...[
            const SizedBox(width: 8),
            TagChip(
              label: tag,
              selected: selected == tag,
              onTap: () => onSelect(tag),
            ),
          ],
        ],
      ),
    );
  }
}

class TagChip extends StatelessWidget {
  const TagChip(
      {super.key,
      required this.label,
      required this.selected,
      required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 12.5)),
      selected: selected,
      onSelected: (_) => onTap(),
      backgroundColor: Ink0.surface,
      selectedColor: Ink0.line,
      side: BorderSide(color: selected ? Colors.transparent : Ink0.line),
      labelStyle: TextStyle(color: Ink0.text),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    );
  }
}
