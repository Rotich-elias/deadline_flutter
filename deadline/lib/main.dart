import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'data/local_db.dart';
import 'data/notes_store.dart';
import 'data/task_store.dart';
import 'services/app_lock_service.dart';
import 'services/notifications.dart';
import 'sync/sync_service.dart';
import 'theme.dart';
import 'ui/app_lock_gate.dart';
import 'ui/home_shell.dart';
import 'ui/loading_page.dart';

/// Minimum time the branded loading page stays up, so a fast start does not
/// flash it for a couple of frames.
const _minSplash = Duration(milliseconds: 900);

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
  });

  final TaskStore store;
  final NotesStore notesStore;
  final SyncService sync;
  final AppTheme appTheme;
  final AppLockService appLock;
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
      // Secure storage can be cleared independently of the database (device
      // transfer, "clear data" on some ROMs). A note lock without an app PIN
      // could never be opened again, so release any orphans. The update is a
      // no-op when nothing is locked.
      if (!appLock.enabled) await notesStore.clearAllLocks();
      await sync.loadSettings();
      await appTheme.load();

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
  });
  final TaskStore store;
  final NotesStore notesStore;
  final SyncService sync;
  final AppTheme appTheme;
  final AppLockService appLock;

  @override
  State<DeadlineApp> createState() => _DeadlineAppState();
}

class _DeadlineAppState extends State<DeadlineApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Never block the first frame on permission dialogs, notification
    // scheduling or the network. The UI paints, then these run.
    WidgetsBinding.instance.addPostFrameCallback((_) => _afterFirstFrame());
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
    unawaited(widget.sync.syncNow());
  }

  @override
  void dispose() {
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
          ),
        );
      },
    );
  }
}
