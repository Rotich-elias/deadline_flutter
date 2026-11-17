import 'package:flutter/material.dart';

import '../services/app_lock_service.dart';
import '../theme.dart';
import 'pin_pad.dart';

/// Full-screen PIN gate shown instead of [HomeShell] whenever app lock is on
/// and the app has been backgrounded (or the user tapped "Lock now").
class LockPage extends StatefulWidget {
  const LockPage({super.key, required this.appLock});

  final AppLockService appLock;

  @override
  State<LockPage> createState() => _LockPageState();
}

class _LockPageState extends State<LockPage> {
  bool _biometricPrompted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryBiometrics());
  }

  Future<void> _tryBiometrics() async {
    if (!mounted || _biometricPrompted) return;
    if (!widget.appLock.biometricEnabled) return;
    _biometricPrompted = true;
    final ok = await widget.appLock
        .authenticateBiometric(reason: 'Unlock Deadlines&Notes');
    if (ok && mounted) widget.appLock.unlock();
  }

  @override
  Widget build(BuildContext context) {
    final biometricsOn = widget.appLock.biometricEnabled;
    return Scaffold(
      backgroundColor: Ink0.bg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
            child: PinPad(
              icon: Icons.lock_outline,
              title: 'Deadlines&Notes',
              subtitle: biometricsOn
                  ? 'Enter your PIN, or use your fingerprint'
                  : 'Enter your PIN to unlock',
              popOnSuccess: false,
              validate: (pin) async =>
                  await widget.appLock.verifyPin(pin) ? null : 'Wrong PIN',
              onSuccess: (_) => widget.appLock.unlock(),
              onBiometric: biometricsOn ? _tryBiometrics : null,
            ),
          ),
        ),
      ),
    );
  }
}
