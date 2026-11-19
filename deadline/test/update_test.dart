import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;

import 'package:deadline/models/app_update.dart';
import 'package:deadline/services/update_service.dart';
import 'package:deadline/theme.dart';
import 'package:deadline/ui/about_page.dart';

const _url = 'https://www.teto.co.ke/download/deadlines-notes';

class _MemoryStore implements UpdateFingerprintStore {
  final values = <String, String>{};

  @override
  Future<String?> read(String url) async => values[url];

  @override
  Future<void> write(String url, String fingerprint) async =>
      values[url] = fingerprint;
}

class _FakeServer {
  _FakeServer(this.statusCode, this.headers);

  final int statusCode;
  final Map<String, String> headers;
  final methods = <String>[];

  http.Client get client => http_testing.MockClient((request) async {
        methods.add(request.method);
        return http.Response('', statusCode, headers: headers);
      });
}

void main() {
  group('AppUpdate', () {
    test('compares dotted versions and ignores build suffixes', () {
      expect(AppUpdate.compareVersions('1.0.24', '1.0.25'), -1);
      expect(AppUpdate.compareVersions('1.0.25', '1.0.24'), 1);
      expect(AppUpdate.compareVersions('1.0.24+25', '1.0.24'), 0);
      expect(AppUpdate.compareVersions('v2.0', '1.9.9'), 1);
    });

    test('falls back to a generic label when no version is known', () {
      const update = AppUpdate(url: _url);
      expect(update.displayVersion, 'Latest available');
      expect(update.isNewerThan('1.0.24'), isTrue);
      expect(update.updateKey, _url);
    });

    test('update identity defaults to the published version when present', () {
      const update = AppUpdate(latestVersion: '1.0.25', url: _url);
      expect(update.updateKey, '1.0.25');

      const fingerprinted = AppUpdate(url: _url, updateKey: '"etag"');
      expect(fingerprinted.updateKey, '"etag"');
    });

    test('uses a version parsed from the download filename when present', () {
      const update = AppUpdate(latestVersion: '1.0.25', url: _url);
      expect(update.displayVersion, '1.0.25');
      expect(update.isNewerThan('1.0.24+25'), isTrue);
      expect(update.isNewerThan('1.0.25'), isFalse);
    });
  });

  group('UpdateService', () {
    test('first check records a baseline without prompting', () async {
      final store = _MemoryStore();
      final server = _FakeServer(200, {'etag': '"v1"'});
      final service =
          UpdateService(url: _url, client: server.client, store: store);

      expect(await service.check('1.0.24'), isNull);
      expect(store.values[_url], '"v1"');
      expect(server.methods, ['HEAD']);
    });

    test('an unchanged APK stays silent', () async {
      final store = _MemoryStore();
      final first = _FakeServer(200, {'etag': '"v1"'});
      await UpdateService(url: _url, client: first.client, store: store)
          .check('1.0.24');

      final second = _FakeServer(200, {'etag': '"v1"'});
      expect(
        await UpdateService(url: _url, client: second.client, store: store)
            .check('1.0.24'),
        isNull,
      );
    });

    test('a changed APK offers the download URL', () async {
      final store = _MemoryStore();
      final first = _FakeServer(200, {'etag': '"v1"'});
      await UpdateService(url: _url, client: first.client, store: store)
          .check('1.0.24');

      final changed = _FakeServer(200, {
        'ETag': '"v2"',
        'Last-Modified': 'Wed, 18 Nov 2026 12:00:00 GMT',
      });
      final update =
          await UpdateService(url: _url, client: changed.client, store: store)
              .check('1.0.24');

      expect(update, isNotNull);
      expect(update!.url, _url);
      expect(update.latestVersion, isNull);
      expect(store.values[_url], contains('"v2"'));
    });

    test('a versioned filename is detected on the first check', () async {
      const versioned = 'https://example.test/deadline-1.0.25.apk';
      final server = _FakeServer(200, {'content-length': '12345'});
      final update = await UpdateService(
        url: versioned,
        client: server.client,
        store: _MemoryStore(),
      ).check('1.0.24+25');

      expect(update?.latestVersion, '1.0.25');
    });

    test('the filename version wins over an unchanged fingerprint', () async {
      const versioned =
          'https://blob.example.test/deadline-1.0.25-abc123.apk?download=1';
      final store = _MemoryStore();
      final seen = _FakeServer(200, {'etag': '"v1"'});
      await UpdateService(
              url: versioned, client: seen.client, store: store)
          .check('1.0.24');

      // Same ETag, but the installed build is older than the version in the
      // filename, so the user should still be offered the update.
      final repeat = _FakeServer(200, {'etag': '"v1"'});
      final update = await UpdateService(
              url: versioned, client: repeat.client, store: store)
          .check('1.0.24');

      expect(update?.latestVersion, '1.0.25');
    });

    test('reads the version from Content-Disposition after a redirect',
        () async {
      // Dart's http client keeps response.request.url as the original URL
      // after a redirect, so the version only appears in this header.
      final headers = {
        'etag': '"v1"',
        'content-disposition':
            'attachment; filename="deadline-1.0.26-abc123.apk"',
      };
      final store = _MemoryStore();
      final service = UpdateService(
        url: _url,
        client: _FakeServer(200, headers).client,
        store: store,
      );

      final first = await service.check('1.0.25');
      expect(first?.latestVersion, '1.0.26');
      expect(first?.updateKey, '1.0.26');

      // A second check with the same fingerprint must still offer the update:
      // the installed version has not changed.
      final repeat = UpdateService(
        url: _url,
        client: _FakeServer(200, headers).client,
        store: store,
      );
      expect((await repeat.check('1.0.25'))?.latestVersion, '1.0.26');

      // Once installed, the same APK is no longer an update.
      final current = UpdateService(
        url: _url,
        client: _FakeServer(200, headers).client,
        store: store,
      );
      expect(await current.check('1.0.26'), isNull);
    });

    test('uses the version or APK fingerprint as the notification identity',
        () async {
      const versioned = 'https://example.test/deadline-1.0.25.apk';
      final versionedUpdate = await UpdateService(
        url: versioned,
        client: _FakeServer(200, {'etag': '"v1"'}).client,
        store: _MemoryStore(),
      ).check('1.0.24');
      expect(versionedUpdate?.updateKey, '1.0.25');

      final store = _MemoryStore()..values[_url] = '"v1"';
      final changed = _FakeServer(200, {
        'ETag': '"v2"',
        'Last-Modified': 'Wed, 18 Nov 2026 12:00:00 GMT',
      });
      final fingerprinted = await UpdateService(
              url: _url, client: changed.client, store: store)
          .check('1.0.24');
      expect(fingerprinted?.updateKey, contains('"v2"'));
    });

    test('server failures and missing headers stay silent', () async {
      final failing = _FakeServer(500, {'etag': '"v1"'});
      expect(
        await UpdateService(url: _url, client: failing.client, store: _MemoryStore())
            .check('1.0.24'),
        isNull,
      );

      final noHeaders = _FakeServer(200, const {});
      expect(
        await UpdateService(url: _url, client: noHeaders.client, store: _MemoryStore())
            .check('1.0.24'),
        isNull,
      );
    });
  });

  testWidgets('About page offers a changed APK and opens its URL',
      (tester) async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('deadline/platform'),
      (call) async {
        calls.add(call);
        switch (call.method) {
          case 'appVersion':
            return '1.0.24+25';
          case 'openUrl':
            return true;
          default:
            return null;
        }
      },
    );

    final store = _MemoryStore()..values[_url] = '"old"';
    final server = _FakeServer(200, {'etag': '"new"'});
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.dark),
      home: AboutPage(
        updateService:
            UpdateService(url: _url, client: server.client, store: store),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('about-update')));
    await tester.pumpAndSettle();

    expect(find.text('Update available'), findsOneWidget);
    expect(
      find.text('A new version of Deadlines&Notes is available.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Update'));
    await tester.pumpAndSettle();

    final opened = calls.where((c) => c.method == 'openUrl').toList();
    expect(opened, hasLength(1));
    expect(opened.single.arguments, _url);
  });
}
