import 'dart:convert';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

import 'sync_backend.dart';

const driveScopes = <String>['https://www.googleapis.com/auth/drive.appdata'];

/// Tombstones older than this are dropped from the shared file so it doesn't
/// grow forever; every device has long since seen the delete by then.
const _maxTombstoneAge = Duration(days: 30);

/// Stores a whole entity list (tasks, or notes) as one JSON file in the
/// user's Drive appDataFolder — an app-private space that never shows up in
/// their normal Drive UI. There's no per-row server index like the Laravel
/// backend has, so every sync downloads the full file, merges in local
/// changes newest-wins, and re-uploads the merged set. One instance per
/// entity type, each with its own file name and (de)serializers.
class DriveBackend<T> implements SyncBackend<T> {
  DriveBackend(
    this._account, {
    required this.fileName,
    required this.toJson,
    required this.fromJson,
    required this.idOf,
    required this.updatedAtOf,
    required this.isDeleted,
  });

  final GoogleSignInAccount _account;
  final String fileName;
  final Map<String, dynamic> Function(T) toJson;
  final T Function(Map<String, dynamic>) fromJson;
  final String Function(T) idOf;
  final DateTime Function(T) updatedAtOf;
  final bool Function(T) isDeleted;

  @override
  Future<SyncResponse<T>> sync({
    required List<T> changes,
    DateTime? since,
  }) async {
    final headers = await _account.authHeaders;
    final fileId = await _findOrCreateFile(headers);
    final remote = await _download(headers, fileId);

    final merged = {for (final t in remote) idOf(t): t};
    for (final c in changes) {
      final existing = merged[idOf(c)];
      if (existing == null ||
          updatedAtOf(c).isAfter(updatedAtOf(existing))) {
        merged[idOf(c)] = c;
      }
    }

    final now = DateTime.now().toUtc();
    final pruned = merged.values
        .where((t) => !(isDeleted(t) &&
            now.difference(updatedAtOf(t)) > _maxTombstoneAge))
        .toList();

    await _upload(headers, fileId, pruned);

    return SyncResponse(serverTime: now, items: pruned);
  }

  Future<String> _findOrCreateFile(Map<String, String> headers) async {
    final listUri = Uri.https('www.googleapis.com', '/drive/v3/files', {
      'spaces': 'appDataFolder',
      'q': "name='$fileName'",
      'fields': 'files(id)',
    });
    final listRes = await http
        .get(listUri, headers: headers)
        .timeout(const Duration(seconds: 20));
    _checkStatus(listRes);

    final files = (jsonDecode(listRes.body) as Map<String, dynamic>)['files']
        as List;
    if (files.isNotEmpty) {
      return (files.first as Map<String, dynamic>)['id'] as String;
    }

    final createUri = Uri.https('www.googleapis.com', '/drive/v3/files');
    final createRes = await http
        .post(
          createUri,
          headers: {...headers, 'Content-Type': 'application/json'},
          body: jsonEncode({
            'name': fileName,
            'parents': ['appDataFolder'],
          }),
        )
        .timeout(const Duration(seconds: 20));
    _checkStatus(createRes);
    return (jsonDecode(createRes.body) as Map<String, dynamic>)['id']
        as String;
  }

  Future<List<T>> _download(
      Map<String, String> headers, String fileId) async {
    final uri = Uri.https(
        'www.googleapis.com', '/drive/v3/files/$fileId', {'alt': 'media'});
    final res =
        await http.get(uri, headers: headers).timeout(const Duration(seconds: 20));
    if (res.statusCode == 404) return [];
    _checkStatus(res);
    if (res.bodyBytes.isEmpty) return [];

    final list = jsonDecode(res.body) as List;
    return list.map((e) => fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> _upload(
      Map<String, String> headers, String fileId, List<T> items) async {
    final uri = Uri.https('www.googleapis.com',
        '/upload/drive/v3/files/$fileId', {'uploadType': 'media'});
    final res = await http
        .patch(
          uri,
          headers: {...headers, 'Content-Type': 'application/json'},
          body: jsonEncode(items.map(toJson).toList()),
        )
        .timeout(const Duration(seconds: 20));
    _checkStatus(res);
  }

  void _checkStatus(http.Response res) {
    if (res.statusCode == 401) {
      throw ApiException(
          'Google sign-in expired. Sign in again in Settings.');
    }
    if (res.statusCode >= 400) {
      throw ApiException('Drive returned ${res.statusCode}.');
    }
  }
}
