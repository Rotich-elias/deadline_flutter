// On-device "AI-lite": turns pasted text into the fields already understood
// by the task form. No network, no API key and no new dependency — just a few
// conservative patterns for dates, times, tags and checklist-like lines.
//
// The result is always a draft. The user still confirms every field before
// anything is saved, so a bad guess can never silently corrupt a deadline.

class SmartDraft {
  const SmartDraft({
    required this.title,
    this.notes,
    this.tag,
    this.due,
    this.checklist = const [],
  });

  final String title;
  final String? notes;
  final String? tag;
  final DateTime? due;
  final List<String> checklist;

  bool get isEmpty =>
      title.isEmpty &&
      (notes == null || notes!.isEmpty) &&
      tag == null &&
      due == null &&
      checklist.isEmpty;
}

class _When {
  const _When(this.date, this.cleaned);

  final DateTime date;
  final String cleaned;
}

final _hashTag = RegExp(r'#([\w-]+)');
final _tagLine = RegExp(r'^(?:tag|label)\s*:\s*(.+)$', caseSensitive: false);

// Longest/most specific checklist markers first: "- [ ] task" must not be
// mistaken for a plain "- " line.
final _checklistLine = RegExp(
    r'^\s*(?:[-*]\s+\[[ xX]\]\s+|\[[ xX]\]\s+|[-*•]\s+|\d+[.)]\s+)(.+)$');

final _isoDate = RegExp(r'\b(\d{4})-(\d{2})-(\d{2})\b');
final _slashDate = RegExp(r'\b(\d{1,2})/(\d{1,2})(?:/(\d{2,4}))?\b');
final _namedDayMonth = RegExp(
    r'\b(\d{1,2})\s+(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.?(?:\s+(\d{4}))?\b',
    caseSensitive: false);
final _monthDay = RegExp(
    r'\b(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.?\s+(\d{1,2})(?:,?\s+(\d{4}))?\b',
    caseSensitive: false);
final _relative = RegExp(
    r'\b(today|tomorrow|tonight|next\s+week|in\s+\d+\s+days?)\b',
    caseSensitive: false);
final _ampmTime = RegExp(
    r'\b(?:at\s+|by\s+)?(\d{1,2})(?::(\d{2}))?\s*(am|pm)\b',
    caseSensitive: false);
final _time24 = RegExp(r'\b(\d{1,2}):(\d{2})\b');
final _leftoverConnective =
    RegExp(r'\b(?:due|deadline|by|at|on|for)\s*:?\s*$', caseSensitive: false);

const _months = <String, int>{
  'jan': 1,
  'feb': 2,
  'mar': 3,
  'apr': 4,
  'may': 5,
  'jun': 6,
  'jul': 7,
  'aug': 8,
  'sep': 9,
  'oct': 10,
  'nov': 11,
  'dec': 12,
};

int? _monthNumber(String value) => _months[value.toLowerCase().substring(0, 3)];

int _expandYear(int value, int reference) => value < 100 ? 2000 + value : value;

DateTime? _safeDate(int year, int month, int day) =>
    month >= 1 && month <= 12 && day >= 1 && day <= 31
        ? DateTime(year, month, day)
        : null;

String _remove(String input, RegExpMatch match) =>
    input.replaceRange(match.start, match.end, ' ');

String _tidy(String input) => input.replaceAll(RegExp(r'\s{2,}'), ' ').trim();

