import 'package:flutter/material.dart';

import '../services/app_lock_service.dart';
import '../theme.dart';
import 'pin_pad.dart';

/// Sets up a PIN for locked notes when none exists yet. This deliberately
/// leaves app lock off: a note PIN is enough to gate individual notes, and no
/// app-wide lock or FLAG_SECURE is implied.
Future<bool> ensureNotePin(BuildContext context, AppLockService appLock) async {
  if (appLock.pinConfigured) return true;

  final setUp = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: Ink0.surface,
      title: const Text('Create a note PIN'),
      content: const Text(
        'Locked notes use a four-digit PIN. App lock stays off — this PIN only '
        'protects notes you lock. There is no way to recover it, so remember '
        'it.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Not now'),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Create PIN'),
        ),
      ],
    ),
  );
  if (setUp != true || !context.mounted) return false;

  final pin = await showPinSheet(
    context,
    title: 'Choose a note PIN',
    subtitle: 'Four digits you will use to unlock locked notes.',
  );
  if (pin == null || !context.mounted) return false;

  final confirmed = await showPinSheet(
    context,
    title: 'Confirm your note PIN',
    subtitle: 'Enter the same four digits again.',
    validate: (value) async => value == pin ? null : 'Those PINs do not match',
  );
  if (confirmed == null || !context.mounted) return false;

  await appLock.setPin(pin);
  return true;
}

/// Confirms the user may open a locked note. The app may already be unlocked,
/// but a per-note lock deliberately asks again. Biometrics are offered first
/// when app lock enabled them; the PIN pad is the fallback.
Future<bool> confirmNoteAccess(
  BuildContext context,
  AppLockService appLock, {
  String reason = 'Unlock this note',
}) async {
  if (!appLock.pinConfigured) return true;

  if (appLock.biometricEnabled) {
    final ok = await appLock.authenticateBiometric(reason: reason);
    if (ok) return true;
    if (!context.mounted) return false;
  }

  final pin = await showPinSheet(
    context,
    title: 'Locked note',
    subtitle: 'Enter your PIN to open it.',
    validate: (value) async =>
        await appLock.verifyPin(value) ? null : 'Wrong PIN',
  );
  return pin != null;
}
