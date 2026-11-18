import 'package:flutter/foundation.dart';

import '../models/task.dart';
import 'platform_bridge.dart';

/// Keeps Android proximity alerts in step with the local task store.
/// A denied/revoked permission leaves the in-app due-date reminder working and
/// is reported through [lastError] so the UI can explain what happened.
class LocationAlerts {
  const LocationAlerts._();

  /// Last permission/bridge problem, consumed by the shell to show a snackbar.
  /// Cleared whenever a later call succeeds.
  static final ValueNotifier<String?> lastError = ValueNotifier<String?>(null);

  static Future<void> register(Task task) async {
    final alert = task.locationAlert;
    if (alert == null) return;
    try {
      await PlatformBridge.addProximityAlert(
        id: task.id,
        latitude: alert.latitude,
        longitude: alert.longitude,
        radiusMeters: alert.radiusMeters,
        label: alert.label.isEmpty ? task.title : alert.label,
      );
      lastError.value = null;
    } on BridgeException catch (e) {
      lastError.value = e.message;
    }
  }

  static Future<void> unregister(String taskId) async {
    try {
      await PlatformBridge.clearProximityAlerts([taskId]);
      lastError.value = null;
    } on BridgeException catch (e) {
      lastError.value = e.message;
    }
  }

  /// Rebuilds all alerts after a cold start (Android drops them on reboot).
  static Future<void> syncAll(Iterable<Task> tasks) async {
    try {
      await PlatformBridge.clearProximityAlerts();
      for (final task in tasks) {
        if (task.deleted || task.locationAlert == null) continue;
        try {
          await PlatformBridge.addProximityAlert(
            id: task.id,
            latitude: task.locationAlert!.latitude,
            longitude: task.locationAlert!.longitude,
            radiusMeters: task.locationAlert!.radiusMeters,
            label: task.locationAlert!.label.isEmpty
                ? task.title
                : task.locationAlert!.label,
          );
        } on BridgeException catch (e) {
          // Keep going: one task with a lost permission must not stop the rest.
          lastError.value = e.message;
        }
      }
    } on BridgeException catch (e) {
      lastError.value = e.message;
    }
  }
}
