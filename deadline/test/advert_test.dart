import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;

import 'package:deadline/models/app_advert.dart';
import 'package:deadline/services/advert_service.dart';

const _url = 'https://www.teto.co.ke/api/adverts?app=deadlines-notes';

const _first = {
  'id': '1',
  'title': 'New planner available',
  'body': 'Try the updated study planner.',
  'imageUrl': 'https://store123.public.blob.vercel-storage.com/images/banner.png',
  'ctaLabel': 'Read more',
  'ctaUrl': 'https://teto.co.ke/products',
};

const _second = {
  'id': '2',
  'title': 'Exam tips',
  'body': 'A short guide is ready.',
};

class _MemorySeenStore implements AdvertSeenStore {
  final ids = <String>{};

  @override
  Future<bool> isSeen(String id) async => ids.contains(id);

  @override
  Future<void> markSeen(String id) async => ids.add(id);
}

http.Client _server(Object body, {int status = 200}) => http_testing.MockClient((request) async {
      return http.Response(
        jsonEncode(body),
        status,
        headers: {'content-type': 'application/json'},
      );
    });

void main() {
  group('AppAdvert', () {
    test('parses the public payload', () {
      final advert = AppAdvert.tryFromJson(_first)!;
      expect(advert.id, '1');
      expect(advert.title, 'New planner available');
      expect(advert.body, contains('study planner'));
      expect(advert.hasImage, isTrue);
      expect(advert.hasCta, isTrue);
      expect(advert.buttonLabel, 'Read more');
    });

    test('uses a default button label when none is published', () {
      final advert = AppAdvert.tryFromJson(_second)!;
      expect(advert.hasCta, isFalse);
      expect(advert.buttonLabel, 'Learn more');
    });

    test('rejects malformed entries and unsafe URLs', () {
      expect(AppAdvert.tryFromJson({'id': '1'}), isNull);
      expect(AppAdvert.tryFromJson('not json'), isNull);

      final unsafe = AppAdvert.tryFromJson({
        'id': '3',
        'title': 'Tap here',
        'body': 'Unsafe link',
        'ctaUrl': 'javascript:alert(1)',
        'imageUrl': 'file:///etc/passwd',
      })!;
      expect(unsafe.hasCta, isFalse);
      expect(unsafe.hasImage, isFalse);
    });
  });

  group('AdvertService', () {
    test('returns unseen adverts in feed order', () async {
      final service = AdvertService(
        url: _url,
        client: _server({'adverts': [_first, _second]}),
        store: _MemorySeenStore(),
      );

      final adverts = await service.check('1.0.29');
      expect(adverts.map((advert) => advert.id), ['1', '2']);
    });

    test('skips adverts the install has already seen', () async {
      final store = _MemorySeenStore();
      await store.markSeen('1');

      final service = AdvertService(
        url: _url,
        client: _server({'adverts': [_first, _second]}),
        store: store,
      );

      final adverts = await service.check('1.0.29');
      expect(adverts.map((advert) => advert.id), ['2']);
    });

    test('marks an advert as seen only when told to', () async {
      final store = _MemorySeenStore();
      final service = AdvertService(
        url: _url,
        client: _server({'adverts': [_first]}),
        store: store,
      );

      expect(await service.check('1.0.29'), hasLength(1));
      expect(store.ids, isEmpty);
      expect(await service.check('1.0.29'), hasLength(1));

      await service.markSeen(const AppAdvert(id: '1', title: 't', body: 'b'));
      expect(await service.check('1.0.29'), isEmpty);
    });

    test('sends a versioned user agent on a GET request', () async {
      String? method;
      String? agent;
      final client = http_testing.MockClient((request) async {
        method = request.method;
        agent = request.headers['user-agent'];
        return http.Response(jsonEncode({'adverts': []}), 200);
      });

      await AdvertService(url: _url, client: client, store: _MemorySeenStore())
          .check('1.0.29');

      expect(method, 'GET');
      expect(agent, 'DeadlinesNotes/1.0.29');
    });

    test('ignores broken feeds and server errors', () async {
      final bad = AdvertService(
        url: _url,
        client: _server({'adverts': [{'id': 'x'}, _first]}),
        store: _MemorySeenStore(),
      );
      final adverts = await bad.check('1.0.29');
      expect(adverts.map((advert) => advert.id), ['1']);

      final failed = AdvertService(
        url: _url,
        client: _server({'error': 'down'}, status: 500),
        store: _MemorySeenStore(),
      );
      expect(await failed.check('1.0.29'), isEmpty);

      final wrongShape = AdvertService(
        url: _url,
        client: _server('<html></html>'),
        store: _MemorySeenStore(),
      );
      expect(await wrongShape.check('1.0.29'), isEmpty);
    });
  });
}
