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

      // The APK's real filename carries the version (e.g.
      // `deadline-1.0.26-<hash>.apk`). Dart's http client reports the original
      // request url after a redirect, so read Content-Disposition first — the
      // version is there on the final 200 response. Fall back to the URL only
      // for deployments that publish a versioned download link directly.
      final parsedVersion = _versionFromHeaders(res.headers) ??
          _versionFromUrl(res.request?.url.toString() ?? url) ??
          _versionFromUrl(url);
      if (parsedVersion != null) {
        return AppUpdate.compareVersions(currentVersion, parsedVersion) < 0
            ? _available(parsedVersion, fingerprint)
            : null;
      }

      // No version in the URL: fall back to "the file changed". The first
      // observation only records a baseline, so it never prompts spuriously.
      if (previous == null || previous == fingerprint) return null;
      return _available(null, fingerprint);
    } catch (e) {
      // Network, timeout or a broken response all mean "no update right now".
      debugPrint('Update check skipped: $e');
      return null;
    } finally {
      if (ownedClient) client.close();
    }
  }

  AppUpdate _available(String? version, String fingerprint) => AppUpdate(
        latestVersion: version,
        updateKey: version ?? fingerprint,
        url: url,
        notes: 'A new version has been uploaded. Tap Update to download it.',
      );

  /// Header keys from the http package are lower-cased, but be lenient.
  static String? _header(Map<String, String> headers, String key) {
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == key) return entry.value.trim();
    }
    return null;
  }

  static String _fingerprint(Map<String, String> headers) {
    return [
      _header(headers, 'etag'),
      _header(headers, 'last-modified'),
      _header(headers, 'content-length'),
    ].where((value) => value != null && value.isNotEmpty).join('|');
  }

  /// Reads `deadline-1.0.26-<hash>.apk` from a `Content-Disposition` header,
  /// or from a redirect `Location`. Both are needed because Dart's http client
  /// reports the original request url after following a redirect.
  static String? _versionFromHeaders(Map<String, String> headers) {
    final disposition = _header(headers, 'content-disposition');
    if (disposition != null) {
      final match = RegExp(r'filename\s*=\s*"?([^";]+)', caseSensitive: false)
          .firstMatch(disposition);
      if (match != null) {
        final version = _versionFromFilename(match.group(1)!);
        if (version != null) return version;
      }
    }
    final location = _header(headers, 'location');
    return location == null ? null : _versionFromUrl(location);
  }

  /// Picks `1.0.25` out of a filename like `deadline-1.0.25.apk`, when present.
  static String? _versionFromFilename(String name) =>
      RegExp(r'(\d+(?:\.\d+){1,3})').firstMatch(name)?.group(1);

  static String? _versionFromUrl(String url) {
    final segments = Uri.tryParse(url)?.pathSegments ?? const <String>[];
    if (segments.isEmpty) return null;
    return _versionFromFilename(segments.last);
  }
}
