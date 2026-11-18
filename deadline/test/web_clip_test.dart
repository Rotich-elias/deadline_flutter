import 'package:deadline/utils/web_clip.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

Future<http.Response> _html(String body, {int status = 200}) async =>
    http.Response(
      body,
      status,
      headers: {'content-type': 'text/html; charset=utf-8'},
    );

Future<WebClip?> _clip(
  String html, {
  Uri? uri,
}) =>
    WebClipper.clip(
      (uri ?? Uri.https('example.com', '/post')).toString(),
      fetcher: (_) => _html(html),
    );

void main() {
  group('WebClipper.clip', () {
    test('extracts title, body, site name and canonical URL', () async {
      final clip = await _clip('''
        <html><head>
          <title>Weekend plans</title>
          <meta property="og:site_name" content="Example Journal">
          <link rel="canonical" href="/posts/weekend">
        </head><body><p>Paint the kitchen.</p></body></html>
      ''');

      expect(clip, isNotNull);
      expect(clip!.title, 'Weekend plans');
      expect(clip.body, 'Paint the kitchen.');
      expect(clip.siteName, 'Example Journal');
      expect(clip.url, 'https://example.com/posts/weekend');
    });

    test('HTML-decodes entities in title and body', () async {
      final clip = await _clip('''
        <html><head><title>Tom &amp; Jerry &quot;live&quot; &#39;here&#39;</title></head>
        <body><p>Keep &lt;strong&gt; &nbsp; simple &amp; clear</p></body></html>
      ''');

      expect(clip!.title, "Tom & Jerry \"live\" 'here'");
      expect(clip.body, 'Keep <strong> simple & clear');
    });

    test('strips script and style contents, including their text', () async {
      final clip = await _clip('''
        <html><head>
          <style>.secret { color: red; }</style>
          <script>var password = 'nope';</script>
          <title>Visible</title>
        </head><body>
          <p>Real text</p><script>alert('bad')</script>
        </body></html>
      ''');

      expect(clip!.title, 'Visible');
      expect(clip.body, 'Real text');
      expect(clip.body, isNot(contains('password')));
      expect(clip.body, isNot(contains('alert')));
      expect(clip.body, isNot(contains('color')));
    });

    test('turns paragraphs, line breaks, lists and headings into newlines',
        () async {
      final clip = await _clip('''
        <html><body>
          <h1>Diary</h1>
          <p>First paragraph<br>second line</p>
          <p>Second paragraph</p>
          <ul><li>Alpha</li><li>Beta</li></ul>
        </body></html>
      ''');

      expect(
          clip!.body,
          'Diary\nFirst paragraph\nsecond line\n'
          'Second paragraph\nAlpha\nBeta');
    });

    test('rejects non-http schemes and malformed URLs without fetching', () {
      var fetched = false;
      for (final url in [
        'ftp://example.com/a',
        'file:///tmp/a.html',
        'not a url',
        '',
      ]) {
        WebClipper.clip(
          url,
          fetcher: (uri) {
            fetched = true;
            return _html('<title>x</title>');
          },
        );
      }
      expect(fetched, isFalse);
    });

    test('returns null for non-2xx responses', () async {
      for (final status in [301, 404, 500]) {
        final clip = await WebClipper.clip(
          'https://example.com/a',
          fetcher: (_) => _html('<title>Ignored</title>', status: status),
        );
        expect(clip, isNull, reason: '$status');
      }
    });

    test('returns null when both title and body are empty', () async {
      expect(await _clip('<html><body><div>  </div></body></html>'), isNull);
      expect(await _clip(''), isNull);
    });

    test('falls back to og:title and meta description', () async {
      final clip = await _clip('''
        <html><head>
          <meta property="og:title" content="Open graph title">
          <meta name="description" content="A short summary &amp; more">
        </head><body></body></html>
      ''');

      expect(clip!.title, 'Open graph title');
      expect(clip.body, 'A short summary & more');
    });

    test('never throws when the fetcher fails or HTML is garbled', () async {
      final failed = await WebClipper.clip(
        'https://example.com/a',
        fetcher: (_) => throw StateError('offline'),
      );
      expect(failed, isNull);

      final garbled =
          await _clip('<title>Partial</title><p>unclosed <div>text');
      expect(garbled, isNotNull);
      expect(garbled!.title, isNotEmpty);
    });

    test('caps long bodies at 4000 characters', () async {
      final clip = await _clip('<p>${'word ' * 1200}</p>');
      final length = clip?.body.length ?? 0;
      expect(length, greaterThanOrEqualTo(3900));
      expect(length, lessThanOrEqualTo(4000));
    });
  });

  group('WebClipper.fromPastedText', () {
    test('uses the first non-empty line as title and keeps all text as body',
        () {
      final clip = WebClipper.fromPastedText(
        '\n  \n  Groceries   for   dinner  \nMilk\nEggs\n',
        url: 'https://example.com/note',
      );

      expect(clip, isNotNull);
      expect(clip!.title, 'Groceries for dinner');
      expect(clip.body, 'Groceries for dinner\nMilk\nEggs');
      expect(clip.url, 'https://example.com/note');
    });

    test('returns null for blank text or an invalid URL', () {
      expect(WebClipper.fromPastedText('  \n\n '), isNull);
      expect(
        WebClipper.fromPastedText('hello', url: 'ftp://example.com'),
        isNull,
      );
    });
  });
}
