import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_update.dart';
import '../utils/company.dart';

/// Remembers the last seen fingerprint of the APK URL across launches.
abstract class UpdateFingerprintStore {
  const UpdateFingerprintStore();

  Future<String?> read(String url);
  Future<void> write(String url, String fingerprint);
}

/// Stores one fingerprint per download URL in SharedPreferences.
class SharedPreferencesFingerprintStore implements UpdateFingerprintStore {
  const SharedPreferencesFingerprintStore();

  static const _key = 'update.apkFingerprints';

  Future<Map<String, String>> _readAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return <String, String>{};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(k, v.toString()));
    } catch (_) {
      return <String, String>{};
    }
  }

  @override
  Future<String?> read(String url) async => (await _readAll())[url];

  @override
  Future<void> write(String url, String fingerprint) async {
    final all = await _readAll();
    all[url] = fingerprint;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(all));
  }
}

/// Checks for a new APK without any server-side API.
///
/// A HEAD request follows the download redirect and reads the final URL plus
/// the file's ETag / Last-Modified / size. When the filename carries a version
/// (`deadline-1.0.24-<hash>.apk`) it is compared with the installed version;
/// otherwise a changed fingerprint means a new upload. Every failure is silent
/// so a flaky network or a server that omits those headers never interrupts
/// this offline-first app.
class UpdateService {
  const UpdateService({
    String? url,
    http.Client? client,
    UpdateFingerprintStore? store,
  })  : url = url ?? Company.apkUrl,
        _client = client,
        _store = store;

  /// Full URL of the published APK, overridable in tests or deployments.
  final String url;
  final http.Client? _client;
  final UpdateFingerprintStore? _store;

  Future<AppUpdate?> check(String currentVersion) async {
    final ownedClient = _client == null;
    final client = _client ?? http.Client();
    try {
      final uri = Uri.parse(url);
      if (!uri.hasScheme || (uri.scheme != 'https' && uri.scheme != 'http')) {
        return null;
      }

      final res = await client
          .head(
            uri,
            headers: {
              'Accept': '*/*',
              'User-Agent': 'DeadlinesNotes/$currentVersion',
            },
          )
          .timeout(const Duration(seconds: 8));
      if (res.statusCode >= 400) return null;

      final fingerprint = _fingerprint(res.headers);
      if (fingerprint.isEmpty) return null;

      final store = _store ?? const SharedPreferencesFingerprintStore();
      final previous = await store.read(url);
      await store.write(url, fingerprint);

      // The download URL redirects to a file whose name carries the version
      // (e.g. `deadline-1.0.24-<hash>.apk`). That is more precise than the
      // fingerprint: re-uploading the same version must not prompt again.
      final finalUrl = res.request?.url.toString() ?? url;
      final parsedVersion =
          _versionFromUrl(finalUrl) ?? _versionFromUrl(url);
      if (parsedVersion != null) {
        return AppUpdate.compareVersions(currentVersion, parsedVersion) < 0
            ? _available(parsedVersion)
            : null;
      }

      // No version in the URL: fall back to "the file changed". The first
      // observation only records a baseline, so it never prompts spuriously.
      if (previous == null || previous == fingerprint) return null;
      return _available(null);
    } catch (e) {
      // Network, timeout or a broken response all mean "no update right now".
      debugPrint('Update check skipped: $e');
      return null;
    } finally {
      if (ownedClient) client.close();
    }
  }

  AppUpdate _available(String? version) => AppUpdate(
        latestVersion: version,
        url: url,
        notes: 'A new version has been uploaded. Tap Update to download it.',
      );

  /// Header keys from the http package are lower-cased, but be lenient.
  static String _fingerprint(Map<String, String> headers) {
    String? get(String key) {
      for (final entry in headers.entries) {
        if (entry.key.toLowerCase() == key) return entry.value.trim();
      }
      return null;
    }

    return [
      get('etag'),
      get('last-modified'),
      get('content-length'),
    ].where((value) => value != null && value.isNotEmpty).join('|');
  }

  /// Picks `1.0.25` out of a filename like `deadline-1.0.25.apk`, when present.
  static String? _versionFromUrl(String url) {
    final segments = Uri.tryParse(url)?.pathSegments ?? const <String>[];
    if (segments.isEmpty) return null;
    return RegExp(r'(\d+(?:\.\d+){1,3})').firstMatch(segments.last)?.group(1);
  }
}
