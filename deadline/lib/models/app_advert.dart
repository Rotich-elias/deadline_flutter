/// One popup advert published in the Teto admin console.
///
/// Only the fields needed to render the popup are sent to the app; scheduling
/// is enforced by the website, so the app never has to interpret dates.
class AppAdvert {
  const AppAdvert({
    required this.id,
    required this.title,
    required this.body,
    this.imageUrl,
    this.ctaLabel,
    this.ctaUrl,
  });

  final String id;
  final String title;
  final String body;
  final String? imageUrl;
  final String? ctaLabel;
  final String? ctaUrl;

  /// The stable identity used to remember that this advert was shown.
  String get key => id;

  bool get hasImage => _isWebUrl(imageUrl);

  bool get hasCta => _isWebUrl(ctaUrl);

  String get buttonLabel {
    final label = ctaLabel?.trim() ?? '';
    return label.isEmpty ? 'Learn more' : label;
  }

  static bool _isWebUrl(String? value) {
    if (value == null || value.trim().isEmpty) return false;
    final uri = Uri.tryParse(value.trim());
    return uri != null &&
        (uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.host.isNotEmpty;
  }

  static String? _text(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// Returns null for malformed entries so one bad advert cannot break a feed.
  static AppAdvert? tryFromJson(Object? value) {
    if (value is! Map<String, dynamic>) return null;

    final id = _text(value['id']);
    final title = _text(value['title']);
    final body = _text(value['body']);
    if (id == null || title == null || body == null) return null;

    return AppAdvert(
      id: id,
      title: title,
      body: body,
      imageUrl: _text(value['imageUrl']),
      ctaLabel: _text(value['ctaLabel']),
      ctaUrl: _text(value['ctaUrl']),
    );
  }
}
