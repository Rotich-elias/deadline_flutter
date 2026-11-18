// Natural-language scheduling helpers.
//
// A task stores its due date in UTC, but people type schedules in local wall
// clock time ("pay rent tomorrow 5pm"). This parser extracts that phrase,
// strips it from the title and returns a local DateTime the form can edit.
// If no date or time is recognised it returns null, so callers can leave an
// existing due date untouched.

class ScheduleParse {
  const ScheduleParse({
    required this.title,
    this.dueLocal,
    this.tag,
    this.checklist = const [],
  });

  final String title;
  final DateTime? dueLocal;
  final String? tag;
  final List<String> checklist;
}

final _hashTag = RegExp(r'#([\w-]+)');
final _tagLine = RegExp(r'^(?:tag|label)\s*:\s*(.+)$', caseSensitive: false);

// Most specific markers first so "- [ ] step" is not read as "- step".
final _checklistLine = RegExp(
    r'^\s*(?:[-*]\s+\[[ xX]\]\s+|\[[ xX]\]\s+|[-*•]\s+|\d+[.)]\s+)(.+)$');

final _isoDate = RegExp(r'\b(\d{4})-(\d{2})-(\d{2})\b');
final _slashDate = RegExp(r'\b(\d{1,2})/(\d{1,2})(?:/(\d{2,4}))?\b');
final _namedDayMonth = RegExp(
    r'\b(\d{1,2})\s+(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.?(?:\s+(\d{4}))?(?!\w)',
    caseSensitive: false);
final _monthDay = RegExp(
    r'\b(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.?\s+(\d{1,2})(?:\s+(\d{4}))?(?!\w)',
    caseSensitive: false);
final _relative = RegExp(
    r'\b(today|tomorrow|tonight|next\s+week|in\s+\d+\s+days?)\b',
    caseSensitive: false);
final _weekday = RegExp(
    r'\b(?:(next|this)\s+)?(monday|tuesday|wednesday|thursday|friday|saturday|sunday|mon|tue|tues|wed|weds|thu|thurs|fri|sat|sun)\b',
    caseSensitive: false);
final _ampmTime = RegExp(
    r'\b(?:at\s+|by\s+)?(\d{1,2})(?::(\d{2}))?\s*(am|pm)\b',
    caseSensitive: false);
final _time24 = RegExp(r'\b(\d{1,2}):(\d{2})\b');
final _specialTime =
    RegExp(r'\b(?:at\s+|by\s+)?(noon|midnight)\b', caseSensitive: false);
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

const _weekdays = <String, int>{
  'monday': 1,
  'mon': 1,
  'tuesday': 2,
  'tue': 2,
  'tues': 2,
  'wednesday': 3,
  'wed': 3,
  'weds': 3,
  'thursday': 4,
  'thu': 4,
  'thurs': 4,
  'friday': 5,
  'fri': 5,
  'saturday': 6,
  'sat': 6,
  'sunday': 7,
  'sun': 7,
};

int? _monthNumber(String value) => _months[value.toLowerCase().substring(0, 3)];

int? _weekdayNumber(String value) =>
    _weekdays[value.toLowerCase().replaceAll(RegExp(r'\s+'), '')];

int _expandYear(int value, int reference) => value < 100 ? 2000 + value : value;

// DateTime silently rolls 30 February into March, so check the round trip.
DateTime? _safeDate(int year, int month, int day) {
  if (year < 1 ||
      year > 9999 ||
      month < 1 ||
      month > 12 ||
      day < 1 ||
      day > 31) {
    return null;
  }
  try {
    final date = DateTime(year, month, day);
    return date.year == year && date.month == month && date.day == day
        ? date
        : null;
  } catch (_) {
    return null;
  }
}

String _remove(String input, RegExpMatch match) =>
    input.replaceRange(match.start, match.end, ' ');

String _tidy(String input) => input.replaceAll(RegExp(r'\s+'), ' ').trim();

class NaturalSchedule {
  /// Extracts a due date and formatting hints from [input].
  ///
  /// Returns null when neither a date nor a time could be recognised; the
  /// caller should then keep whatever due date it already had. Dates are
  /// returned as local wall-clock values, matching the form's dueLocal field.
  static ScheduleParse? parse(String input, {DateTime? now}) {
    try {
      return _parse(input, now ?? DateTime.now());
    } catch (_) {
      // A paste is only ever a draft: malformed text must never crash the UI.
      return null;
    }
  }

