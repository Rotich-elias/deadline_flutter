import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

/// Owns the app-lock state: the PIN (stored only as a salted hash), the
/// optional biometric toggle, and whether the app is currently locked.
///
/// Everything secret lives in Android's Keystore-backed secure storage. A
/// locked note's flag is *not* here; that is device-local data in the notes
/// table, so it survives restarts without ever being synced.
class AppLockService extends ChangeNotifier {
  AppLockService({
    FlutterSecureStorage? storage,
    LocalAuthentication? auth,
  })  : _storage = storage ?? const FlutterSecureStorage(),
        _auth = auth ?? LocalAuthentication();

  static const _keyEnabled = 'lock.enabled';
  static const _keyHash = 'lock.pin.hash';
  static const _keySalt = 'lock.pin.salt';
  static const _keyBiometric = 'lock.biometric';

  /// Iterated hashing makes a stolen PIN hash expensive to brute-force.
  static const _iterations = 40000;

  /// Four digits keeps unlocking quick with one thumb; the hash above is what
  /// makes a 10,000-combination PIN non-trivial to recover offline.
  static const int pinLength = 4;

  static const _secureChannel = MethodChannel('deadline/security');

  final FlutterSecureStorage _storage;
  final LocalAuthentication _auth;

  bool _enabled = false;
  bool _locked = false;
  bool _biometricEnabled = false;
  bool _biometricsAvailable = false;
  String? _hash;
  String? _salt;

  bool get enabled => _enabled;
  bool get locked => _locked;
  bool get biometricEnabled => _biometricEnabled;
  bool get biometricsAvailable => _biometricsAvailable;

  /// Reads the saved settings and locks the app immediately when app lock is
  /// on, so a cold start never paints the lists before the PIN screen.
  Future<void> load() async {
    try {
      _enabled = (await _storage.read(key: _keyEnabled)) == 'true';
      _hash = await _storage.read(key: _keyHash);
      _salt = await _storage.read(key: _keySalt);
      _biometricEnabled = (await _storage.read(key: _keyBiometric)) == 'true';
    } catch (e) {
      // Secure storage can be unavailable on an unusual device. Failing open
      // would expose the app, so treat it as "lock not configured".
      debugPrint('Could not read app lock settings: $e');
      _enabled = false;
    }

    if (_hash == null || _salt == null) _enabled = false;
    if (_enabled) {
      _locked = true;
      await _refreshBiometrics();
      await _applySecureScreen(true);
    }
    notifyListeners();
  }

  /// Turns app lock on without locking the current session. The lock takes
  /// effect the next time the app leaves the foreground.
  Future<void> enable(String pin) async {
    final salt = _newSalt();
    final hash = hashPin(pin, salt);
    _salt = salt;
    _hash = hash;
    _enabled = true;
    _locked = false;

    await _write(_keySalt, salt);
    await _write(_keyHash, hash);
    await _write(_keyEnabled, 'true');

    await _refreshBiometrics();
    await _applySecureScreen(true);
    notifyListeners();
  }

  /// Replaces the PIN after checking the current one.
  Future<bool> changePin(String currentPin, String newPin) async {
    if (!await verifyPin(currentPin)) return false;
    final salt = _newSalt();
    final hash = hashPin(newPin, salt);
    _salt = salt;
    _hash = hash;
    await _write(_keySalt, salt);
    await _write(_keyHash, hash);
    notifyListeners();
    return true;
  }

  /// Turns app lock off. Callers are responsible for clearing note locks,
  /// because a note lock without an app lock would have no way to unlock it.
  Future<bool> disable(String pin) async {
    if (!await verifyPin(pin)) return false;
    _enabled = false;
    _locked = false;
    _biometricEnabled = false;
    _hash = null;
    _salt = null;

    await _delete(_keyEnabled);
    await _delete(_keyHash);
    await _delete(_keySalt);
    await _delete(_keyBiometric);

    await _applySecureScreen(false);
    notifyListeners();
    return true;
  }

  Future<bool> verifyPin(String pin) async {
    final salt = _salt;
    final hash = _hash;
    if (salt == null || hash == null) return false;
    return _constantTimeEquals(hashPin(pin, salt), hash);
  }

  Future<void> setBiometricEnabled(bool value) async {
    if (!_enabled || (value && !_biometricsAvailable)) return;
    _biometricEnabled = value;
    await _write(_keyBiometric, value ? 'true' : 'false');
    notifyListeners();
  }

  /// Shows the system biometric prompt. Returns false when biometrics are off,
  /// unavailable, cancelled, or repeatedly rejected.
  Future<bool> authenticateBiometric(
      {String reason = 'Unlock Deadlines&Notes'}) async {
    if (!_biometricEnabled || !_biometricsAvailable) return false;
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
    } on PlatformException catch (e) {
      debugPrint('Biometric authentication failed: ${e.message}');
      return false;
    }
  }

  /// Locks the UI while keeping the app process alive, e.g. when the user
  /// leaves the app or taps "Lock now".
  void lockNow() {
    if (!_enabled || _locked) return;
    _locked = true;
    notifyListeners();
  }

  void unlock() {
    if (!_locked) return;
    _locked = false;
    notifyListeners();
  }

  /// Called from the app's lifecycle observer. Backgrounding the app locks it
  /// so the next launch shows the PIN screen. Biometric prompts and system
  /// dialogs only take the app to `inactive`, so they do not lock it.
  void handleLifecycle(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      lockNow();
    }
  }

  Future<void> _refreshBiometrics() async {
    try {
      _biometricsAvailable =
          await _auth.canCheckBiometrics && await _auth.isDeviceSupported();
    } catch (e) {
      debugPrint('Could not query biometrics: $e');
      _biometricsAvailable = false;
    }
    if (!_biometricsAvailable && _biometricEnabled) {
      _biometricEnabled = false;
      await _write(_keyBiometric, 'false');
    }
  }

  Future<void> _applySecureScreen(bool enabled) async {
    try {
      await _secureChannel
          .invokeMethod<void>('setSecureScreen', {'enabled': enabled});
    } catch (e) {
      // Missing on tests and non-Android hosts; the app still works.
      debugPrint('Secure screen unavailable: $e');
    }
  }

  Future<void> _write(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
    } catch (e) {
      debugPrint('Could not save app lock setting $key: $e');
    }
  }

  Future<void> _delete(String key) async {
    try {
      await _storage.delete(key: key);
    } catch (e) {
      debugPrint('Could not clear app lock setting $key: $e');
    }
  }

  static String _newSalt() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return base64UrlEncode(bytes);
  }

  /// Salted, iterated SHA-256. Exposed for tests; the plain PIN is never
  /// written anywhere.
  static String hashPin(String pin, String salt) {
    var digest = sha256.convert(utf8.encode('$salt:$pin'));
    for (var i = 1; i < _iterations; i++) {
      digest = sha256.convert(digest.bytes);
    }
    return digest.toString();
  }

  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}
