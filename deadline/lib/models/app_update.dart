/// A newly published APK discovered by watching the download URL.
///
/// There is no version API: the app only knows the file changed. When the URL
/// happens to contain a version (e.g. `deadline-1.0.25.apk`) we include it for
/// display; otherwise [latestVersion] is null and the prompt stays generic.
class AppUpdate {
  const AppUpdate({
    this.latestVersion,
    this.notes = '',
    required this.url,
  });

  final String? latestVersion;
  final String notes;
  final String url;

  String get displayVersion => latestVersion ?? 'Latest available';

  /// True when the discovered version is newer than the installed one.
  /// A null version means "the file changed", which is treated as new.
  bool isNewerThan(String currentVersion) {
    final version = latestVersion;
    return version == null || version.isEmpty ||
        compareVersions(currentVersion, version) < 0;
  }

  /// Compares dotted version strings such as `1.0.24` or `1.0.24+25`.
  /// Returns -1 when [a] is older, 1 when newer, 0 when equal. Unknown
  /// segments count as 0, so unusual labels never crash the check.
  static int compareVersions(String a, String b) {
    final left = _segments(a);
    final right = _segments(b);
    final length = left.length > right.length ? left.length : right.length;
    for (var i = 0; i < length; i++) {
      final l = i < left.length ? left[i] : 0;
      final r = i < right.length ? right[i] : 0;
      if (l != r) return l < r ? -1 : 1;
    }
    return 0;
  }

  static List<int> _segments(String version) {
    final release = version.trim().replaceFirst(RegExp(r'^[vV]'), '');
    // The build number after `+` (or a `-beta` suffix) is not part of the
    // public version: `1.0.24+25` and `1.0.24` are the same release.
    final withoutSuffix = release.split(RegExp(r'[+\-]')).first;
    return withoutSuffix
        .split('.')
        .map((part) => int.tryParse(part) ?? 0)
        .toList(growable: false);
  }
}
