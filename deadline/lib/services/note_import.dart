import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../data/notes_store.dart';
import '../models/note.dart';

/// One thing shared into the app: the text itself plus the name the sharing
/// app gave it. Samsung Notes' `.txt` export drops the note's title from the
/// text but keeps it as the file name, so the name is worth carrying along.
class SharedNote {
  const SharedNote(this.text, {this.name});

  final String text;
  final String? name;
}

/// Connection to the native share receiver. Anything shared into the app
/// (for example a note exported from Samsung Notes) is buffered until the UI
/// is ready to import it.
class SharedNotesInbox extends ChangeNotifier {
  SharedNotesInbox._();
  static final instance = SharedNotesInbox._();

  static const _channel = MethodChannel('deadline/notifications');

  final List<SharedNote> _pending = [];
  bool _listening = false;

  /// Number of "Quick note" shortcut requests seen since startup. A launcher
  /// shortcut can arrive while the app is already open, so the UI watches this
  /// counter as well as the cold-start flag.
  int quickNoteRequests = 0;

  /// Starts listening for shares and drains anything that arrived while the
  /// app was starting. Safe to call more than once.
  Future<void> start() async {
    if (!_listening) {
      _listening = true;
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'sharedNotes') await pull();
        if (call.method == 'quickNote') {
          quickNoteRequests++;
          notifyListeners();
        }
        return null;
      });
    }
    await pull();
  }

  /// Collects whatever the native side has buffered.
  Future<void> pull() async {
    try {
      final raw = await _channel.invokeMethod<List<Object?>>('takeSharedNotes');
      if (raw == null || raw.isEmpty) return;
      final shares = <SharedNote>[];
      for (final item in raw) {
        final note = _decode(item);
        if (note != null) shares.add(note);
      }
      if (shares.isEmpty) return;
      _pending.addAll(shares);
      notifyListeners();
    } on MissingPluginException {
      // Not an Android device, or the plugin is unavailable in a test.
    } catch (e) {
      debugPrint('Could not collect shared notes: $e');
    }
  }

  /// Newer builds send `{text, name}` maps; plain strings are still accepted
  /// so an older buffered payload does not get dropped.
  static SharedNote? _decode(Object? item) {
    if (item is String) {
      return item.trim().isEmpty ? null : SharedNote(item);
    }
    if (item is Map) {
      final text = item['text']?.toString().trim() ?? '';
      if (text.isEmpty) return null;
      final name = item['name']?.toString().trim();
      return SharedNote(text,
          name: (name == null || name.isEmpty) ? null : name);
    }
    return null;
  }

  /// Hands over the buffered notes and clears the buffer.
  List<SharedNote> take() {
    final out = List<SharedNote>.from(_pending);
    _pending.clear();
    return out;
  }
}

class ImportOutcome {
  const ImportOutcome({required this.imported, required this.duplicates});

  final int imported;
  final int duplicates;

  bool get isEmpty => imported == 0;
}

class ParsedNote {
  const ParsedNote({required this.title, this.body});

  final String title;
  final String? body;
}

/// Turns shared plain text or Samsung Notes `.txt` exports into notes.
///
/// Shared text is split on its first non-empty line, which becomes the title.
/// When the sharing app also supplies a file name (Samsung Notes titles its
/// export after the note), that name is preferred as the title and the whole
/// text stays as the body, because the export itself leaves the title out.
class NoteImport {
  NoteImport._();

  static const _maxTitle = 120;

  /// Leading direction marks and zero-width characters some exports carry.
  static final _leadingMarks = RegExp(r'^[\u200e\u200f\u202a-\u202e\ufeff]+');

  /// Samsung Notes names text exports `<title>_<yymmdd>_<hhmmss>.txt`. The
  /// timestamp is not part of the title; stripping it keeps "Movies list" out
  /// of "Movies list _261011_141605" and falls back to the note's first line
  /// when the rest is just "Notes".
  static final _exportTimestamp = RegExp(r'[ _]\d{6,8}[ _]\d{4,6}$');

  /// Samsung adds " (1)", " (2)" … when exporting the same note again to a
  /// folder that already holds the earlier file. Strip it before the timestamp
  /// so re-shares keep the same title and are recognised as duplicates.
  static final _copySuffix = RegExp(r'\s*\(\d+\)$');

  /// File names that say nothing about the note; never use them as a title.
  static const _genericNames = {
    'text',
    'note',
    'notes',
    'untitled',
    'samsung notes',
    'share',
    'shared note',
  };

