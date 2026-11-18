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
    stem = _cleanLine(stem);
    if (stem.isEmpty || stem.length < 2) return null;
    if (_genericNames.contains(stem.toLowerCase())) return null;
    return stem;
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
