import 'package:http/http.dart' as http;

/// A readable snippet taken from a web page or from text the user pasted.
class WebClip {
  const WebClip({
    required this.url,
    required this.title,
    required this.body,
    this.siteName,
  });

  final String url;
  final String title;
  final String body;
  final String? siteName;

  @override
  String toString() => 'WebClip(url: $url, title: $title, '
      'body: ${body.length} chars, siteName: $siteName)';
}

/// Fetches a page and reduces it to a title, a short body and a site name.
///
/// Deliberately forgiving: broken markup and network errors yield either a
/// best-effort [WebClip] or `null`, never an exception in calling code.
class WebClipper {
  WebClipper._();

  static const int _maxBodyLength = 4000;

  static Future<WebClip?> clip(
    String url, {
    Future<http.Response> Function(Uri)? fetcher,
    Duration timeout = const Duration(seconds: 12),
  }) async {
    final uri = _httpUri(url);
    if (uri == null) return null;

    final http.Response response;
    try {
      final load = fetcher ?? (uri) => http.get(uri);
      response = await load(uri).timeout(timeout);
    } catch (_) {
      return null;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) return null;

    try {
      return _parse(uri, response.body);
    } catch (_) {
      // Malformed HTML must not break the caller.
      return null;
    }
  }

  /// Turns pasted text into a clip: the first non-empty line is the title and
  /// the whole (tidied) text is kept as the body.
  static WebClip? fromPastedText(String text, {String? url}) {
    if (url != null && _httpUri(url) == null) return null;

    final decoded =
        _decode(text).replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final lines = decoded
        .split('\n')
        .map(_tidyLine)
        .where((line) => line.isNotEmpty)
        .toList();
    if (lines.isEmpty) return null;

    final body = lines.join('\n');
    return WebClip(
      url: url ?? '',
      title: lines.first,
      body: _cap(body),
    );
  }

