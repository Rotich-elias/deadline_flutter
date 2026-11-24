import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_advert.dart';
import '../utils/company.dart';

/// Remembers which advert IDs have already been shown on this install.
abstract class AdvertSeenStore {
  const AdvertSeenStore();

  Future<bool> isSeen(String id);
  Future<void> markSeen(String id);

  /// Allows a one-time migration when the stored IDs are known to be wrong.
  Future<void> resetIfNeeded() async {}
}

/// Stores the seen IDs in SharedPreferences, newest last. The list is capped so
/// a long-lived install cannot accumulate an unbounded number of IDs.
class SharedPreferencesAdvertSeenStore implements AdvertSeenStore {
  const SharedPreferencesAdvertSeenStore();

  static const _key = 'adverts.seenIds';
  static const _versionKey = 'adverts.seenStoreVersion';
  static const _currentVersion = 2;
  static const _maxSeen = 200;

  /// Builds before v1.0.31 marked an advert as seen even when its dialog failed
  /// to open. Clear those false positives once so the published adverts show.
  @override
  Future<void> resetIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getInt(_versionKey) == _currentVersion) return;
    await prefs.remove(_key);
    await prefs.setInt(_versionKey, _currentVersion);
  }

  Future<List<String>> _readAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return <String>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <String>[];
      return decoded
          .whereType<String>()
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();
    } catch (_) {
      return <String>[];
    }
  }

  @override
  Future<bool> isSeen(String id) async => (await _readAll()).contains(id);

  @override
  Future<void> markSeen(String id) async {
    final all = (await _readAll())..remove(id);
    all.add(id);
    final trimmed = all.length > _maxSeen ? all.sublist(all.length - _maxSeen) : all;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(trimmed));
  }
}

/// Fetches the active adverts published by teto.co.ke and filters out the ones
/// this install has already seen. All failures are silent: ads must never get
/// in the way of this offline-first app.
class AdvertService {
  const AdvertService({
    String? url,
    http.Client? client,
    AdvertSeenStore? store,
  })  : url = url ?? Company.advertUrl,
        _client = client,
        _store = store;

  /// Public JSON feed, overridable in tests or deployments.
  final String url;
  final http.Client? _client;
  final AdvertSeenStore? _store;

  Future<List<AppAdvert>> check(String currentVersion) async {
    final ownedClient = _client == null;
    final client = _client ?? http.Client();
    try {
      final uri = Uri.parse(url);
      if (!uri.hasScheme || (uri.scheme != 'https' && uri.scheme != 'http')) {
        return const <AppAdvert>[];
      }

      final res = await client
          .get(
            uri,
            headers: {
              'Accept': 'application/json',
              'User-Agent': 'DeadlinesNotes/$currentVersion',
            },
          )
          .timeout(const Duration(seconds: 8));
      if (res.statusCode >= 400) return const <AppAdvert>[];

      final decoded = jsonDecode(res.body);
      if (decoded is! Map<String, dynamic>) return const <AppAdvert>[];
      final items = decoded['adverts'];
      if (items is! List) return const <AppAdvert>[];

      final store = _store ?? const SharedPreferencesAdvertSeenStore();
      await store.resetIfNeeded();
      final unseen = <AppAdvert>[];
      for (final item in items) {
        final advert = AppAdvert.tryFromJson(item);
        if (advert == null) continue;
        if (await store.isSeen(advert.key)) continue;
        unseen.add(advert);
      }
      return unseen;
    } catch (e) {
      debugPrint('Advert check skipped: $e');
      return const <AppAdvert>[];
    } finally {
      if (ownedClient) client.close();
    }
  }

  /// Called only after the popup has actually been shown to the user.
  Future<void> markSeen(AppAdvert advert) async {
    final store = _store ?? const SharedPreferencesAdvertSeenStore();
    await store.markSeen(advert.key);
  }
}
