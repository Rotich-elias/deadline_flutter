import 'package:flutter/material.dart';

import '../models/app_advert.dart';
import '../services/platform_bridge.dart';
import '../theme.dart';

/// Shows a published advert. The CTA, when present, opens in the browser;
/// otherwise the popup is informational only.
Future<void> showAdvertDialog(
  BuildContext context, {
  required AppAdvert advert,
  NavigatorState? navigator,
  ScaffoldMessengerState? messenger,
}) async {
  // The caller may live above MaterialApp, where Navigator.of(context) cannot
  // see the app's navigator. Explicit states keep the popup working there.
  final nav = navigator ?? Navigator.of(context);
  final msg = messenger ?? ScaffoldMessenger.of(context);

  final accepted = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: Ink0.surface,
      title: Text(
        advert.title,
        style: TextStyle(color: Ink0.text, fontSize: 17),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (advert.hasImage)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  advert.imageUrl!,
                  height: 140,
                  fit: BoxFit.cover,
                  // A missing banner must not hide the message.
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            if (advert.hasImage) const SizedBox(height: 12),
            Text(
              advert.body,
              style: TextStyle(color: Ink0.muted, fontSize: 13),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => nav.pop(false),
          child: const Text('Close'),
        ),
        if (advert.hasCta)
          FilledButton(
            onPressed: () => nav.pop(true),
            child: Text(advert.buttonLabel),
          ),
      ],
    ),
  );

  if (accepted != true || !advert.hasCta || !context.mounted) return;
  final opened = await PlatformBridge.openUrl(advert.ctaUrl!);
  if (!opened && context.mounted) {
    msg.showSnackBar(SnackBar(
      content: Text('Could not open a browser. Visit ${advert.ctaUrl}'),
    ));
  }
}
