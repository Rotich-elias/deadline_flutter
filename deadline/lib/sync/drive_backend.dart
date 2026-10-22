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
///
/// Two devices syncing at once would otherwise overwrite each other's work,
/// so uploads carry the ETag of the file they were based on. Drive rejects a
/// stale write with 412 and the whole read-merge-write cycle is retried.
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
    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        return await _syncOnce(changes);
      } on _PreconditionFailed catch (e) {
        lastError = e;
      }
    }
    throw ApiException(
      'Another device changed the Drive file repeatedly during sync. '
      'Please try again. ($lastError)',
    );
  }

  Future<SyncResponse<T>> _syncOnce(List<T> changes) async {
    final headers = await _account.authHeaders;
    final fileId = await _findOrCreateFile(headers);
    final snapshot = await _download(headers, fileId);

    final merged = {for (final t in snapshot.items) idOf(t): t};
    for (final c in changes) {
      final existing = merged[idOf(c)];
      if (existing == null || updatedAtOf(c).isAfter(updatedAtOf(existing))) {
        merged[idOf(c)] = c;
      }
    }

    final now = DateTime.now().toUtc();
    final pruned = merged.values
        .where((t) => !(isDeleted(t) &&
            now.difference(updatedAtOf(t)) > _maxTombstoneAge))
        .toList();

    await _upload(headers, fileId, pruned, snapshot.etag);

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

    final files =
        (jsonDecode(listRes.body) as Map<String, dynamic>)['files'] as List;
    if (files.isNotEmpty) {
      return (files.first as Map<String, dynamic>)['id'] as String;
    }

    final createRes = await http
        .post(
          Uri.https('www.googleapis.com', '/drive/v3/files'),
          headers: {...headers, 'Content-Type': 'application/json'},
          body: jsonEncode({
            'name': fileName,
            'parents': ['appDataFolder'],
          }),
        )
        .timeout(const Duration(seconds: 20));
    _checkStatus(createRes);
    return (jsonDecode(createRes.body) as Map<String, dynamic>)['id'] as String;
  }

  /// Returns the file contents plus the ETag they were read at. A missing
  /// file (deleted from Drive, or a race after listing) is treated as empty
  /// so the upload recreates it instead of failing the sync.
  Future<_DriveSnapshot<T>> _download(
      Map<String, String> headers, String fileId) async {
    final uri = Uri.https(
        'www.googleapis.com', '/drive/v3/files/$fileId', {'alt': 'media'});
    final res = await http
        .get(uri, headers: headers)
        .timeout(const Duration(seconds: 20));
    if (res.statusCode == 404) return _DriveSnapshot<T>([], null);
    _checkStatus(res);
    if (res.bodyBytes.isEmpty) {
      return _DriveSnapshot<T>([], res.headers['etag']);
    }

    final list = jsonDecode(res.body) as List;
    return _DriveSnapshot<T>(
      list.map((e) => fromJson(e as Map<String, dynamic>)).toList(),
      res.headers['etag'],
    );
  }

  Future<void> _upload(Map<String, String> headers, String fileId,
      List<T> items, String? etag) async {
    final uri = Uri.https('www.googleapis.com',
        '/upload/drive/v3/files/$fileId', {'uploadType': 'media'});
    final reqHeaders = {...headers, 'Content-Type': 'application/json'};
    if (etag != null && etag.isNotEmpty) reqHeaders['If-Match'] = etag;

    final res = await http
        .patch(
          uri,
          headers: reqHeaders,
          body: jsonEncode(items.map(toJson).toList()),
        )
        .timeout(const Duration(seconds: 20));
    if (res.statusCode == 412) throw const _PreconditionFailed();
    if (res.statusCode == 404) throw const _PreconditionFailed();
    _checkStatus(res);
  }

  void _checkStatus(http.Response res) {
    if (res.statusCode == 401) {
      throw ApiException('Google sign-in expired. Sign in again in Settings.');
    }
    if (res.statusCode >= 400) {
      throw ApiException('Drive returned ${res.statusCode}.');
    }
  }
}

class _DriveSnapshot<T> {
  const _DriveSnapshot(this.items, this.etag);
  final List<T> items;
  final String? etag;
}

class _PreconditionFailed implements Exception {
  const _PreconditionFailed();
  @override
  String toString() => 'Drive file changed during sync';
}
