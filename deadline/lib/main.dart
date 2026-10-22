import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'data/local_db.dart';
import 'data/notes_store.dart';
import 'data/task_store.dart';
import 'services/notifications.dart';
import 'sync/sync_service.dart';
import 'theme.dart';
import 'ui/home_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  final db = LocalDb();
  await db.open();
  await Notifications.instance.init();

  final store = TaskStore(db);
  final notesStore = NotesStore(db);
  final sync = SyncService(db, store, notesStore);
  final appTheme = AppTheme();
  Notifications.instance.onExternalChange = () => unawaited(store.load());

  await store.loadDigestSettings();
  await store.load();
  await notesStore.load();
  await sync.loadSettings();
  await appTheme.load();

  runApp(DeadlineApp(
    store: store,
    notesStore: notesStore,
    sync: sync,
    appTheme: appTheme,
  ));
}

class DeadlineApp extends StatefulWidget {
  const DeadlineApp({
    super.key,
    required this.store,
    required this.notesStore,
    required this.sync,
    required this.appTheme,
  });
  final TaskStore store;
  final NotesStore notesStore;
  final SyncService sync;
  final AppTheme appTheme;

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
            child: child ?? const SizedBox.shrink(),
          ),
          home: HomeShell(
            store: widget.store,
            notesStore: widget.notesStore,
            sync: widget.sync,
            appTheme: widget.appTheme,
          ),
        );
      },
    );
  }
}
