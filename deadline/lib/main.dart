import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'data/local_db.dart';
import 'data/notes_store.dart';
import 'data/task_store.dart';
import 'models/app_advert.dart';
import 'models/app_update.dart';
import 'services/advert_service.dart';
import 'services/app_lock_service.dart';
import 'services/location_alerts.dart';
import 'services/note_draft_service.dart';
import 'services/note_import.dart';
import 'services/notifications.dart';
import 'services/platform_bridge.dart';
import 'services/update_service.dart';
import 'sync/sync_service.dart';
import 'theme.dart';
import 'ui/advert_dialog.dart';
import 'ui/app_lock_gate.dart';
import 'ui/home_shell.dart';
import 'ui/loading_page.dart';
import 'ui/update_dialog.dart';

/// Minimum time the branded loading page stays up, so a fast start does not
/// flash it for a couple of frames.
const _minSplash = Duration(milliseconds: 900);

/// An update prompt waiting for the current dialog to finish.
class _PendingUpdate {
  const _PendingUpdate(this.update, this.current);

  final AppUpdate update;
  final String current;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  // Paint the loading page first, then open the database and load data behind
  // it. This replaces the blank window that used to sit between the native
  // splash and the first real frame.
  runApp(const DeadlineBootstrap());
}

/// Everything the running app needs, once the async startup work is done.
class _AppDeps {
  const _AppDeps({
    required this.store,
    required this.notesStore,
    required this.sync,
    required this.appTheme,
    required this.appLock,
    required this.quickNote,
    required this.pendingDraft,
  });

  final TaskStore store;
  final NotesStore notesStore;
  final SyncService sync;
  final AppTheme appTheme;
  final AppLockService appLock;
  final bool quickNote;
  final bool pendingDraft;
}

class DeadlineBootstrap extends StatefulWidget {
  const DeadlineBootstrap({super.key});

  @override
  State<DeadlineBootstrap> createState() => _DeadlineBootstrapState();
}

class _DeadlineBootstrapState extends State<DeadlineBootstrap> {
  _AppDeps? _deps;
  Object? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_boot());
  }

  Future<void> _boot() async {
    final started = DateTime.now();
    if (_error != null) setState(() => _error = null);

    try {
      final db = LocalDb();
      await db.open();
      await Notifications.instance.init();

      final store = TaskStore(db);
      final notesStore = NotesStore(db);
      final sync = SyncService(db, store, notesStore);
      final appTheme = AppTheme();
      final appLock = AppLockService();
      Notifications.instance.onExternalChange = () => unawaited(store.load());

      await store.loadDigestSettings();
      await appLock.load();
      await store.load();
      await notesStore.load();
      // Older imports used Samsung's whole export file name as the note title.
      // Normalise those once so the notes read like the pages they came from.
      await NoteImport.repairLegacyTitles(notesStore);
      // Android forgets proximity alerts on reboot; rebuild them from data.
      unawaited(LocationAlerts.syncAll(store.tasks));
      // Secure storage can be cleared independently of the database (device
      // transfer, "clear data" on some ROMs). A note lock without any PIN
      // could never be opened again, so release only those orphans. A PIN kept
      // after turning app lock off is enough, so those notes stay locked.
      // The update is a no-op when nothing is locked.
      if (!appLock.pinConfigured) await notesStore.clearAllLocks();
      await sync.loadSettings();
      await appTheme.load();
      // Consume the launcher shortcut flag once, at startup. HomeShell waits
      // for the lock gate to open before acting on it.
      final quickNote = await PlatformBridge.takeQuickNote();
      // A camera hand-off can kill the activity mid-draft. Reopen the note
      // form after the lock gate opens so the draft and photo are restored.
      final pendingDraft = await NoteDraftService().peek() != null;

      final elapsed = DateTime.now().difference(started);
      if (elapsed < _minSplash) {
        await Future<void>.delayed(_minSplash - elapsed);
      }

      if (!mounted) return;
      setState(() {
        _deps = _AppDeps(
          store: store,
          notesStore: notesStore,
          sync: sync,
          appTheme: appTheme,
          appLock: appLock,
          quickNote: quickNote,
          pendingDraft: pendingDraft,
        );
      });
    } catch (error, stack) {
      debugPrint('Startup failed: $error\n$stack');
      if (!mounted) return;
      setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final deps = _deps;

    if (_error != null) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.dark),
        home: BootErrorView(detail: '$_error', onRetry: _boot),
      );
    }

    if (deps == null) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.dark),
        home: const LoadingPage(),
      );
    }

    return DeadlineApp(
      store: deps.store,
      notesStore: deps.notesStore,
      sync: deps.sync,
      appTheme: deps.appTheme,
      appLock: deps.appLock,
      quickNote: deps.quickNote,
      pendingDraft: deps.pendingDraft,
    );
  }
}

