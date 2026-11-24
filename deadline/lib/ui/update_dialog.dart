import 'package:flutter/material.dart';

import '../models/app_update.dart';
import '../services/platform_bridge.dart';
import '../theme.dart';

/// Shows the update prompt and, when accepted, opens the published APK URL.
/// Choosing "Later" does nothing.
Future<void> offerUpdate(
  BuildContext context, {
  required AppUpdate update,
  required String currentVersion,
  NavigatorState? navigator,
  ScaffoldMessengerState? messenger,
}) async {
  // Callers above MaterialApp must pass the app's navigator explicitly.
  final nav = navigator ?? Navigator.of(context);
  final msg = messenger ?? ScaffoldMessenger.of(context);

  final accepted = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: Ink0.surface,
      title: Text(
        'Update available',
        style: TextStyle(color: Ink0.text, fontSize: 17),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            update.latestVersion == null
                ? 'A new version of Deadlines&Notes is available.'
                : 'Version ${update.latestVersion} is available. '
                    'You have $currentVersion.',
            style: TextStyle(color: Ink0.muted, fontSize: 13),
          ),
          if (update.notes.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              update.notes.trim(),
              style: TextStyle(color: Ink0.muted, fontSize: 13),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => nav.pop(false),
          child: const Text('Later'),
        ),
        FilledButton(
          onPressed: () => nav.pop(true),
          child: const Text('Update'),
        ),
      ],
    ),
  );

  if (accepted != true || !context.mounted) return;
  final opened = await PlatformBridge.openUrl(update.url);
  if (!opened && context.mounted) {
    msg.showSnackBar(SnackBar(
      content: Text('Could not open a browser. Visit ${update.url}'),
    ));
  }
}