  static Uri? _httpUri(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null || !uri.isAbsolute || uri.host.isEmpty) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    return uri;
  }

  static WebClip? _parse(Uri requested, String html) {
    final title = _cleanTag(_tagBody(html, 'title')) ??
        _cleanTag(_meta(html, 'og:title'));
    final description = _cleanTag(_meta(html, 'description')) ??
        _cleanTag(_meta(html, 'og:description'));
    final body = _bodyText(html, fallback: description ?? '');
    if ((title == null || title.isEmpty) && body.isEmpty) return null;

    final siteName = _cleanTag(_meta(html, 'og:site_name')) ??
        _cleanTag(_meta(html, 'application-name'));
    final canonical = _canonical(requested, html);

    return WebClip(
      url: canonical?.toString() ?? requested.toString(),
      title: title ?? '',
      body: _cap(body),
      siteName: siteName,
    );
  }

  static String? _tagBody(String html, String tag) {
    final match = RegExp(
      r'<' + tag + r'\b[^>]*>(.*?)</' + tag + r'\s*>',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(html);
    return match?.group(1);
  }

  /// Finds the `content` of a `<meta>` tag addressed by `name`, `property` or
  /// `itemprop`. Quoting is optional in the wild, so accept all three forms.
  static String? _meta(String html, String key) {
    for (final match
        in RegExp(r'<meta\b[^>]*>', caseSensitive: false).allMatches(html)) {
      final attrs = _attributes(match.group(0)!);
      final name =
          (attrs['name'] ?? attrs['property'] ?? attrs['itemprop'] ?? '')
              .toLowerCase();
      if (name != key.toLowerCase()) continue;
      final content = attrs['content'];
      if (content != null && content.trim().isNotEmpty) return content;
    }
    return null;
  }

  static Map<String, String> _attributes(String tag) {
    final attrs = <String, String>{};
    final pattern = RegExp(
      r'''([\w:-]+)\s*=\s*("([^"]*)"|'([^']*)'|([^\s"'>]+))''',
    );
    for (final match in pattern.allMatches(tag)) {
      attrs.putIfAbsent(
        match.group(1)!.toLowerCase(),
        () => match.group(3) ?? match.group(4) ?? match.group(5) ?? '',
      );
    }
    return attrs;
  }

  static Uri? _canonical(Uri base, String html) {
    for (final match
        in RegExp(r'<link\b[^>]*>', caseSensitive: false).allMatches(html)) {
      final attrs = _attributes(match.group(0)!);
      final rel = attrs['rel']?.toLowerCase().split(RegExp(r'\s+')) ?? const [];
      if (!rel.contains('canonical')) continue;
      final href = attrs['href'];
      if (href == null || href.trim().isEmpty) continue;
      try {
        final resolved = base.resolve(href.trim());
        if ((resolved.scheme == 'http' || resolved.scheme == 'https') &&
            resolved.host.isNotEmpty) {
          return resolved;
        }
      } catch (_) {
        // Ignore a broken canonical link and keep the requested URL.
      }
    }
    return null;
  }

  static String _bodyText(String html, {required String fallback}) {
    var text = html.replaceAll(
      RegExp(r'<!--.*?-->', caseSensitive: false, dotAll: true),
      ' ',
    );
    for (final tag in const [
      'script',
      'style',
      'noscript',
      'template',
      'svg',
    ]) {
      text = text.replaceAll(
        RegExp(
          r'<' + tag + r'\b[^>]*>.*?</' + tag + r'\s*>',
          caseSensitive: false,
          dotAll: true,
        ),
        ' ',
      );
    }
    final body = RegExp(
      r'<body\b[^>]*>(.*?)</body\s*>',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(text);
    if (body != null) text = body.group(1)!;

    text = text.replaceAll(
      RegExp(r'<(br|hr)\b[^>]*>', caseSensitive: false),
      '\n',
    );
    text = text.replaceAll(
      RegExp(
        r'</?(p|div|li|ul|ol|h[1-6]|blockquote|tr|table|section|article|pre)\b[^>]*>',
        caseSensitive: false,
      ),
      '\n',
    );
    text = text.replaceAll(RegExp(r'<[^>]*>', dotAll: true), '');
    text = _decode(text);

    final lines = text
        .split('\n')
        .map(_tidyLine)
        .where((line) => line.isNotEmpty)
        .toList();
    final readable = lines.join('\n');
    return readable.isEmpty ? _tidyLine(_decode(fallback)) : readable;
  }

  static String? _cleanTag(String? value) {
    if (value == null) return null;
    final cleaned = _tidyLine(_decode(value));
    return cleaned.isEmpty ? null : cleaned;
  }

  static String _tidyLine(String value) =>
      value.replaceAll(RegExp(r'\s+'), ' ').trim();

  static String _decode(String value) {
    var text = value;
    text = text.replaceAllMapped(
      RegExp(r'&#x([0-9a-fA-F]+);?'),
      (m) => _charFromCode(int.tryParse(m.group(1)!, radix: 16), m.group(0)!),
    );
    text = text.replaceAllMapped(
      RegExp(r'&#([0-9]+);?'),
      (m) => _charFromCode(int.tryParse(m.group(1)!), m.group(0)!),
    );
    text = text
        .replaceAll(RegExp(r'&nbsp;?', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'&lt;?', caseSensitive: false), '<')
        .replaceAll(RegExp(r'&gt;?', caseSensitive: false), '>')
        .replaceAll(RegExp(r'&quot;?', caseSensitive: false), '"')
        .replaceAll(RegExp(r'&(?:apos|#39);?', caseSensitive: false), "'")
        // Ampersand last so `&amp;lt;` stays a literal `&lt;`.
        .replaceAll(RegExp(r'&amp;?', caseSensitive: false), '&');
    return text;
  }

  static String _charFromCode(int? code, String original) {
    if (code == null || code < 0 || code > 0x10ffff) return original;
    try {
      return String.fromCharCode(code);
    } catch (_) {
      return original;
    }
  }

  static String _cap(String body) => body.length <= _maxBodyLength
      ? body
      : body.substring(0, _maxBodyLength).trimRight();
}
