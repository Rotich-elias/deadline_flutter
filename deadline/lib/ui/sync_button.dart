import 'package:flutter/material.dart';

import '../sync/sync_service.dart';
import '../theme.dart';
import '../utils/urgency.dart';
import 'settings_sheet.dart';

/// The small cloud icon in each page header — tap to open sync settings.
/// Shared between the deadlines and notes tabs since they sync through the
/// same [SyncService].
class SyncButton extends StatelessWidget {
  const SyncButton({super.key, required this.sync});
  final SyncService sync;

  @override
  Widget build(BuildContext context) {
    if (sync.state == SyncState.working) {
      return const Padding(
        padding: EdgeInsets.all(14),
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    final (icon, color) = switch (sync.state) {
      SyncState.off => (Icons.cloud_off, Ink0.muted),
      SyncState.offline => (Icons.cloud_off, Ink0.muted),
      SyncState.failed => (Icons.cloud_off, Urgency.overdue.color),
      _ => (Icons.cloud_done, Urgency.week.color),
    };

    return IconButton(
      tooltip: 'Sync settings',
      icon: Icon(icon, color: color, size: 21),
      onPressed: () => showSyncSettings(context, sync),
    );
  }
}
