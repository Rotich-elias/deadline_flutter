import 'package:flutter/material.dart';

import 'markup.dart';

/// Renders note markup into selectable spans. Unknown tags and unmatched
/// closing tags are shown literally, so malformed or legacy text never crashes
/// the reader.
TextSpan buildRichSpan(
  String body, {
  required TextStyle base,
  required Color highlight,
  required Color bullet,
}) {
  final children = <InlineSpan>[];
  final lines = body.split('\n');
  for (var lineIndex = 0; lineIndex < lines.length; lineIndex++) {
    if (lineIndex > 0) children.add(const TextSpan(text: '\n'));
    final line = lines[lineIndex];
    final trimmed = line.trimLeft();
    if (trimmed.startsWith('- ')) {
      children.add(TextSpan(
        text: '•  ',
        style: base.copyWith(color: bullet, fontWeight: FontWeight.w700),
      ));
      children.addAll(_inline(trimmed.substring(2), base, highlight));
    } else {
      children.addAll(_inline(line, base, highlight));
    }
  }
  return TextSpan(style: base, children: children);
}

List<InlineSpan> _inline(String text, TextStyle base, Color highlight) {
  final spans = <InlineSpan>[];
  final buffer = StringBuffer();
  final stack = <TextStyle>[base];

  void flush() {
    if (buffer.isEmpty) return;
    spans.add(TextSpan(text: buffer.toString(), style: stack.last));
    buffer.clear();
  }

  TextStyle styleFor(String tag, TextStyle previous) => switch (tag) {
        'b' => previous.copyWith(fontWeight: FontWeight.w700),
        'i' => previous.copyWith(fontStyle: FontStyle.italic),
        'u' => previous.copyWith(decoration: TextDecoration.underline),
        'm' => previous.copyWith(
            backgroundColor: highlight.withValues(alpha: 0.4),
            color: previous.color),
        _ => previous,
      };

  var i = 0;
  while (i < text.length) {
    if (text[i] == '<') {
      final end = text.indexOf('>', i + 1);
      if (end != -1) {
        final tag = text.substring(i + 1, end);
        if (inlineTags.contains(tag)) {
          flush();
          stack.add(styleFor(tag, stack.last));
          i = end + 1;
          continue;
        }
        if (tag.startsWith('/') &&
            inlineTags.contains(tag.substring(1)) &&
            stack.length > 1) {
          flush();
          stack.removeLast();
          i = end + 1;
          continue;
        }
      }
    }
    buffer.write(text[i]);
    i++;
  }
  flush();
  return spans;
}