  static ScheduleParse? _parse(String input, DateTime at) {
    String? tag;
    final checklist = <String>[];
    final remaining = <String>[];

    for (final raw in input.replaceAll('\r\n', '\n').split('\n')) {
      var line = raw.trim();
      if (line.isEmpty) continue;

      final tagLine = _tagLine.firstMatch(line);
      if (tagLine != null) {
        tag ??= tagLine.group(1)!.trim();
        continue;
      }

      final step = _checklistLine.firstMatch(line);
      if (step != null) {
        checklist.add(step.group(1)!.trim());
        continue;
      }

      for (final hash in _hashTag.allMatches(line)) {
        tag ??= hash.group(1);
      }
      remaining.add(line.replaceAll(_hashTag, ' '));
    }

    var work = remaining.join('\n');
    DateTime? date;
    var hasExplicitDate = false;
    var defaultHour = 9;
    int? weekdayTarget;
    var weekdayIsNext = false;

    var match = _isoDate.firstMatch(work);
    if (match != null) {
      date = _safeDate(int.parse(match.group(1)!), int.parse(match.group(2)!),
          int.parse(match.group(3)!));
      if (date != null) {
        hasExplicitDate = true;
        work = _remove(work, match);
      }
    }

    match = _slashDate.firstMatch(work);
    if (match != null && date == null) {
      final first = int.parse(match.group(1)!);
      final second = int.parse(match.group(2)!);
      final yearGroup = match.group(3);
      final year = yearGroup == null
          ? at.year
          : _expandYear(int.parse(yearGroup), at.year);
      // Day/month is the default, but "11/20/2026" can only be month/day.
      final dayFirst = second > 12 && first <= 12 ? false : true;
      date = dayFirst
          ? _safeDate(year, second, first)
          : _safeDate(year, first, second);
      if (date == null && yearGroup != null) {
        date = _safeDate(year, first, second);
      }
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
          match.group(3) == null ? at.year : int.parse(match.group(3)!),
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
          match.group(3) == null ? at.year : int.parse(match.group(3)!),
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
        date = DateTime(at.year, at.month, at.day);
      } else if (phrase == 'tomorrow') {
        date = DateTime(at.year, at.month, at.day + 1);
      } else if (phrase == 'tonight') {
        date = DateTime(at.year, at.month, at.day);
      } else if (phrase == 'next week') {
        date = DateTime(at.year, at.month, at.day + 7);
      } else {
        final days = int.parse(RegExp(r'\d+').firstMatch(phrase)!.group(0)!);
        date = DateTime(at.year, at.month, at.day + days);
      }
      hasExplicitDate = true;
      work = _remove(work, match);
    }

    match = _weekday.firstMatch(work);
    if (match != null) {
      weekdayTarget = _weekdayNumber(match.group(2)!);
      weekdayIsNext = (match.group(1) ?? '').toLowerCase() == 'next';
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
      foundTime = hour >= 0 && hour <= 23 && minute >= 0 && minute <= 59;
      work = _remove(work, match);
    } else {
      match = _time24.firstMatch(work);
      if (match != null) {
        hour = int.parse(match.group(1)!);
        minute = int.parse(match.group(2)!);
        foundTime = hour >= 0 && hour <= 23 && minute >= 0 && minute <= 59;
        work = _remove(work, match);
      } else {
        match = _specialTime.firstMatch(work);
        if (match != null) {
          hour = match.group(1)!.toLowerCase() == 'noon' ? 12 : 0;
          minute = 0;
          foundTime = true;
          work = _remove(work, match);
        }
      }
    }
    if (!foundTime) {
      hour = defaultHour;
      minute = 0;
    }

    DateTime? due;
    if (hasExplicitDate && date != null) {
      due = DateTime(date.year, date.month, date.day, hour, minute);
    } else if (weekdayTarget != null &&
        weekdayTarget >= 1 &&
        weekdayTarget <= 7) {
      var days = weekdayTarget - at.weekday;
      if (weekdayIsNext && days <= 0) days += 7;
      if (days < 0) days += 7;
      var candidate = DateTime(at.year, at.month, at.day + days, hour, minute);
      // "Today" counts as the next occurrence only while the time is future.
      if (!candidate.isAfter(at)) {
        candidate = candidate.add(const Duration(days: 7));
      }
      due = candidate;
    } else if (foundTime) {
      var candidate = DateTime(at.year, at.month, at.day, hour, minute);
      if (!candidate.isAfter(at)) {
        candidate = candidate.add(const Duration(days: 1));
      }
      due = candidate;
    }

    if (due == null) return null;

    final title = work
        .split('\n')
        .map((line) => _tidy(line.replaceFirst(_leftoverConnective, ' ')))
        .where((line) => line.isNotEmpty)
        .join(' ');

    return ScheduleParse(
      title: title,
      dueLocal: due,
      tag: tag,
      checklist: List.unmodifiable(checklist),
    );
  }
}
