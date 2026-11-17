import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// One line in the local activity history.
class ActivityEntry {
  const ActivityEntry({
    required this.at,
    required this.action,
    this.detail,
    this.entityId,
  });

  final DateTime at;
  final String action;
  final String? detail;
  final String? entityId;

  Map<String, dynamic> toJson() => {
        'at': at.toIso8601String(),
        'action': action,
        if (detail != null) 'detail': detail,
        if (entityId != null) 'entityId': entityId,
      };

  factory ActivityEntry.fromJson(Map<String, dynamic> json) => ActivityEntry(
        at: DateTime.tryParse(json['at'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        action: json['action'] as String? ?? '',
        detail: json['detail'] as String?,
        entityId: json['entityId'] as String?,
      );
}

/// A small, append-only log of user actions kept entirely on the device.
class ActivityLog {
  ActivityLog([this._prefs]);

  static const String storageKey = 'activity.log';
  static const int _maxEntries = 200;

  final SharedPreferences? _prefs;

  /// The production constructor: uses the platform's preferences store.
  static Future<ActivityLog> instance() async =>
      ActivityLog(await SharedPreferences.getInstance());

  Future<SharedPreferences> get _store =>
      _prefs != null ? Future.value(_prefs) : SharedPreferences.getInstance();

  /// Prepends an entry, keeping the log capped at 200 records.
  Future<void> record(
    String action, {
    String? detail,
    String? entityId,
  }) async {
    final prefs = await _store;
    final entries = _read(prefs);
    entries.insert(
      0,
      ActivityEntry(
        at: DateTime.now(),
        action: action,
        detail: detail,
        entityId: entityId,
      ),
    );
    await _write(prefs, entries.take(_maxEntries).toList());
  }

  /// Returns at most [limit] entries, newest first.
  Future<List<ActivityEntry>> recent({int limit = 100}) async {
    if (limit <= 0) return <ActivityEntry>[];
    final prefs = await _store;
    return _read(prefs).take(limit).toList();
  }

  Future<void> clear() async {
    final prefs = await _store;
    await prefs.remove(storageKey);
  }

  List<ActivityEntry> _read(SharedPreferences prefs) {
    final raw = prefs.getString(storageKey);
    if (raw == null || raw.isEmpty) return <ActivityEntry>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <ActivityEntry>[];
      final entries = <ActivityEntry>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        final json = Map<String, dynamic>.from(item);
        if (json['action'] is! String) continue;
        entries.add(ActivityEntry.fromJson(json));
      }
      return entries.length > _maxEntries
          ? entries.sublist(0, _maxEntries)
          : entries;
    } catch (_) {
      return <ActivityEntry>[];
    }
  }

  Future<void> _write(SharedPreferences prefs, List<ActivityEntry> entries) =>
      prefs.setString(
        storageKey,
        jsonEncode(entries.map((entry) => entry.toJson()).toList()),
      );
}
