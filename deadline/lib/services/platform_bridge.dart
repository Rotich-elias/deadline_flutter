import 'package:flutter/services.dart';

/// Thin Dart wrapper over the small Android bridge in MainActivity.kt.
///
/// Every method is optional: on unsupported platforms or when a permission is
/// denied the calls return null/false rather than throwing, so the UI can
/// simply hide or explain the feature.
class PlatformBridge {
  static const MethodChannel _channel = MethodChannel('deadline/platform');

  static Future<String?> _string(String method, [Object? arg]) async {
    try {
      return await _channel.invokeMethod<String>(method, arg);
    } on PlatformException catch (e) {
      return e.message;
    } catch (_) {
      return null;
    }
  }

  static Future<bool> _bool(String method, [Object? arg]) async {
    try {
      return await _channel.invokeMethod<bool>(method, arg) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Take a photo with the system camera and get a JPEG path in app storage.
  static Future<String?> capturePhoto() => _string('capturePhoto');

  /// Start/stop a voice memo. Both return the finished file path (stop) or a
  /// placeholder path (start, so the UI can show "Recording…").
  static Future<String?> startAudioRecording() =>
      _string('startAudioRecording');
  static Future<String?> stopAudioRecording() => _string('stopAudioRecording');

  /// Android's on-device speech recognizer; returns the best transcript.
  static Future<String?> transcribe() => _string('transcribe');

  static Future<Map<String, double>?> currentLocation() async {
    try {
      final raw =
          await _channel.invokeMapMethod<String, Object>('currentLocation');
      if (raw == null) return null;
      final lat = (raw['latitude'] as num?)?.toDouble();
      final lon = (raw['longitude'] as num?)?.toDouble();
      if (lat == null || lon == null) return null;
      return {'latitude': lat, 'longitude': lon};
    } catch (_) {
      return null;
    }
  }

  static Future<bool> addProximityAlert({
    required String id,
    required double latitude,
    required double longitude,
    required double radiusMeters,
    required String label,
  }) =>
      _bool('addProximityAlert', {
        'id': id,
        'latitude': latitude,
        'longitude': longitude,
        'radiusMeters': radiusMeters,
        'label': label,
      });

  static Future<bool> clearProximityAlerts([List<String>? ids]) =>
      _bool('clearProximityAlerts', ids == null ? null : {'ids': ids});

  /// Events from the device's calendars, for two-way calendar sync.
  static Future<List<Map<String, dynamic>>> calendarEvents({
    required DateTime from,
    required DateTime to,
  }) async {
    try {
      final raw = await _channel.invokeListMethod<Map<dynamic, dynamic>>(
        'calendarEvents',
        {
          'from': from.millisecondsSinceEpoch,
          'to': to.millisecondsSinceEpoch,
        },
      );
      return [
        for (final item in raw ?? const [])
          Map<String, dynamic>.from(item.map((k, v) => MapEntry('$k', v))),
      ];
    } catch (_) {
      return const [];
    }
  }

  static Future<bool> addCalendarEvent({
    required String title,
    required DateTime start,
    int durationMinutes = 60,
  }) =>
      _bool('addCalendarEvent', {
        'title': title,
        'start': start.millisecondsSinceEpoch,
        'durationMinutes': durationMinutes,
      });

  /// Installed version from Android's package manager, e.g. `1.0.20+21`.
  static Future<String?> appVersion() async {
    try {
      return await _channel.invokeMethod<String>('appVersion');
    } catch (_) {
      return null;
    }
  }

  /// Opens an http(s) URL in the phone's browser. Returns false when no
  /// browser is installed so the caller can show the URL as plain text.
  static Future<bool> openUrl(String url) => _bool('openUrl', url);

  /// True when this launch came from the "Quick note" home-screen shortcut.
  static Future<bool> takeQuickNote() => _bool('takeQuickNote');
}
