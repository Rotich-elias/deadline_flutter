import 'package:deadline/utils/rich_text.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

TextSpan _span(
  String text, {
  required List<String> urls,
  required List<String> wikis,
}) =>
    buildRichSpan(
      text,
      base: const TextStyle(fontSize: 14),
      highlight: Colors.amber,
      bullet: Colors.grey,
      onUrlTap: urls.add,
      onWikiTap: wikis.add,
    );

List<TextSpan> _links(TextSpan span) => span.children!
    .whereType<TextSpan>()
    .where((child) => child.recognizer != null)
    .toList();

void _tap(TextSpan span) => (span.recognizer! as TapGestureRecognizer).onTap!();

void main() {
  test('http(s) addresses in note text become tappable links', () {
    final urls = <String>[];
    final span =
        _span('See https://example.com/a?b=1 now', urls: urls, wikis: const []);

    final links = _links(span);
    expect(links, hasLength(1));
    expect(links.single.text, 'https://example.com/a?b=1');
    _tap(links.single);
    expect(urls, ['https://example.com/a?b=1']);
  });

  test('trailing punctuation is not swallowed by a link', () {
    final urls = <String>[];
    final span =
        _span('Visit https://example.com/x.', urls: urls, wikis: const []);

    expect(_links(span).single.text, 'https://example.com/x');
  });

  test('inline wiki links are tappable and hide the tasks: routing hint', () {
    final urls = <String>[];
    final wikis = <String>[];
    final span = _span('Read [[tasks:Pay rent]] and [[Ideas]]',
        urls: urls, wikis: wikis);

    final links = _links(span);
    expect(links.map((s) => s.text), ['Pay rent', 'Ideas']);
    for (final link in links) {
      _tap(link);
    }
    expect(wikis, ['tasks:Pay rent', 'Ideas']);
    expect(urls, isEmpty);
  });

  test('markup around a link keeps both the formatting and the tap target', () {
    final urls = <String>[];
    final span =
        _span('<b>Source</b> https://example.com', urls: urls, wikis: const []);

    expect(span.children!.whereType<TextSpan>().first.text, 'Source');
    expect(_links(span).single.text, 'https://example.com');
  });
}
