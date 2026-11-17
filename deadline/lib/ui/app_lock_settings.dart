import 'package:flutter/material.dart';

import '../data/notes_store.dart';
import '../services/app_lock_service.dart';
import '../theme.dart';
import 'pin_pad.dart';

/// Settings for the app PIN and the optional biometric unlock. Locked notes
/// are managed from a note itself (the lock button in the note view).
Future<void> showAppLockSettings(
  BuildContext context,
  AppLockService appLock,
  NotesStore notesStore,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Ink0.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _AppLockSheet(appLock: appLock, notesStore: notesStore),
  );
}

class _AppLockSheet extends StatelessWidget {
  const _AppLockSheet({required this.appLock, required this.notesStore});

  final AppLockService appLock;
  final NotesStore notesStore;

  Future<void> _setUp(BuildContext context) async {
    final pin = await showPinSheet(
      context,
      title: 'Choose a PIN',
      subtitle: 'Four digits you will use to unlock the app.',
    );
    if (pin == null || !context.mounted) return;

    final confirmed = await showPinSheet(
      context,
      title: 'Confirm your PIN',
      subtitle: 'Enter the same four digits again.',
      validate: (value) async =>
          value == pin ? null : 'Those PINs do not match',
    );
    if (confirmed == null || !context.mounted) return;

    await appLock.enable(pin);
    if (!context.mounted) return;
    _say(context, 'App lock is on');
  }

  Future<void> _changePin(BuildContext context) async {
    final current = await _askPin(
      context,
      title: 'Enter your current PIN',
      subtitle: 'Confirm it is you before choosing a new PIN.',
      verify: true,
    );
    if (current == null || !context.mounted) return;

    final pin = await showPinSheet(
      context,
      title: 'Choose a new PIN',
      subtitle: 'Four digits you will use to unlock the app.',
    );
    if (pin == null || !context.mounted) return;

    final confirmed = await showPinSheet(
      context,
      title: 'Confirm your new PIN',
      subtitle: 'Enter the same four digits again.',
      validate: (value) async =>
          value == pin ? null : 'Those PINs do not match',
    );
    if (confirmed == null || !context.mounted) return;

    final changed = await appLock.changePin(current, pin);
    if (!context.mounted) return;
    _say(context, changed ? 'PIN changed' : 'Could not change the PIN');
  }

  Future<void> _disable(BuildContext context) async {
    final pin = await _askPin(
      context,
      title: 'Turn off app lock',
      subtitle: 'Enter your PIN to confirm.',
      verify: true,
    );
    if (pin == null || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    // A note lock without app lock would be impossible to open, so turning
    // app lock off releases every note.
    await notesStore.clearAllLocks();
    await appLock.disable(pin);
    if (!context.mounted) return;

    Navigator.of(context).pop();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(
        content: Text('App lock is off. Locked notes were unlocked.'),
      ));
  }

  void _lockNow(BuildContext context) {
    Navigator.of(context).pop();
    appLock.lockNow();
  }

  Future<String?> _askPin(
    BuildContext context, {
    required String title,
    String? subtitle,
    bool verify = false,
  }) {
    return showPinSheet(
      context,
      title: title,
      subtitle: subtitle,
      validate: verify
          ? (value) async => await appLock.verifyPin(value) ? null : 'Wrong PIN'
          : null,
    );
  }

  static void _say(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appLock,
      builder: (context, _) {
        final on = appLock.enabled;
        return SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Ink0.line,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Ink0.surfaceHi,
                        shape: BoxShape.circle,
                        border: Border.all(color: Ink0.line),
                      ),
                      child: Icon(
                        on ? Icons.lock_outline : Icons.lock_open_outlined,
                        size: 21,
                        color: on ? Ink0.text : Ink0.muted,
                      ),
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'App lock',
                            style: TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w700,
                              color: Ink0.text,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            on
                                ? 'On · locked when you leave the app'
                                : 'Off · anyone with the phone can read your notes',
                            style: TextStyle(fontSize: 12.5, color: Ink0.muted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                if (!on) ...[
                  Text(
                    'Protect the whole app with a four-digit PIN. You can also '
                    'lock individual notes; they stay masked in the list and '
                    'are left out of search results.',
                    style: TextStyle(
                        fontSize: 13.5, color: Ink0.muted, height: 1.5),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => _setUp(context),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Set up app lock',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ] else ...[
                  SwitchListTile.adaptive(
                    value: appLock.biometricEnabled,
                    onChanged: appLock.biometricsAvailable
                        ? (value) async {
                            await appLock.setBiometricEnabled(value);
                            if (context.mounted &&
                                value &&
                                !appLock.biometricEnabled) {
                              _say(context,
                                  'Fingerprint unlock is not available here');
                            }
                          }
                        : null,
                    contentPadding: EdgeInsets.zero,
                    title: Text('Unlock with fingerprint',
                        style: TextStyle(color: Ink0.text, fontSize: 15)),
                    subtitle: Text(
                      appLock.biometricsAvailable
                          ? 'Use the fingerprint already set up on this phone'
                          : 'No fingerprint is set up on this phone',
                      style: TextStyle(fontSize: 12.5, color: Ink0.muted),
                    ),
                  ),
                  _ActionRow(
                    icon: Icons.password,
                    label: 'Change PIN',
                    onTap: () => _changePin(context),
                  ),
                  _ActionRow(
                    icon: Icons.lock_clock_outlined,
                    label: 'Lock now',
                    onTap: () => _lockNow(context),
                  ),
                  const SizedBox(height: 8),
                  _ActionRow(
                    icon: Icons.lock_open_outlined,
                    label: 'Turn off app lock',
                    danger: true,
                    onTap: () => _disable(context),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Turning app lock off also unlocks every locked note. '
                    'The PIN itself is never stored; only a salted hash is '
                    'kept in the phone\'s secure storage.',
                    style: TextStyle(
                        fontSize: 12, color: Ink0.muted, height: 1.45),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? const Color(0xFFFF6B6B) : Ink0.text;
    return ListTile(
      onTap: onTap,
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, size: 20, color: danger ? color : Ink0.muted),
      title: Text(label, style: TextStyle(fontSize: 15, color: color)),
      trailing: Icon(Icons.chevron_right, size: 20, color: Ink0.muted),
    );
  }
}
