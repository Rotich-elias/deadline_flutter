import 'package:flutter/material.dart';

import '../services/app_lock_service.dart';
import 'lock_page.dart';

/// Overlays [LockPage] above the whole app — including any open bottom sheet
/// or pushed note — so backgrounding the app can never leave content visible
/// behind the lock. The child stays alive underneath, which keeps the current
/// tab and search state across a lock/unlock cycle.
class AppLockGate extends StatelessWidget {
  const AppLockGate({
    super.key,
    required this.appLock,
    required this.child,
  });

  final AppLockService appLock;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appLock,
      builder: (context, _) {
        if (!appLock.enabled || !appLock.locked) return child;
        return Stack(
          fit: StackFit.expand,
          children: [
            // Keep the app underneath for state, but make it inert and
            // invisible to accessibility while the lock is up.
            ExcludeSemantics(
              child: IgnorePointer(child: child),
            ),
            Positioned.fill(
              child: LockPage(appLock: appLock),
            ),
          ],
        );
      },
    );
  }
}
