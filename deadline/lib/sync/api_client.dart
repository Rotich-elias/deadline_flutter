import 'dart:convert';

import 'package:http/http.dart' as http;

import 'sync_backend.dart';

/// Talks to a single endpoint: POST {base}{path}. Send what changed locally,
/// get back what changed remotely. One instance per entity type (Task, Note),
/// each pointed at its own endpoint and given its own (de)serializers.
class ApiClient<T> implements SyncBackend<T> {
  ApiClient({
    required this.baseUrl,
    required this.token,
    required this.path,
    required this.toJson,
    required this.fromJson,
  });

  final String baseUrl;
  final String token;
  final String path;
  final Map<String, dynamic> Function(T) toJson;
  final T Function(Map<String, dynamic>) fromJson;

  @override
  Future<SyncResponse<T>> sync({
    required List<T> changes,
    DateTime? since,
  }) async {
    final uri =
        Uri.parse('${baseUrl.replaceAll(RegExp(r"/+$"), "")}$path');

    final res = await http
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({
            'since': since?.toUtc().toIso8601String(),
            'changes': changes.map(toJson).toList(),
          }),
        )
        .timeout(const Duration(seconds: 20));

    if (res.statusCode == 401) {
      throw ApiException('Token rejected. Check it in Settings.');
    }
    if (res.statusCode >= 400) {
      throw ApiException('Server returned ${res.statusCode}.');
    }

    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return SyncResponse(
      serverTime: DateTime.parse(body['server_time'] as String).toUtc(),
      items: (body['items'] as List)
          .map((e) => fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
