import 'package:flutter/services.dart';

/// A camera failure reported explicitly by the Android bridge.
class CameraCaptureException implements Exception {
  const CameraCaptureException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// A permission/bridge error reported explicitly by Android.
///
/// These are thrown rather than returned as null/false/empty so a revoked
/// permission cannot masquerade as "no result" in the UI.
class BridgeException implements Exception {
  const BridgeException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => message;
}

/// Thin Dart wrapper over the small Android bridge in MainActivity.kt.
///
/// Calls return null/false/empty when the platform does not implement the
/// channel (tests, unsupported platforms). A permission refusal or a native
/// failure is reported as a [BridgeException] so the UI can show the reason.
class PlatformBridge {
  static const MethodChannel _channel = MethodChannel('deadline/platform');

  static Future<String?> _string(String method, [Object? arg]) async {
    try {
      return await _channel.invokeMethod<String>(method, arg);
    } on MissingPluginException {
      return null;
    } on PlatformException catch (e) {
      throw BridgeException(
          e.code, e.message ?? 'The device could not complete this action.');
    }
  }

  static Future<bool> _bool(String method, [Object? arg]) async {
    try {
      return await _channel.invokeMethod<bool>(method, arg) ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException catch (e) {
      throw BridgeException(
          e.code, e.message ?? 'The device could not complete this action.');
    }
  }

  /// Take a photo with the system camera and get a JPEG path in app storage.
  /// Native errors are thrown as [CameraCaptureException] so the form can show
  /// them instead of treating an error string as a file path.
  static Future<String?> capturePhoto() async {
    try {
      return await _channel.invokeMethod<String>('capturePhoto');
    } on MissingPluginException {
      return null;
    } on PlatformException catch (e) {
      throw CameraCaptureException(e.message ?? 'The camera could not open.');
    }
  }

  /// Path left by a capture whose activity was destroyed before Dart received
  /// the method-channel result. Consumes the pending path exactly once.
  static Future<String?> takePendingCapture() => _string('takePendingCapture');

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
    } on MissingPluginException {
      return null;
    } on PlatformException catch (e) {
      throw BridgeException(
          e.code, e.message ?? 'Your location could not be read.');
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
    } on MissingPluginException {
      return const [];
    } on PlatformException catch (e) {
      throw BridgeException(
          e.code, e.message ?? 'The device calendar could not be read.');
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
