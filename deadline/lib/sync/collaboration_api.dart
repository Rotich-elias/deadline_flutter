import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/shared_list.dart';
import 'sync_backend.dart';

/// REST client for the optional collaboration endpoints documented in
/// `backend/api_routes_v2.php`. It reuses the same bearer token as task/note
/// sync and never stores anything locally: shared lists live on the server.
class CollaborationApi {
  CollaborationApi({
    required String baseUrl,
    required this.token,
    http.Client? client,
  })  : baseUrl = baseUrl.replaceFirst(RegExp(r'/+$'), ''),
        _client = client;

  final String baseUrl;
  final String token;
  final http.Client? _client;

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('$baseUrl$path').replace(
          queryParameters: query == null || query.isEmpty ? null : query);

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
      };

  Future<Object?> _request(
    String method,
    String path, {
    Object? body,
    Map<String, String>? query,
    bool allowNotFound = false,
  }) async {
    final client = _client ?? http.Client();
    final uri = _uri(path, query);
    late final http.Response res;
    switch (method) {
      case 'POST':
        res = await client.post(uri, headers: _headers, body: jsonEncode(body));
        break;
      case 'DELETE':
        res = await client.delete(uri, headers: _headers);
        break;
      default:
        res = await client.get(uri, headers: _headers);
    }
    if (allowNotFound && res.statusCode == 404) return null;
    if (res.statusCode == 401) {
      throw ApiException('Token rejected. Check it in Sync settings.');
    }
    if (res.statusCode >= 400) {
      throw ApiException(_message(res));
    }
    if (res.body.trim().isEmpty) return null;
    try {
      return jsonDecode(res.body);
    } on FormatException {
      throw ApiException('The server returned an unexpected response.');
    }
  }

  String _message(http.Response res) {
    try {
      final decoded = jsonDecode(res.body);
      if (decoded is Map && decoded['message'] != null) {
        return decoded['message'].toString();
      }
    } catch (_) {
      // Fall through to the status-only message.
    }
    return 'Server returned ${res.statusCode}.';
  }

  static Map<String, dynamic> _map(Object? value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

  static List<Map<String, dynamic>> _list(Object? value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList(growable: false);
  }

  Future<List<SharedList>> lists() async {
    final raw = await _request('GET', '/api/shared-lists');
    return _list(raw).map(SharedList.fromJson).toList(growable: false);
  }

  Future<SharedList> show(int listId) async {
    final raw = await _request('GET', '/api/shared-lists/$listId');
    return SharedList.fromJson(_map(raw));
  }

  Future<SharedList> create(String name) async {
    final raw = await _request('POST', '/api/shared-lists', body: {
      'name': name.trim(),
    });
    return SharedList.fromJson(_map(raw));
  }

  Future<SharedInvitation> invite(int listId, String email) async {
    final raw = await _request(
      'POST',
      '/api/shared-lists/$listId/invite',
      body: {'email': email.trim()},
    );
    return SharedInvitation.fromJson(_map(raw));
  }

  Future<List<SharedInvitation>> invitations(int listId) async {
    final raw = await _request('GET', '/api/shared-lists/$listId/invitations');
    return _list(raw).map(SharedInvitation.fromJson).toList(growable: false);
  }

  /// Accepts by token. The server still checks that the signed-in email is the
  /// invited address; this client only passes the token through.
  Future<SharedList> accept(String token) async {
    final raw = await _request(
      'POST',
      '/api/shared-lists/accept/${Uri.encodeComponent(token.trim())}',
    );
    final map = _map(raw);
    final list = map['shared_list'];
    return SharedList.fromJson(
        list is Map ? Map<String, dynamic>.from(list) : map);
  }

  Future<List<SharedMember>> members(int listId) async {
    final raw = await _request('GET', '/api/shared-lists/$listId/members');
    return _list(raw).map(SharedMember.fromJson).toList(growable: false);
  }

  Future<List<String>> tasks(int listId) async {
    final raw = await _request('GET', '/api/shared-lists/$listId/tasks');
    return _list(raw)
        .map((t) => (t['id'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toList(growable: false);
  }

  Future<void> attach(int listId, String taskId) => _request(
        'POST',
        '/api/shared-lists/$listId/tasks/${Uri.encodeComponent(taskId)}',
      );

  Future<void> detach(int listId, String taskId) => _request(
        'DELETE',
        '/api/shared-lists/$listId/tasks/${Uri.encodeComponent(taskId)}',
      );

  Future<SharedAccount?> lookup(String email) async {
    final raw = await _request(
      'GET',
      '/api/accounts/lookup',
      query: {'email': email.trim()},
      allowNotFound: true,
    );
    if (raw == null) return null;
    return SharedAccount.fromJson(_map(raw));
  }
}
