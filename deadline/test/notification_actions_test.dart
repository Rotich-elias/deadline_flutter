import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android manifest registers the notification action receiver', () {
    // flutter_local_notifications sends every "Mark done" / "Snooze 1h" press
    // to this receiver as an explicit broadcast. The plugin's own manifest
    // does not declare it, so forgetting it here makes the buttons silently
    // do nothing (Android just drops the broadcast).
    const receiver =
        'com.dexterous.flutterlocalnotifications.ActionBroadcastReceiver';

    final candidates = [
      File('android/app/src/main/AndroidManifest.xml'),
      File('../android/app/src/main/AndroidManifest.xml'),
    ];
    final manifest = candidates.firstWhere(
      (f) => f.existsSync(),
      orElse: () => throw StateError('AndroidManifest.xml not found'),
    );

    expect(manifest.readAsStringSync(), contains(receiver));
  });
}
