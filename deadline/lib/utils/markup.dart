/// Lightweight inline markup shared by the note editor and reader.
///
/// Notes keep a single [String] body, so formatting is stored as small tags:
/// `<b>`, `<i>`, `<u>` and `<m>` (highlight). A line starting with "- " is a
/// bullet. Everything else is literal text, which means every note written
/// before formatting existed still displays exactly as before.
const inlineTags = {'b', 'i', 'u', 'm'};

final _tagPattern = RegExp(r'</?[bium]>');

/// Text as the user reads it: markup removed and "- " lines shown as bullets.
/// Used for card previews, search and accessibility.
String stripMarkup(String? body) {
  if (body == null || body.isEmpty) return '';
  return body.split('\n').map((line) {
    final plain = line.replaceAllMapped(_tagPattern, (_) => '');
    final trimmed = plain.trimLeft();
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
  var lineStart = 0;
  for (var i = caret - 1; i >= 0; i--) {
    if (text[i] == '\n') {
      lineStart = i + 1;
      break;
    }
  }
  var lineEnd = caret;
  while (lineEnd < text.length && text[lineEnd] != '\n') {
    lineEnd++;
  }
  final line = text.substring(lineStart, lineEnd);

  if (line.startsWith('- ')) {
    final updated =
        '${text.substring(0, lineStart)}${line.substring(2)}${text.substring(lineEnd)}';
    final shifted = caret - 2 < lineStart ? lineStart : caret - 2;
    return (text: updated, start: shifted, end: shifted);
  }

  final updated =
      '${text.substring(0, lineStart)}- ${text.substring(lineStart)}';
  return (
    text: updated,
    start: caret + 2,
    end: caret + 2,
  );
}
