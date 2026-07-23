class SyncResponse<T> {
  SyncResponse({required this.serverTime, required this.items});
  final DateTime serverTime;
  final List<T> items;
}

class ApiException implements Exception {
  ApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Somewhere to push local changes and pull back whatever changed elsewhere.
/// Implemented by [ApiClient] (a Laravel server) and [DriveBackend] (a JSON
/// file in the user's Google Drive appDataFolder) for both Tasks and Notes —
/// [SyncService] doesn't care which backend or which entity it's carrying.
abstract class SyncBackend<T> {
  Future<SyncResponse<T>> sync({required List<T> changes, DateTime? since});
}
