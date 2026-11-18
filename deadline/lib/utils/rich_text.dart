import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'markup.dart';

/// Renders note markup into selectable spans. Unknown tags and unmatched
/// closing tags are shown literally, so malformed or legacy text never crashes
/// the reader.
///
/// When [onUrlTap] / [onWikiTap] are supplied, http(s) addresses and `[[links]]`
/// become tappable spans as well. The plain markup-only form stays the default
/// so previews and callers that do not handle taps keep their old behaviour.
TextSpan buildRichSpan(
  String body, {
  required TextStyle base,
  required Color highlight,
  required Color bullet,
  void Function(String url)? onUrlTap,
  void Function(String target)? onWikiTap,
  TextStyle? linkStyle,
}) {
  final children = <InlineSpan>[];
  final links = _LinkStyle(
    style: linkStyle ??
        base.copyWith(
          color: const Color(0xFF7FB0FF),
          decoration: TextDecoration.underline,
          decorationColor: const Color(0xFF7FB0FF).withValues(alpha: 0.6),
        ),
    onUrlTap: onUrlTap,
    onWikiTap: onWikiTap,
  );
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
      children.addAll(_inline(trimmed.substring(2), base, highlight, links));
    } else {
      children.addAll(_inline(line, base, highlight, links));
    }
  }
  return TextSpan(style: base, children: children);
}

class _LinkStyle {
  const _LinkStyle({
    required this.style,
    required this.onUrlTap,
    required this.onWikiTap,
  });

  final TextStyle style;
  final void Function(String url)? onUrlTap;
  final void Function(String target)? onWikiTap;
}

/// Matches a bare http(s) address. Punctuation that commonly follows a link in
/// prose is trimmed below rather than being swallowed by the pattern.
final _urlPattern = RegExp(r'https?://[^\s<>\[\]]+');

const _trailingPunctuation = '.,;:!?)]}\'"';

List<InlineSpan> _inline(
  String text,
  TextStyle base,
  Color highlight,
  _LinkStyle links,
) {
  final spans = <InlineSpan>[];
  final buffer = StringBuffer();
  final stack = <TextStyle>[base];

  void flush() {
    if (buffer.isEmpty) return;
    spans.add(TextSpan(text: buffer.toString(), style: stack.last));
    buffer.clear();
  }

  void addLink(String label, VoidCallback onTap) {
    spans.add(TextSpan(
      text: label,
      style: links.style,
      recognizer: TapGestureRecognizer()..onTap = onTap,
    ));
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
    final match =
        links.onUrlTap == null ? null : _urlPattern.matchAsPrefix(text, i);
    if (match != null) {
      var url = match.group(0)!;
      while (url.isNotEmpty &&
          _trailingPunctuation.contains(url[url.length - 1])) {
        url = url.substring(0, url.length - 1);
      }
      if (url.isNotEmpty) {
        flush();
        addLink(url, () => links.onUrlTap!(url));
        i += url.length;
        continue;
      }
    }

    if (links.onWikiTap != null &&
        text.startsWith('[[', i) &&
        !text.startsWith('[[[', i)) {
      final close = text.indexOf(']]', i + 2);
      if (close != -1) {
        final target = text.substring(i + 2, close).trim();
        if (target.isNotEmpty &&
            !target.contains('[') &&
            !target.contains(']')) {
          flush();
          final display = target.startsWith('tasks:') ||
                  target.toLowerCase().startsWith('tasks:')
              ? target.substring(6)
              : target;
          addLink(display, () => links.onWikiTap!(target));
          i = close + 2;
          continue;
        }
      }
    }

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