/// Pulls the first recognisable date/time phrase out of [line] and returns the
/// line with that phrase removed. A bare time (e.g. "call at 5pm") is assumed
/// to mean today, or tomorrow once that time has already passed.
_When? _findWhen(String line, DateTime now) {
  var work = line;
  DateTime? date;
  var hasExplicitDate = false;
  var defaultHour = 17; // end-of-day unless the phrase says otherwise

  var match = _isoDate.firstMatch(work);
  if (match != null) {
    date = _safeDate(int.parse(match.group(1)!), int.parse(match.group(2)!),
        int.parse(match.group(3)!));
    if (date != null) {
      hasExplicitDate = true;
      work = _remove(work, match);
    }
  }

  match ??= _slashDate.firstMatch(work);
  if (match != null && date == null) {
    date = _safeDate(
      int.parse(match.group(3) == null
          ? now.year.toString()
          : _expandYear(int.parse(match.group(3)!), now.year).toString()),
      int.parse(match.group(2)!),
      int.parse(match.group(1)!),
    );
    if (date != null) {
      hasExplicitDate = true;
      work = _remove(work, match);
    }
  }

  match = _namedDayMonth.firstMatch(work);
  if (match != null && date == null) {
    final month = _monthNumber(match.group(2)!);
    if (month != null) {
      date = _safeDate(
        match.group(3) == null ? now.year : int.parse(match.group(3)!),
        month,
        int.parse(match.group(1)!),
      );
      if (date != null) {
        hasExplicitDate = true;
        work = _remove(work, match);
      }
    }
  }

  match = _monthDay.firstMatch(work);
  if (match != null && date == null) {
    final month = _monthNumber(match.group(1)!);
    if (month != null) {
      date = _safeDate(
        match.group(3) == null ? now.year : int.parse(match.group(3)!),
        month,
        int.parse(match.group(2)!),
      );
      if (date != null) {
        hasExplicitDate = true;
        work = _remove(work, match);
      }
    }
  }

  match = _relative.firstMatch(work);
  if (match != null && date == null) {
    final phrase =
        match.group(0)!.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    if (phrase == 'today') {
      date = DateTime(now.year, now.month, now.day);
      defaultHour = 17;
    } else if (phrase == 'tomorrow') {
      date = DateTime(now.year, now.month, now.day + 1);
      defaultHour = 9;
    } else if (phrase == 'tonight') {
      date = DateTime(now.year, now.month, now.day);
      defaultHour = 21;
    } else if (phrase == 'next week') {
      date = DateTime(now.year, now.month, now.day + 7);
      defaultHour = 17;
    } else {
      final days = int.parse(RegExp(r'\d+').firstMatch(phrase)!.group(0)!);
      date = DateTime(now.year, now.month, now.day + days);
      defaultHour = 17;
    }
    work = _remove(work, match);
  }

  var hour = defaultHour;
  var minute = 0;
  var foundTime = false;

  match = _ampmTime.firstMatch(work);
  if (match != null) {
    hour = int.parse(match.group(1)!);
    minute = int.parse(match.group(2) ?? '0');
    final suffix = match.group(3)!.toLowerCase();
    if (suffix == 'pm' && hour < 12) hour += 12;
    if (suffix == 'am' && hour == 12) hour = 0;
    foundTime = true;
    work = _remove(work, match);
  } else {
    match = _time24.firstMatch(work);
    if (match != null) {
      hour = int.parse(match.group(1)!);
      minute = int.parse(match.group(2)!);
      foundTime = true;
      work = _remove(work, match);
    }
  }

  if (date == null && !foundTime) return null;

  date ??= DateTime(now.year, now.month, now.day);
  var result = DateTime(date.year, date.month, date.day, hour, minute);
  if (!hasExplicitDate && result.isBefore(now)) {
    result = result.add(const Duration(days: 1));
  }

  final cleaned = _tidy(work.replaceFirst(_leftoverConnective, ''));
  return _When(result, cleaned);
}

/// Parses pasted text into an editable draft. Lines that look like checklist
/// steps become steps; the first ordinary line becomes the title and the rest
/// become notes. Everything not recognised stays as plain text.
SmartDraft extractSmartDraft(String text, {DateTime? now}) {
  final at = now ?? DateTime.now();
  final lines = text
      .replaceAll('\r\n', '\n')
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();
  if (lines.isEmpty) return const SmartDraft(title: '');

  String? tag;
  DateTime? due;
  final checklist = <String>[];
  final remaining = <String>[];

  for (final line in lines) {
    var work = line;

    final tagLine = _tagLine.firstMatch(work);
    if (tagLine != null) {
      tag ??= tagLine.group(1)!.trim();
      continue;
    }

    final hash = _hashTag.firstMatch(work);
    if (hash != null) {
      tag ??= hash.group(1)!;
      work = _remove(work, hash);
    }

    final step = _checklistLine.firstMatch(work);
    if (step != null) {
      checklist.add(step.group(1)!.trim());
      continue;
    }

    final when = _findWhen(work, at);
    if (when != null) {
      due ??= when.date;
      work = when.cleaned;
    }

    work = _tidy(work);
    if (work.isNotEmpty) remaining.add(work);
  }

  final title = remaining.isEmpty
      ? (checklist.isEmpty ? '' : checklist.first)
      : remaining.first;
  final notes = remaining.skip(1).join('\n');

  return SmartDraft(
    title: title,
    notes: notes.isEmpty ? null : notes,
    tag: tag,
    due: due,
    checklist: List.unmodifiable(checklist),
  );
}