  static ParsedNote? parse(String raw, {String? name}) {
    var text = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    if (text.startsWith('\ufeff')) text = text.substring(1);

    final lines = text.split('\n');
    var start = 0;
    while (start < lines.length && lines[start].trim().isEmpty) {
      start++;
    }
    if (start >= lines.length) return null;

    final firstLine = _cleanLine(lines[start]);
    if (firstLine.isEmpty) return null;

    final hint = _titleFromName(name);
    final useHint =
        hint != null && hint.toLowerCase() != firstLine.toLowerCase();

    var title = useHint ? hint : firstLine;
    var body = lines.sublist(useHint ? start : start + 1).join('\n').trim();

    if (title.length > _maxTitle) {
      final cut = _splitPoint(title);
      final overflow = title.substring(cut).trim();
      title = title.substring(0, cut).trim();
      body = [if (overflow.isNotEmpty) overflow, if (body.isNotEmpty) body]
          .join('\n');
    }

    return ParsedNote(title: title, body: body.isEmpty ? null : body);
  }

  static String _cleanLine(String line) => line
      .trim()
      .replaceFirst(_leadingMarks, '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  /// "Jobs to be paid.txt" -> "Jobs to be paid"; nothing for generic names.
  static String? _titleFromName(String? name) {
    if (name == null) return null;
    var stem = name.trim();
    final slash = stem.lastIndexOf(RegExp(r'[/\\]'));
    if (slash >= 0) stem = stem.substring(slash + 1);
    if (stem.toLowerCase().endsWith('.txt')) {
      stem = stem.substring(0, stem.length - 4);
    }
    stem = stem.replaceFirst(_copySuffix, '');
    return _meaningfulTitle(_cleanLine(stem));
  }

  static String? _meaningfulTitle(String stem) {
    stem = stem.replaceFirst(_exportTimestamp, '').trim();
    if (stem.isEmpty || stem.length < 2) return null;
    if (_genericNames.contains(stem.toLowerCase())) return null;
    return stem;
  }

  /// Repairs notes imported by older builds that used the whole Samsung Notes
  /// file name ("Books idea_260708_045209") as their title. Also removes
  /// duplicates left by a re-share whose file names gained Samsung's " (1)"
  /// copy suffix. Safe to run on every launch: notes without the Samsung
  /// import pattern are left untouched.
  static Future<int> repairLegacyTitles(NotesStore store) async {
    var changed = 0;
    final removedIds = <String>{};
    final all = List<Note>.from(store.notes);
    final archived = List<Note>.from(store.archived);

    for (final note in all) {
      if (removedIds.contains(note.id)) continue;
      final fixed = _repairTitle(note.title, note.body);
      if (fixed == null) continue;

      final key = _key(fixed.title, fixed.body);
      Note? twin;
      for (final other in [...all, ...archived]) {
        if (other.id == note.id || removedIds.contains(other.id)) continue;
        if (_key(other.title, other.body) == key) {
          twin = other;
          break;
        }
      }
      if (twin != null) {
        // Keep the older copy and purge the newer re-share artifact.
        final drop = note.updatedAt.isBefore(twin.updatedAt) ? twin : note;
        removedIds.add(drop.id);
        await store.purge(drop);
        changed++;
        continue;
      }

      if (fixed.title == note.title && fixed.body == note.body) continue;
      await store.save(note.copyWith(title: fixed.title, body: fixed.body));
      changed++;
    }
    return changed;
  }

  static ParsedNote? _repairTitle(String title, String? body) {
    final clean = _cleanLine(title).replaceFirst(_copySuffix, '').trim();
    if (!_exportTimestamp.hasMatch(clean)) return null;
    final hint = _meaningfulTitle(clean);
    if (hint != null) return ParsedNote(title: hint, body: body);

    // A generic file name ("Notes_…") meant the old importer used the first
    // line as the title but left that line in the body too. Re-split the body
    // so the repaired note matches a fresh import and is not duplicated when
    // the same Samsung note is shared again.
    return parse(body ?? '');
  }

  static int _splitPoint(String title) {
    final cut = title.lastIndexOf(' ', _maxTitle);
    return cut < _maxTitle ~/ 2 ? _maxTitle : cut;
  }

  static String _key(String title, String? body) =>
      '${title.trim()}\u0000${(body ?? '').trim()}';

  /// Imports every shared note, skipping exact duplicates of notes already in
  /// the app (live or archived).
  static Future<ImportOutcome> importAll(
    NotesStore store,
    Iterable<SharedNote> shares,
  ) async {
    final seen = <String>{
      for (final n in store.notes) _key(n.title, n.body),
      for (final n in store.archived) _key(n.title, n.body),
    };

    var imported = 0;
    var duplicates = 0;
    for (final share in shares) {
      final parsed = parse(share.text, name: share.name);
      if (parsed == null) continue;
      if (!seen.add(_key(parsed.title, parsed.body))) {
        duplicates++;
        continue;
      }
      await store.add(Note.create(title: parsed.title, body: parsed.body));
      imported++;
    }
    return ImportOutcome(imported: imported, duplicates: duplicates);
  }
}
