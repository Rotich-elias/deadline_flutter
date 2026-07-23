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
  Notifications.instance.onExternalChange = () => unawaited(store.load());

  await store.loadDigestSettings();
  await store.load();
  await notesStore.load();
  await sync.loadSettings();
  await Notifications.instance.resyncAll(store.tasks);
  unawaited(sync.syncNow());

  runApp(DeadlineApp(store: store, notesStore: notesStore, sync: sync));
}

class DeadlineApp extends StatefulWidget {
  const DeadlineApp({
    super.key,
    required this.store,
    required this.notesStore,
    required this.sync,
  });
  final TaskStore store;
  final NotesStore notesStore;
  final SyncService sync;

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
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Deadlines',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: HomeShell(
        store: widget.store,
        notesStore: widget.notesStore,
        sync: widget.sync,
      ),
    );
  }
}
