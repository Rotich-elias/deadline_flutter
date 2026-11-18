import '../models/note.dart';
import '../models/task.dart';

/// Matches a single, simple `[[target]]` pair. Brackets inside the target are
/// treated as malformed, which also keeps the pattern from running across two
/// adjacent links.
final _linkPattern = RegExp(r'\[\[([^\[\]]+)\]\]');

const _taskPrefix = 'tasks:';

/// One `[[...]]` link found in a raw string.
///
/// [start] and [end] are offsets into that original raw string: [start] is the
/// index of the first `[`, and [end] is one past the second `]`. They can be
/// used directly with `String.substring(start, end)` to highlight or replace
/// the link without disturbing the surrounding text.
class NoteLink {
  const NoteLink({
    required this.target,
    required this.isTask,
    required this.start,
    required this.end,
  });

  /// The linked title, trimmed and without the `tasks:` prefix.
  final String target;

  /// True for `[[tasks:...]]` links, false for plain `[[...]]` note links.
  final bool isTask;

  /// Inclusive offset of the opening `[[` in the raw string.
  final int start;

  /// Exclusive offset just after the closing `]]` in the raw string.
  final int end;

  @override
  bool operator ==(Object other) =>
      other is NoteLink &&
      other.target == target &&
      other.isTask == isTask &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(target, isTask, start, end);

  @override
  String toString() =>
      'NoteLink(target: $target, isTask: $isTask, start: $start, end: $end)';
}

/// Finds and strips wiki-style links in note bodies and task notes.
///
/// Both `[[Exact Note Title]]` and `[[tasks:Task Title]]` are accepted. The
/// `tasks:` prefix is case-insensitive, and whitespace around the title is
/// ignored. Links are non-overlapping: parsing consumes the whole `[[...]]`
/// pair, so adjacent links never share offsets.
class LinkParser {
  const LinkParser._();

  /// Returns the links in [text], in the order they appear.
  ///
  /// Null, empty, blank and malformed input yields an empty list rather than a
  /// throw. Links whose target is empty (including `[[tasks:]]`) are ignored.
  static List<NoteLink> parse(String? text) {
    if (text == null || text.isEmpty) return const <NoteLink>[];
    final links = <NoteLink>[];
    for (final match in _linkPattern.allMatches(text)) {
      final link = _linkAt(text, match);
      if (link != null) links.add(link);
    }
    return links;
  }

  /// Returns [text] with link brackets removed and the display title kept.
  ///
  /// For previews and search, `[[Exact Note Title]]` becomes `Exact Note Title`.
  /// A `tasks:` prefix is a routing hint rather than display text, so
  /// `[[tasks:Pay rent]]` becomes `Pay rent`. Text that is not a valid link,
  /// including malformed bracket runs, is left exactly as it was.
  static String strip(String? text) {
    if (text == null || text.isEmpty) return '';
    return text.replaceAllMapped(_linkPattern, (match) {
      final link = _linkAt(text, match);
      return link?.target ?? match.group(0)!;
    });
  }

  static NoteLink? _linkAt(String text, Match match) {
    // A run of three or more brackets (e.g. `[[[A]]]`) would match only its
    // inner pair. Treat the whole run as malformed instead of linking part of
    // it; the same rule applies to a stray bracket just after a valid pair.
    if (match.start > 0 && text[match.start - 1] == '[') return null;
    if (match.end < text.length && text[match.end] == ']') return null;

    final raw = match.group(1);
    if (raw == null) return null;
    var content = raw.trim();
    if (content.isEmpty) return null;

    var isTask = false;
    if (content.length >= _taskPrefix.length &&
        content.substring(0, _taskPrefix.length).toLowerCase() == _taskPrefix) {
      isTask = true;
      content = content.substring(_taskPrefix.length).trim();
    }
    if (content.isEmpty) return null;

    return NoteLink(
      target: content,
      isTask: isTask,
      start: match.start,
      end: match.end,
    );
  }
}

/// A source that references a title, used by [BacklinkIndex].
class Backlink {
  const Backlink({
    required this.sourceId,
    required this.sourceTitle,
    required this.sourceIsTask,
  });

  /// Id of the note or task containing the link.
  final String sourceId;

  /// Title of that note or task, as stored.
  final String sourceTitle;

  /// True when the source is a task, false when it is a note.
  final bool sourceIsTask;

  @override
  bool operator ==(Object other) =>
      other is Backlink &&
      other.sourceId == sourceId &&
      other.sourceTitle == sourceTitle &&
      other.sourceIsTask == sourceIsTask;

  @override
  int get hashCode => Object.hash(sourceId, sourceTitle, sourceIsTask);

  @override
  String toString() =>
      'Backlink(sourceId: $sourceId, sourceTitle: $sourceTitle, '
      'sourceIsTask: $sourceIsTask)';
}

/// An in-memory reverse index of `[[...]]` links.
///
/// Note bodies, task notes and task titles are scanned as sources. Targets are
/// matched case-insensitively and trimmed, so `[[  meetings  ]]` resolves a
/// note titled `Meetings`. A plain link resolves a note; a `tasks:` link
/// resolves a deadline. Each source is listed at most once per target, even
/// when it mentions that target several times.
class BacklinkIndex {
  BacklinkIndex([Iterable<Note>? notes, Iterable<Task>? tasks]) {
    for (final note in notes ?? const <Note>[]) {
      _addSource(note.id, note.title, false, [note.body]);
    }
    for (final task in tasks ?? const <Task>[]) {
      _addSource(task.id, task.title, true, [task.notes, task.title]);
    }
  }

  final Map<String, List<Backlink>> _byTarget = {};

  /// Sources that link to [title].
  ///
  /// [isTask] must agree with the kind of link: false for `[[title]]`, true for
  /// `[[tasks:title]]`. A blank title returns no backlinks.
  List<Backlink> forTarget(String title, {required bool isTask}) {
    final key = _key(title);
    if (key.isEmpty) return const <Backlink>[];
    return List.unmodifiable(
        _byTarget[_typedKey(key, isTask)] ?? const <Backlink>[]);
  }

  /// Links written in [note]'s body, in the order they appear.
  List<NoteLink> outgoing(Note note) => LinkParser.parse(note.body);

  void _addSource(
    String id,
    String sourceTitle,
    bool sourceIsTask,
    List<String?> texts,
  ) {
    final backlink = Backlink(
      sourceId: id,
      sourceTitle: sourceTitle,
      sourceIsTask: sourceIsTask,
    );
    final seen = <String>{};
    for (final text in texts) {
      for (final link in LinkParser.parse(text)) {
        final key = _key(link.target);
        final typed = _typedKey(key, link.isTask);
        if (key.isEmpty || !seen.add(typed)) continue;
        (_byTarget[typed] ??= <Backlink>[]).add(backlink);
      }
    }
  }

  static String _key(String title) => title.trim().toLowerCase();

  static String _typedKey(String key, bool isTask) =>
      isTask ? 'task:$key' : 'note:$key';
}
