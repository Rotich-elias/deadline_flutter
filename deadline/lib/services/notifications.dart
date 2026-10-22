import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../data/local_db.dart';
import '../models/task.dart';
import 'home_widget_service.dart';

const _markDoneAction = 'mark_done';
const _snoozeAction = 'snooze_1h';

/// A reminder inside this many minutes of the deadline is treated as
/// critical: maximum importance, hard to miss.
const _alarmThresholdMinutes = 60;

const _androidActions = <AndroidNotificationAction>[
  AndroidNotificationAction(_markDoneAction, 'Mark done',
      cancelNotification: true),
  AndroidNotificationAction(_snoozeAction, 'Snooze 1h',
      cancelNotification: true, showsUserInterface: false),
];

final _iosCategory = DarwinNotificationCategory(
  'deadlineActions',
  actions: <DarwinNotificationAction>[
    DarwinNotificationAction.plain(_markDoneAction, 'Mark done'),
    DarwinNotificationAction.plain(_snoozeAction, 'Snooze 1h',
        options: {DarwinNotificationActionOption.foreground}),
  ],
);

const _details = NotificationDetails(
  android: AndroidNotificationDetails(
    'deadlines',
    'Deadline reminders',
    channelDescription: 'Warnings before a task is due',
    importance: Importance.high,
    priority: Priority.high,
    actions: _androidActions,
  ),
  iOS: DarwinNotificationDetails(categoryIdentifier: 'deadlineActions'),
);

const _alarmDetails = NotificationDetails(
  android: AndroidNotificationDetails(
    'deadlines_alarm',
    'Urgent deadline alerts',
    channelDescription:
        'High-priority alert when a task is due within the hour or overdue',
    importance: Importance.max,
    priority: Priority.max,
    category: AndroidNotificationCategory.alarm,
    actions: _androidActions,
  ),
  iOS: DarwinNotificationDetails(
    categoryIdentifier: 'deadlineActions',
    interruptionLevel: InterruptionLevel.timeSensitive,
  ),
);

const _digestDetails = NotificationDetails(
  android: AndroidNotificationDetails(
    'daily_digest',
    'Daily summary',
    channelDescription: 'One notification each morning with what is due',
    importance: Importance.defaultImportance,
    priority: Priority.defaultPriority,
  ),
  iOS: DarwinNotificationDetails(),
);

/// Runs in whichever isolate the OS delivered the tap in — the running app,
/// or (if the app was not alive) a fresh background isolate with no access
/// to app state. Either way we go straight to the database.
@pragma('vm:entry-point')
void notificationBackgroundHandler(NotificationResponse response) {
  _handleResponse(response);
}

void _foregroundHandler(NotificationResponse response) {
  _handleResponse(response);
}

Future<void> _handleResponse(NotificationResponse response) async {
  final taskId = response.payload;
  if (taskId == null || taskId.isEmpty) return;

  final db = LocalDb();
  await db.open();
  final task = await db.find(taskId);
  if (task == null) return;

  switch (response.actionId) {
    case _markDoneAction:
      await db.upsert(task.copyWith(done: true));
      await Notifications.instance.cancelFor(task.id);
      final next = task.nextOccurrence();
      if (next != null) {
        await db.upsert(next);
        await Notifications.instance.scheduleFor(next);
      }
      try {
        await HomeWidgetService.update(await db.all());
      } catch (e) {
        debugPrint('Could not refresh widget after notification: $e');
      }
      Notifications.instance.onExternalChange?.call();
    case _snoozeAction:
      await Notifications.instance._snooze(task);
      Notifications.instance.onExternalChange?.call();
  }
}

/// Two reminders per task by default (a day ahead, an hour ahead), or
/// however many offsets the task was saved with. Whichever is closest to
/// the deadline gets maximum importance. All are rescheduled whenever the
/// task changes and cancelled when it is finished or removed.
class Notifications {
  Notifications._();
  static final instance = Notifications._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  /// Whether Android currently lets the app schedule exact alarms. When it
  /// doesn't (Android 14+ default), reminders fall back to inexact alarms
  /// instead of failing to schedule at all.
  bool _exactAllowed = true;

