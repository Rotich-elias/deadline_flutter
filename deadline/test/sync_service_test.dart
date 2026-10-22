import 'package:deadline/sync/sync_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('validateServerUrl', () {
    test('accepts a plain HTTPS origin', () {
      expect(
          SyncService.validateServerUrl('https://tasks.example.com'), isNull);
      expect(
        SyncService.validateServerUrl('https://example.com/deadline'),
        isNull,
      );
    });

    test('rejects HTTP so the token is never sent in clear text', () {
      expect(
        SyncService.validateServerUrl('http://tasks.example.com'),
        contains('https'),
      );
    });

    test('rejects a bare host or garbage', () {
      expect(SyncService.validateServerUrl('tasks.example.com'), isNotNull);
      expect(SyncService.validateServerUrl(''), isNotNull);
    });

    test('rejects query strings and fragments', () {
      expect(
        SyncService.validateServerUrl('https://example.com?x=1'),
        isNotNull,
      );
      expect(
        SyncService.validateServerUrl('https://example.com#section'),
        isNotNull,
      );
    });
  });
}
