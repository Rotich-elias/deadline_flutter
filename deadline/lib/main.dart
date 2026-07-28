import 'dart:async';

import 'package:flutter/material.dart';

import 'data/local_db.dart';
import 'data/notes_store.dart';
import 'data/task_store.dart';
import 'services/notifications.dart';
import 'sync/sync_service.dart';
import 'theme.dart';
import 'ui/home_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

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
  await Notifications.instance.resyncAll(store.tasks);
  unawaited(sync.syncNow());

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

class _DeadlineAppState extends State<DeadlineApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.appTheme,
      builder: (context, _) {
        widget.appTheme.syncPalette(
          WidgetsBinding.instance.platformDispatcher.platformBrightness,
        );
        return MaterialApp(
          title: 'Deadlines&Notes',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(Brightness.light),
          darkTheme: buildTheme(Brightness.dark),
          themeMode: widget.appTheme.mode,
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
