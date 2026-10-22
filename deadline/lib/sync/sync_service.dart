import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/local_db.dart';
import '../data/notes_store.dart';
import '../data/task_store.dart';
import '../models/note.dart';
import '../models/task.dart';
import '../services/notifications.dart';
import 'api_client.dart';
import 'drive_backend.dart';
import 'sync_backend.dart';

enum SyncState { off, idle, working, offline, failed }

/// Which backend, if any, [SyncService] pushes and pulls through.
enum SyncMethod { off, server, drive }

const _tasksDriveFile = 'deadline_sync.json';
const _notesDriveFile = 'deadline_notes.json';
const _tokenKey = 'sync.token';

/// Push local changes, pull remote ones, merge by newest-wins — for both
/// tasks and notes, over whichever backend is configured.
///
/// The app never waits on this. Everything works from the local database, and
/// sync is a background reconciliation that runs on launch, on resume, shortly
/// after any edit, and when the network comes back. The actual transport —
/// a Laravel server or a file in Google Drive — is a [SyncBackend]; this
/// class only knows about the reconciliation, not where the data goes.
class SyncService extends ChangeNotifier {
  SyncService(this._db, this._store, this._notesStore) {
    _store.onLocalChange = _scheduleDebounced;
    _notesStore.onLocalChange = _scheduleDebounced;
    _netSub = Connectivity().onConnectivityChanged.listen((results) {
      final online = results.any((r) => r != ConnectivityResult.none);
      if (online) syncNow();
    });
  }

  final LocalDb _db;
  final TaskStore _store;
  final NotesStore _notesStore;
  late final StreamSubscription _netSub;
  Timer? _debounce;

  final GoogleSignIn _googleSignIn = GoogleSignIn(scopes: driveScopes);
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  SyncMethod method = SyncMethod.off;
  String baseUrl = '';
  String token = '';
  GoogleSignInAccount? driveAccount;

  DateTime? lastSyncedAt;
  SyncState state = SyncState.off;
  String? lastError;

  bool get configured => switch (method) {
        SyncMethod.off => false,
        SyncMethod.server =>
          validateServerUrl(baseUrl) == null && token.isNotEmpty,
        SyncMethod.drive => driveAccount != null,
      };

  SyncBackend<Task>? get _taskBackend => switch (method) {
        SyncMethod.off => null,
        SyncMethod.server => ApiClient<Task>(
            baseUrl: baseUrl,
            token: token,
            path: '/api/tasks/sync',
            toJson: (t) => t.toJson(),
            fromJson: Task.fromJson,
          ),
        SyncMethod.drive => driveAccount == null
            ? null
            : DriveBackend<Task>(
                driveAccount!,
                fileName: _tasksDriveFile,
                toJson: (t) => t.toJson(),
                fromJson: Task.fromJson,
                idOf: (t) => t.id,
                updatedAtOf: (t) => t.updatedAt,
                isDeleted: (t) => t.deleted,
              ),
      };

  SyncBackend<Note>? get _noteBackend => switch (method) {
        SyncMethod.off => null,
        SyncMethod.server => ApiClient<Note>(
            baseUrl: baseUrl,
            token: token,
            path: '/api/notes/sync',
            toJson: (n) => n.toJson(),
            fromJson: Note.fromJson,
          ),
        SyncMethod.drive => driveAccount == null
            ? null
            : DriveBackend<Note>(
                driveAccount!,
                fileName: _notesDriveFile,
                toJson: (n) => n.toJson(),
                fromJson: Note.fromJson,
                idOf: (n) => n.id,
                updatedAtOf: (n) => n.updatedAt,
                isDeleted: (n) => n.deleted,
              ),
      };

  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    method = SyncMethod.values[prefs.getInt('sync.method') ?? 0];
    baseUrl = prefs.getString('sync.baseUrl') ?? '';

    // The token belongs in the platform keystore, not in SharedPreferences
    // (which Auto Backup / adb could read). Migrate one-time from the old key.
    final legacyToken = prefs.getString(_tokenKey) ?? '';
    try {
      var stored = await _secureStorage.read(key: _tokenKey) ?? '';
      if (stored.isEmpty && legacyToken.isNotEmpty) {
        await _secureStorage.write(key: _tokenKey, value: legacyToken);
        stored = legacyToken;
      }
      if (legacyToken.isNotEmpty) await prefs.remove(_tokenKey);
      token = stored;
    } catch (e) {
      // A device without a working keystore can still use sync; the token
      // simply is not persisted between launches.
      debugPrint('Secure storage unavailable: $e');
      token = legacyToken;
    }

