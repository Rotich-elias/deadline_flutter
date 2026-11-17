import 'package:flutter/services.dart';

import 'markup.dart';

/// The marker that a new line should inherit from the caret's current line.
/// Returns null for ordinary text, so the normal newline is inserted.
({String text, int selection})? continueListAtCaret(String text, int caret) {
  if (caret < 0 || caret > text.length) return null;
  final bounds = lineBoundsAt(text, caret);
  final line = text.substring(bounds.start, bounds.end);

  final check = parseChecklistLine(line);
  late final String marker;
  late final int markerLength;
  if (check != null) {
    marker = '${check.prefix}[ ]${check.spacing}';
    markerLength = check.prefix.length + 3 + check.spacing.length;
  } else {
    final bullet = RegExp(r'^(\s*)([-*•]\s+)').firstMatch(line);
    if (bullet == null) return null;
    marker = bullet.group(0)!;
    markerLength = bullet.end;
  }

  // Do not rewrite the line while the caret is still inside its marker.
  if (caret < bounds.start + markerLength) return null;

  // Enter on an empty item closes the list, like a word processor does.
  if (caret == bounds.end && line.substring(markerLength).trim().isEmpty) {
    return (
      text: text.substring(0, bounds.start) + text.substring(bounds.end),
      selection: bounds.start,
    );
  }

  // Splitting mid-line keeps the same kind of marker on the new line too.
  final insertion = '\n$marker';
  return (
    text: text.substring(0, caret) + insertion + text.substring(caret),
    selection: caret + insertion.length,
  );
}

/// Continues "- " bullets and "- [ ]" checkboxes when Enter is pressed in the
/// note body. Works for soft-keyboard newlines as well as hardware Enter,
/// because it operates on the proposed text edit rather than key events.
class ListContinuationFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final oldText = oldValue.text;
    final newText = newValue.text;

    var start = 0;
    while (start < oldText.length &&
        start < newText.length &&
        oldText[start] == newText[start]) {
      start++;
    }
    var oldEnd = oldText.length;
    var newEnd = newText.length;
    while (oldEnd > start &&
        newEnd > start &&
        oldText[oldEnd - 1] == newText[newEnd - 1]) {
      oldEnd--;
      newEnd--;
    }
    final inserted = newText.substring(start, newEnd);
    // Only a plain Enter is rewritten; pasting multi-line text must keep all
    // of its content instead of being mistaken for a list continuation.
    if (inserted != '\n') return newValue;

    final result = continueListAtCaret(oldText, start);
    if (result == null) return newValue;
    return newValue.copyWith(
      text: result.text,
      selection: TextSelection.collapsed(offset: result.selection),
    );
  }
}