class DeadlineApp extends StatefulWidget {
  const DeadlineApp({
    super.key,
    required this.store,
    required this.notesStore,
    required this.sync,
    required this.appTheme,
    required this.appLock,
    required this.quickNote,
    required this.pendingDraft,
  });
  final TaskStore store;
  final NotesStore notesStore;
  final SyncService sync;
  final AppTheme appTheme;
  final AppLockService appLock;
  final bool quickNote;
  final bool pendingDraft;

  @override
  State<DeadlineApp> createState() => _DeadlineAppState();
}

class _DeadlineAppState extends State<DeadlineApp> with WidgetsBindingObserver {
  // Dialogs are opened from this state, which sits above MaterialApp. Keys
  // give them a valid navigator/scaffold context even at that level.
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  final GlobalKey<ScaffoldMessengerState> _messengerKey =
      GlobalKey<ScaffoldMessengerState>();

  bool _updateChecked = false;
  bool _updateDialogShown = false;
  DateTime? _lastResumeUpdateCheck;

  bool _advertChecked = false;
  AppAdvert? _pendingAdvert;
  _PendingUpdate? _pendingUpdate;
  bool _promptsBusy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Notifications.instance.updateTapped.addListener(_onUpdateTapped);
    widget.appLock.addListener(_onAppLockChanged);
    // Never block the first frame on permission dialogs, notification
    // scheduling or the network. The UI paints, then these run.
    WidgetsBinding.instance.addPostFrameCallback((_) => _afterFirstFrame());
  }

  void _onUpdateTapped() {
    if (!Notifications.instance.updateTapped.value) return;
    unawaited(_showPendingUpdate());
  }

  /// A tap may arrive while the PIN screen is up. Wait for the unlock instead
  /// of dropping the prompt, so the notification still does something.
  void _onAppLockChanged() {
    if (!widget.appLock.locked) {
      unawaited(_showPendingUpdate());
      unawaited(_drainPrompts());
    }
  }

  Future<void> _afterFirstFrame() async {
    try {
      if (!await Notifications.instance.areNotificationsEnabled()) {
        await Notifications.instance.requestNotificationPermission();
      }
      await Notifications.instance.resyncAll(widget.store.tasks);
    } catch (e) {
      debugPrint('Reminder setup failed: $e');
    }
    await Notifications.instance.handleLaunchNotification();
    unawaited(widget.sync.syncNow());
    unawaited(_checkForAdverts());
    unawaited(_checkForUpdates());
    unawaited(_showPendingUpdate());
  }

  /// One-shot launch check. Adverts are shown one at a time, newest first,
  /// and held back while the PIN screen is up.
  Future<void> _checkForAdverts() async {
    if (_advertChecked) return;
    _advertChecked = true;

    final current = await PlatformBridge.appVersion() ?? '';
    final adverts = await const AdvertService().check(current);
    if (!mounted || adverts.isEmpty) return;

    _pendingAdvert = adverts.first;
    await _drainPrompts();
  }

  /// Best-effort launch check. It always posts a notification; the in-app
  /// prompt is held back while the PIN screen is up.
  Future<void> _checkForUpdates() async {
    if (_updateChecked) return;
    _updateChecked = true;
    await _performUpdateCheck();
  }

  /// Resume check, throttled so coming back to the app cannot hammer the URL.
  Future<void> _checkForUpdatesOnResume() async {
    final now = DateTime.now();
    final last = _lastResumeUpdateCheck;
    if (last != null && now.difference(last) < const Duration(hours: 24)) {
      return;
    }
    _lastResumeUpdateCheck = now;
    await _performUpdateCheck();
  }

  Future<void> _performUpdateCheck() async {
    final current = await PlatformBridge.appVersion();
    if (current == null || current.isEmpty || !mounted) return;
    final update = await const UpdateService().check(current);
    if (!mounted) return;
    UpdateState.instance.available.value = update;
    if (update == null) return;

    // Safe to post even when locked; only the dialog must wait for unlock.
    await Notifications.instance.showUpdateNotification(update);
    _queueUpdate(update, current);
    await _drainPrompts();
  }

  void _queueUpdate(AppUpdate update, String current) {
    if (_updateDialogShown || _pendingUpdate != null) return;
    _updateDialogShown = true;
    _pendingUpdate = _PendingUpdate(update, current);
  }

  /// Serialises the advert and update popups so they never stack. Adverts take
  /// priority on launch; the update prompt follows as soon as one is dismissed.
  Future<void> _drainPrompts() async {
    if (_promptsBusy || !mounted || widget.appLock.locked) return;

    final navigator = _navigatorKey.currentState;
    final messenger = _messengerKey.currentState;
    final dialogContext = _navigatorKey.currentContext;
    if (navigator == null || messenger == null || dialogContext == null) return;

    final advert = _pendingAdvert;
    if (advert != null) {
      _pendingAdvert = null;
      _promptsBusy = true;
      try {
        await showAdvertDialog(
          dialogContext,
          advert: advert,
          navigator: navigator,
          messenger: messenger,
        );
        // Only remember an advert after its dialog actually opened.
        await const AdvertService().markSeen(advert);
      } catch (e) {
        debugPrint('Could not show advert: $e');
      } finally {
        _promptsBusy = false;
      }
      await _drainPrompts();
      return;
    }

    final pending = _pendingUpdate;
    if (pending == null) return;
    _pendingUpdate = null;
    _promptsBusy = true;
    try {
      await offerUpdate(
        dialogContext,
        update: pending.update,
        currentVersion: pending.current,
        navigator: navigator,
        messenger: messenger,
      );
    } finally {
      _promptsBusy = false;
    }
    await _drainPrompts();
  }

  /// Opens the prompt after the update notification was tapped.
  Future<void> _showPendingUpdate() async {
    if (!mounted || widget.appLock.locked) return;
    final update = await Notifications.instance.takePendingUpdate();
    if (update == null || !mounted || widget.appLock.locked) return;
    final current = await PlatformBridge.appVersion() ?? '';
    _queueUpdate(update, current);
    await _drainPrompts();
  }

  @override
  void dispose() {
    Notifications.instance.updateTapped.removeListener(_onUpdateTapped);
    widget.appLock.removeListener(_onAppLockChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    widget.appLock.handleLifecycle(state);
    if (state == AppLifecycleState.resumed) {
      // Time has passed while the app was away: refresh colours, then sync.
      widget.store.load();
      widget.notesStore.load();
      widget.sync.syncNow();
      unawaited(_checkForUpdatesOnResume());
      unawaited(_showPendingUpdate());
    }
  }

  @override
  void didChangePlatformBrightness() {
    if (widget.appTheme.mode == ThemeMode.system) setState(() {});
  }

  Brightness get _brightness {
    switch (widget.appTheme.mode) {
      case ThemeMode.light:
        return Brightness.light;
      case ThemeMode.dark:
        return Brightness.dark;
      case ThemeMode.system:
        return WidgetsBinding.instance.platformDispatcher.platformBrightness;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.appTheme,
      builder: (context, _) {
        widget.appTheme.syncPalette(
          WidgetsBinding.instance.platformDispatcher.platformBrightness,
        );
        final brightness = _brightness;
        final overlayStyle = SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: brightness == Brightness.dark
              ? Brightness.light
              : Brightness.dark,
          statusBarBrightness: brightness,
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarDividerColor: Colors.transparent,
          systemNavigationBarIconBrightness: brightness == Brightness.dark
              ? Brightness.light
              : Brightness.dark,
        );
        return MaterialApp(
          navigatorKey: _navigatorKey,
          scaffoldMessengerKey: _messengerKey,
          title: 'Deadlines&Notes',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(Brightness.light),
          darkTheme: buildTheme(Brightness.dark),
          themeMode: widget.appTheme.mode,
          builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
            value: overlayStyle,
            child: AppLockGate(
              appLock: widget.appLock,
              child: child ?? const SizedBox.shrink(),
            ),
          ),
          home: HomeShell(
            store: widget.store,
            notesStore: widget.notesStore,
            sync: widget.sync,
            appTheme: widget.appTheme,
            appLock: widget.appLock,
            quickNote: widget.quickNote,
            pendingDraft: widget.pendingDraft,
          ),
        );
      },
    );
  }
}
