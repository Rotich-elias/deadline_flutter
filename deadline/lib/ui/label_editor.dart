import 'package:flutter/material.dart';

import '../theme.dart';

/// Compact multi-label editor shared by the task and note forms. Labels are
/// ordinary synced strings; this widget only builds the list, never stores it.
class LabelEditor extends StatefulWidget {
  const LabelEditor({
    super.key,
    required this.labels,
    required this.onChanged,
    this.hint = 'Add a label',
    this.suggestions = const [],
  });

  final List<String> labels;
  final ValueChanged<List<String>> onChanged;
  final String hint;
  final List<String> suggestions;

  @override
  State<LabelEditor> createState() => _LabelEditorState();
}

class _LabelEditorState extends State<LabelEditor> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _add(String value) {
    final label = value.trim().replaceFirst(RegExp(r'^#'), '');
    if (label.isEmpty || widget.labels.contains(label)) {
      _controller.clear();
      return;
    }
    widget.onChanged([...widget.labels, label]);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final unused = widget.suggestions
        .where((s) => !widget.labels.contains(s))
        .take(5)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            for (final label in widget.labels)
              InputChip(
                key: Key('label-chip-$label'),
                label: Text(label),
                visualDensity: VisualDensity.compact,
                onDeleted: () => widget
                    .onChanged(widget.labels.where((l) => l != label).toList()),
              ),
          ],
        ),
        if (widget.labels.isNotEmpty) const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: TextField(
                key: const Key('label-input'),
                controller: _controller,
                decoration: InputDecoration(hintText: widget.hint),
                onSubmitted: _add,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.add, size: 18),
              tooltip: 'Add label',
              onPressed: () => _add(_controller.text),
            ),
          ],
        ),
        if (unused.isNotEmpty) ...[
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            children: [
              for (final suggestion in unused)
                ActionChip(
                  key: Key('label-suggestion-$suggestion'),
                  label: Text(suggestion,
                      style: TextStyle(fontSize: 11, color: Ink0.muted)),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _add(suggestion),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
