import '../models/task.dart';
import 'platform_bridge.dart';

/// Keeps Android proximity alerts in step with the local task store.
/// Every method is best-effort: a denied permission simply leaves the in-app
/// due-date reminder working and never blocks a save.
class LocationAlerts {
  const LocationAlerts._();

  static Future<void> register(Task task) async {
    final alert = task.locationAlert;
    if (alert == null) return;
    await PlatformBridge.addProximityAlert(
      id: task.id,
      latitude: alert.latitude,
      longitude: alert.longitude,
      radiusMeters: alert.radiusMeters,
      label: alert.label.isEmpty ? task.title : alert.label,
    );
  }

  static Future<void> unregister(String taskId) =>
      PlatformBridge.clearProximityAlerts([taskId]);

  /// Rebuilds all alerts after a cold start (Android drops them on reboot).
  static Future<void> syncAll(Iterable<Task> tasks) async {
    await PlatformBridge.clearProximityAlerts();
    for (final task in tasks) {
      if (task.deleted || task.locationAlert == null) continue;
      await register(task);
    }
  }
}