  /// Called after a notification action mutates the database directly, so a
  /// live app (foreground case) can refresh its in-memory task list. Not set
  /// in a background isolate spun up just to handle the tap.
  VoidCallback? onExternalChange;

  /// Reserved notification-id slots per task: enough for every preset plus
  /// one for a snoozed reminder, with room to spare.
  static const _slotsPerTask = 8;

  /// Negative so it can never collide with a task's positive id range.
  static const _digestId = -424242;

  /// Prepares timezone data and the plugin. Deliberately does not ask for
  /// permissions: that happens after the first frame (or from settings) so a
  /// slow system dialog box can never delay or break launch.
  Future<void> init() async {
    await _ensureReady();
    await refreshExactAlarmStatus();
  }

  /// Sets up timezone data and the plugin instance. Called from [init] in the
  /// running app, and lazily from the background isolate before it touches
  /// the plugin, since that isolate never runs [init].
  Future<void> _ensureReady() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    final name = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(name));

    await _plugin.initialize(
      InitializationSettings(
        android: const AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          notificationCategories: [_iosCategory],
        ),
      ),
      onDidReceiveNotificationResponse: _foregroundHandler,
      onDidReceiveBackgroundNotificationResponse: notificationBackgroundHandler,
    );
    _ready = true;
  }

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  /// Re-reads the exact-alarm grant. Call after returning from system settings.
  Future<bool> refreshExactAlarmStatus() async {
    final android = _android;
    if (android == null) {
      _exactAllowed = true;
      return true;
    }
    try {
      _exactAllowed = await android.canScheduleExactNotifications() ?? true;
    } catch (e) {
      debugPrint('Could not read exact alarm status: $e');
      _exactAllowed = true;
    }
    return _exactAllowed;
  }

  Future<bool> canScheduleExactNotifications() => refreshExactAlarmStatus();

  /// Whether the user has notifications enabled at all.
  Future<bool> areNotificationsEnabled() async {
    await _ensureReady();
    final android = _android;
    if (android == null) return true;
    try {
      return await android.areNotificationsEnabled() ?? true;
    } catch (e) {
      debugPrint('Could not read notification permission: $e');
      return true;
    }
  }

  /// Shows the Android 13+ notification permission prompt. Safe to call more
  /// than once: the OS simply returns the existing decision.
  Future<bool> requestNotificationPermission() async {
    await _ensureReady();
    final android = _android;
    if (android != null) {
      try {
        return await android.requestNotificationsPermission() ?? true;
      } catch (e) {
        debugPrint('Could not request notification permission: $e');
        return false;
      }
    }
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      try {
        return await ios.requestPermissions(
              alert: true,
              badge: true,
              sound: true,
            ) ??
            false;
      } catch (e) {
        debugPrint('Could not request notification permission: $e');
        return false;
      }
    }
    return true;
  }

  /// Opens the system "alarms & reminders" screen on Android 12+. Returns the
  /// grant after the user comes back, so callers can re-sync the schedule.
  Future<bool> requestExactAlarmPermission() async {
    await _ensureReady();
    final android = _android;
    if (android == null) return true;
    try {
      await android.requestExactAlarmsPermission();
    } catch (e) {
      debugPrint('Could not request exact alarm permission: $e');
    }
    return refreshExactAlarmStatus();
  }

  /// A stable 28-bit id derived from the task's UUID. Unlike [Object.hashCode]
  /// this is guaranteed to be identical across runs, isolates and Dart
  /// versions, so a task's reminders can always be found and cancelled again.
  int _baseId(String taskId) {
    var hash = 0x811c9dc5;
    for (final unit in taskId.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return (hash & 0x07FFFFFF) * _slotsPerTask;
  }

  int _snoozeId(String taskId) => _baseId(taskId) + _slotsPerTask - 1;

  Future<void> cancelFor(String taskId) async {
    await _ensureReady();
    final base = _baseId(taskId);
    for (var i = 0; i < _slotsPerTask; i++) {
      await _plugin.cancel(base + i);
    }
  }

  Future<void> scheduleFor(Task t) async {
    await _ensureReady();
    await cancelFor(t.id);
    if (t.done || t.deleted) return;

    final base = _baseId(t.id);
    final due = t.dueLocal;
    final offsets = t.reminderMinutes.toSet().toList()..sort();
    const maxOffsets = _slotsPerTask - 1; // last slot reserved for snooze

    for (var i = 0; i < offsets.length && i < maxOffsets; i++) {
      final minutesBefore = offsets[i];
      final alarm = minutesBefore <= _alarmThresholdMinutes;
      try {
        await _at(
          base + i,
          due.subtract(Duration(minutes: minutesBefore)),
          alarm ? 'Due now' : _labelFor(minutesBefore),
          t.title,
          payload: t.id,
          alarm: alarm,
        );
      } catch (e) {
        // One bad reminder must not stop the rest from being scheduled.
        debugPrint('Could not schedule reminder for "${t.title}": $e');
      }
    }
  }

  Future<void> _snooze(Task task) async {
    try {
      await _at(
        _snoozeId(task.id),
        DateTime.now().add(const Duration(hours: 1)),
        'Snoozed reminder',
        task.title,
        payload: task.id,
      );
    } catch (e) {
      debugPrint('Could not snooze reminder: $e');
    }
  }

  static String _labelFor(int minutes) {
    if (minutes >= 24 * 60) {
      final days = minutes ~/ (24 * 60);
      return days == 1 ? 'Due tomorrow' : 'Due in $days days';
    }
    if (minutes >= 60) {
      final hours = minutes ~/ 60;
      return hours == 1 ? 'Due in an hour' : 'Due in ${hours}h';
    }
    return 'Due in ${minutes}m';
  }

  AndroidScheduleMode get _scheduleMode => _exactAllowed
      ? AndroidScheduleMode.exactAllowWhileIdle
      : AndroidScheduleMode.inexactAllowWhileIdle;

  /// Schedules with an exact alarm when allowed, and transparently retries as
  /// an inexact alarm if Android rejects the exact request.
  Future<void> _schedule(
    int id,
    String title,
    String body,
    tz.TZDateTime when,
    NotificationDetails details, {
    required String? payload,
    DateTimeComponents? matchDateTimeComponents,
  }) async {
    try {
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        when,
        details,
        androidScheduleMode: _scheduleMode,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: matchDateTimeComponents,
        payload: payload,
      );
    } on PlatformException catch (e) {
      if (e.code != 'exact_alarms_not_permitted') rethrow;
      _exactAllowed = false;
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        when,
        details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: matchDateTimeComponents,
        payload: payload,
      );
    }
  }

  Future<void> _at(
    int id,
    DateTime when,
    String title,
    String body, {
    required String payload,
    bool alarm = false,
  }) async {
    if (when.isBefore(DateTime.now())) return;
    await _schedule(
      id,
      title,
      body,
      tz.TZDateTime.from(when, tz.local),
      alarm ? _alarmDetails : _details,
      payload: payload,
    );
  }

  Future<void> resyncAll(Iterable<Task> tasks) async {
    for (final t in tasks) {
      try {
        await scheduleFor(t);
      } catch (e) {
        debugPrint('Could not reschedule "${t.title}": $e');
      }
    }
  }

  // --- Daily digest -------------------------------------------------------

  Future<void> scheduleDigest({
    required bool enabled,
    required int hour,
    required int minute,
    required int openCount,
    required int overdueCount,
  }) async {
    await _ensureReady();
    await _plugin.cancel(_digestId);
    if (!enabled || openCount == 0) return;

    final body = overdueCount > 0
        ? '$openCount open, $overdueCount overdue'
        : '$openCount due — nothing overdue';

    final now = tz.TZDateTime.now(tz.local);
    var when =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (when.isBefore(now)) when = when.add(const Duration(days: 1));

    try {
      await _schedule(
        _digestId,
        'Deadlines today',
        body,
        when,
        _digestDetails,
        payload: null,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    } catch (e) {
      debugPrint('Could not schedule daily digest: $e');
    }
  }
}
