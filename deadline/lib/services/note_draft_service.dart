import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Unsaved note form state kept across an external camera hand-off. Android can
/// destroy the activity (and the Flutter engine with it) while the camera is
/// open, so the in-memory form state cannot be relied on when it returns.
class NoteDraft {
  const NoteDraft({
    required this.title,
    required this.body,
    required this.tag,
    required this.notebook,
    required this.labels,
    required this.draftId,
    this.existingId,
  });

  final String title;
  final String body;
  final String tag;
  final String notebook;
  final List<String> labels;
  final String draftId;
  final String? existingId;

  Map<String, dynamic> toJson() => {
        'title': title,
        'body': body,
        'tag': tag,
        'notebook': notebook,
        'labels': labels,
        'draftId': draftId,
        'existingId': existingId,
      };

  factory NoteDraft.fromJson(Map<String, dynamic> json) => NoteDraft(
        title: json['title'] as String? ?? '',
        body: json['body'] as String? ?? '',
        tag: json['tag'] as String? ?? '',
        notebook: json['notebook'] as String? ?? '',
        labels: (json['labels'] as List<dynamic>? ?? const [])
            .map((e) => e.toString())
            .toList(),
        draftId: json['draftId'] as String? ?? '',
        existingId: json['existingId'] as String?,
      );
}

class NoteDraftService {
  NoteDraftService({Future<SharedPreferences> Function()? prefs})
      : _prefs = prefs ?? SharedPreferences.getInstance;

  final Future<SharedPreferences> Function() _prefs;

  static const key = 'note.pending_draft';

  Future<void> save(NoteDraft draft) async {
    final prefs = await _prefs();
    await prefs.setString(key, jsonEncode(draft.toJson()));
  }

  Future<NoteDraft?> peek() async {
    final prefs = await _prefs();
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return null;
    try {
      return NoteDraft.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// Reads and removes the draft; the note form owns it from this point on.
  Future<NoteDraft?> take() async {
    final draft = await peek();
    if (draft != null) await clear();
    return draft;
  }

  Future<void> clear() async {
    final prefs = await _prefs();
    await prefs.remove(key);
  }
}