    final ms = prefs.getInt('sync.lastSyncedAt');
    lastSyncedAt = ms == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);

    if (method == SyncMethod.drive) {
      driveAccount = await _googleSignIn.signInSilently();
      if (driveAccount == null) method = SyncMethod.off;
    }

    state = configured ? SyncState.idle : SyncState.off;
    notifyListeners();
  }

  /// Returns an error message for an unusable server URL, or null when valid.
  static String? validateServerUrl(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || uri.host.isEmpty) {
      return 'Enter a full address, e.g. https://tasks.example.com';
    }
    if (uri.scheme != 'https') {
      return 'Use https:// so your token is sent encrypted.';
    }
    if (uri.hasQuery || uri.hasFragment) {
      return 'Enter just the server address, without a query or fragment.';
    }
    return null;
  }

  /// Saves server settings. Returns an error message, or null on success.
  Future<String?> saveServerSettings(
      {required String url, required String tok}) async {
    final error = validateServerUrl(url);
    if (error != null) return error;

    final trimmedToken = tok.trim();
    if (trimmedToken.isEmpty) return 'Enter the access token from your server.';

    baseUrl = url.trim().replaceFirst(RegExp(r'/+$'), '');
    token = trimmedToken;
    method = SyncMethod.server;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('sync.baseUrl', baseUrl);
    await prefs.setInt('sync.method', method.index);
    await prefs.remove(_tokenKey);
    try {
      await _secureStorage.write(key: _tokenKey, value: token);
    } catch (e) {
      debugPrint('Could not store token securely: $e');
    }
    state = configured ? SyncState.idle : SyncState.off;
    notifyListeners();
    if (configured) unawaited(syncNow());
    return null;
  }

  Future<void> signInWithGoogle() async {
    try {
      driveAccount = await _googleSignIn.signIn();
    } catch (e) {
      lastError = 'Google sign-in failed: $e';
      state = SyncState.failed;
      notifyListeners();
      return;
    }
    if (driveAccount == null) return; // user cancelled

    method = SyncMethod.drive;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('sync.method', method.index);
    state = SyncState.idle;
    notifyListeners();
    await syncNow();
  }

  Future<void> signOutOfGoogle() async {
    await _googleSignIn.signOut();
    driveAccount = null;
    if (method == SyncMethod.drive) {
      method = SyncMethod.off;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('sync.method', method.index);
    }
    state = SyncState.off;
    notifyListeners();
  }

  Future<void> turnOff() async {
    method = SyncMethod.off;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('sync.method', method.index);
    state = SyncState.off;
    notifyListeners();
  }

  void _scheduleDebounced() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 3), syncNow);
  }

  bool _running = false;

  Future<void> syncNow() async {
    final taskBackend = _taskBackend;
    final noteBackend = _noteBackend;
    if (taskBackend == null || noteBackend == null || !configured || _running) {
      return;
    }

    final conn = await Connectivity().checkConnectivity();
    if (!conn.any((r) => r != ConnectivityResult.none)) {
      state = SyncState.offline;
      notifyListeners();
      return;
    }

    _running = true;
    state = SyncState.working;
    lastError = null;
    notifyListeners();

    try {
      final serverTime = await _reconcile<Task>(
        backend: taskBackend,
        dirty: _db.dirty,
        find: _db.find,
        upsert: _db.upsert,
        markClean: _db.markClean,
        purgeDeletes: _db.purgeSyncedDeletes,
        idOf: (t) => t.id,
        updatedAtOf: (t) => t.updatedAt,
        onUpsertedRemote: (t) => Notifications.instance.scheduleFor(t),
        since: lastSyncedAt,
      );
      await _reconcile<Note>(
        backend: noteBackend,
        dirty: _db.dirtyNotes,
        find: _db.findNote,
        upsert: _db.upsertNote,
        markClean: _db.markNotesClean,
        purgeDeletes: _db.purgeSyncedNoteDeletes,
        idOf: (n) => n.id,
        updatedAtOf: (n) => n.updatedAt,
        onUpsertedRemote: null,
        since: lastSyncedAt,
      );

      lastSyncedAt = serverTime;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
          'sync.lastSyncedAt', serverTime.millisecondsSinceEpoch);

      state = SyncState.idle;
      await _store.load();
      await _notesStore.load();
    } catch (e) {
      lastError = e.toString();
      state = SyncState.failed;
    } finally {
      _running = false;
      notifyListeners();
    }
  }

  /// Push [dirty] rows through [backend], pull back whatever it returns, and
  /// apply newest-wins locally. Shared between the task pass and the note
  /// pass so the reconciliation rule only lives in one place.
  Future<DateTime> _reconcile<T>({
    required SyncBackend<T> backend,
    required Future<List<T>> Function() dirty,
    required Future<T?> Function(String id) find,
    required Future<void> Function(T) upsert,
    required Future<void> Function(Iterable<String>) markClean,
    required Future<void> Function() purgeDeletes,
    required String Function(T) idOf,
    required DateTime Function(T) updatedAtOf,
    required Future<void> Function(T)? onUpsertedRemote,
    required DateTime? since,
  }) async {
    final outgoing = await dirty();
    final res = await backend.sync(changes: outgoing, since: since);

    // Only clear the dirty flag on rows that were not edited mid-request.
    for (final pushed in outgoing) {
      final current = await find(idOf(pushed));
      if (current != null &&
          updatedAtOf(current).isAtSameMomentAs(updatedAtOf(pushed))) {
        await markClean([idOf(pushed)]);
      }
    }

    // Newest copy wins.
    for (final remote in res.items) {
      final local = await find(idOf(remote));
      if (local == null || updatedAtOf(remote).isAfter(updatedAtOf(local))) {
        await upsert(remote);
        if (onUpsertedRemote != null) await onUpsertedRemote(remote);
      }
    }

    await purgeDeletes();
    return res.serverTime;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _netSub.cancel();
    super.dispose();
  }
}
