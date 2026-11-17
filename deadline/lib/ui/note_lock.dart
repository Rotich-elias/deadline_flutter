import 'package:flutter/material.dart';

import '../services/app_lock_service.dart';
import 'pin_pad.dart';

/// Confirms the user may open a locked note. The app may already be unlocked,
/// but a per-note lock deliberately asks again. Biometrics are offered first;
/// the PIN pad is the fallback.
Future<bool> confirmNoteAccess(
  BuildContext context,
  AppLockService appLock, {
  String reason = 'Unlock this note',
}) async {
  if (!appLock.enabled) return true;

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
