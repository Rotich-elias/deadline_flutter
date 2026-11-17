/// Lightweight inline markup shared by the note editor and reader.
///
/// Notes keep a single [String] body, so formatting is stored as small tags:
/// `<b>`, `<i>`, `<u>` and `<m>` (highlight). A line starting with "- " is a
/// bullet, and a line starting with "- [ ] " or "- [x] " is a checklist item.
/// Everything else is literal text, which means every note written before
/// formatting existed still displays exactly as before.
const inlineTags = {'b', 'i', 'u', 'm'};

final _tagPattern = RegExp(r'</?[bium]>');

/// A checklist marker, with an optional leading bullet. `[  ]` and `[v]` are
/// deliberately not accepted: old handwritten notes use those and must stay
/// literal.
final checklistPrefix = RegExp(r'^(\s*(?:[-*•]\s+)?)\[([ xX])\](\s*)');

({String prefix, bool checked, String spacing, String text})?
    parseChecklistLine(String line) {
  final match = checklistPrefix.firstMatch(line);
  if (match == null) return null;
  return (
    prefix: match.group(1)!,
    checked: match.group(2)!.toLowerCase() == 'x',
    spacing: match.group(3)!,
    text: line.substring(match.end),
  );
}

bool isChecklistLine(String line) => parseChecklistLine(line) != null;

String toggleChecklistLine(String line) {
  final parsed = parseChecklistLine(line);
  if (parsed == null) return line;
  return '${parsed.prefix}[${parsed.checked ? ' ' : 'x'}]'
      '${parsed.spacing}${parsed.text}';
}

/// Ticks one checklist line in a whole note body, leaving all other lines and
/// their formatting exactly as they were.
String toggleChecklistLineAt(String body, int lineIndex) {
  final lines = body.split('\n');
  if (lineIndex < 0 || lineIndex >= lines.length) return body;
  if (!isChecklistLine(lines[lineIndex])) return body;
  lines[lineIndex] = toggleChecklistLine(lines[lineIndex]);
  return lines.join('\n');
}

/// The start/end offsets of the line containing [caret].
({int start, int end}) lineBoundsAt(String text, int caret) {
  var start = 0;
  for (var i = caret - 1; i >= 0; i--) {
    if (text[i] == '\n') {
      start = i + 1;
      break;
    }
  }
  var end = caret;
  while (end < text.length && text[end] != '\n') {
    end++;
  }
  return (start: start, end: end);
}

/// Turns the caret's line into a checklist item, or ticks it if it already is
/// one. An existing "- " bullet is reused instead of being doubled.
({String text, int start, int end}) toggleChecklistAtCaret(
    String text, int caret) {
  final bounds = lineBoundsAt(text, caret);
  final line = text.substring(bounds.start, bounds.end);
  if (isChecklistLine(line)) {
    return (
      text: text.substring(0, bounds.start) +
          toggleChecklistLine(line) +
          text.substring(bounds.end),
      start: caret,
      end: caret,
    );
  }

  final bullet = RegExp(r'^(\s*)([-*•]\s+)').firstMatch(line);
  late final String updated;
  late final int insertionOffset;
  if (bullet != null) {
    insertionOffset = bounds.start + bullet.end;
    updated =
        '${line.substring(0, bullet.end)}[ ] ${line.substring(bullet.end)}';
  } else {
    insertionOffset = bounds.start;
    updated = '- [ ] $line';
  }
  final shifted = updated.length - line.length;
  final newCaret = caret >= insertionOffset ? caret + shifted : caret;
  return (
    text:
        text.substring(0, bounds.start) + updated + text.substring(bounds.end),
    start: newCaret,
    end: newCaret,
  );
}

/// Text as the user reads it: markup removed, "- " lines shown as bullets and
/// checklist lines shown as tick boxes. Used for card previews, search and
/// accessibility.
String stripMarkup(String? body) {
  if (body == null || body.isEmpty) return '';
  return body.split('\n').map((line) {
    final plain = line.replaceAllMapped(_tagPattern, (_) => '');
    final trimmed = plain.trimLeft();
    final check = parseChecklistLine(trimmed);
    if (check != null) {
      return '${check.checked ? '☑' : '☐'} ${check.text}'
          .replaceAllMapped(_tagPattern, (_) => '')
          .trimRight();
    }
    return trimmed.startsWith('- ') ? '• ${trimmed.substring(2)}' : plain;
  }).join('\n');
}

/// Wrap [start, end) in a tag pair, or remove the pair if it is already there.
/// With a collapsed selection an empty pair is inserted and the cursor is left
/// inside it, ready to type.
({String text, int start, int end}) toggleTag(
  String text,
  int start,
  int end,
  String tag,
) {
  final open = '<$tag>';
  final close = '</$tag>';

  if (start != end) {
    final before = text.substring(0, start);
    final selected = text.substring(start, end);
    final after = text.substring(end);
    if (before.endsWith(open) && after.startsWith(close)) {
      return (
        text: before.substring(0, before.length - open.length) +
            selected +
            after.substring(close.length),
        start: start - open.length,
        end: end - open.length,
      );
    }
    return (
      text: '$before$open$selected$close$after',
      start: start + open.length,
      end: end + open.length,
    );
  }

  final next = '${text.substring(0, start)}$open$close${text.substring(start)}';
  return (text: next, start: start + open.length, end: start + open.length);
}

/// Add or remove a "- " bullet on the line containing [caret].
({String text, int start, int end}) toggleBullet(String text, int caret) {
  final bounds = lineBoundsAt(text, caret);
  final line = text.substring(bounds.start, bounds.end);

  if (line.startsWith('- ')) {
    final updated = text.substring(0, bounds.start) +
        line.substring(2) +
        text.substring(bounds.end);
    final shifted = caret - 2 < bounds.start ? bounds.start : caret - 2;
    return (text: updated, start: shifted, end: shifted);
  }

  final updated = '${text.substring(0, bounds.start)}- '
      '${text.substring(bounds.start, bounds.end)}'
      '${text.substring(bounds.end)}';
  return (
    text: updated,
    start: caret + 2,
    end: caret + 2,
  );
}
