import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../data/local_db.dart';
import '../models/task.dart';

const _markDoneAction = 'mark_done';
const _snoozeAction = 'snooze_1h';

/// A reminder inside this many minutes of the deadline is treated as
/// critical: full-screen, high-priority, hard to miss.
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
        'Full-screen alert when a task is due within the hour or overdue',
    importance: Importance.max,
    priority: Priority.max,
    category: AndroidNotificationCategory.alarm,
    fullScreenIntent: true,
    actions: _androidActions,
  ),
  iOS: DarwinNotificationDetails(
    categoryIdentifier: 'deadlineActions',
    interruptionLevel: InterruptionLevel.critical,
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
      Notifications.instance.onExternalChange?.call();
    case _snoozeAction:
      await Notifications.instance._snooze(task);
      Notifications.instance.onExternalChange?.call();
  }
}

/// Two reminders per task by default (a day ahead, an hour ahead), or
/// however many offsets the task was saved with. Whichever is closest to
/// the deadline escalates to a full-screen alert once it's within the hour.
/// All are rescheduled whenever the task changes and cancelled when it is
/// finished or removed.
class Notifications {
  Notifications._();
  static final instance = Notifications._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  /// Called after a notification action mutates the database directly, so a
  /// live app (foreground case) can refresh its in-memory task list. Not set
  /// in a background isolate spun up just to handle the tap.
  VoidCallback? onExternalChange;

  /// Reserved notification-id slots per task: enough for every preset plus
  /// one for a snoozed reminder, with room to spare.
  static const _slotsPerTask = 16;

  Future<void> init() async {
    await _ensureReady();
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestExactAlarmsPermission();
    await _plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
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
      onDidReceiveBackgroundNotificationResponse:
          notificationBackgroundHandler,
    );
    _ready = true;
  }

  int _baseId(String taskId) =>
      (taskId.hashCode & 0x3FFFFFF) * _slotsPerTask;
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
      await _at(
        base + i,
        due.subtract(Duration(minutes: minutesBefore)),
        alarm ? 'Due now' : _labelFor(minutesBefore),
        t.title,
        payload: t.id,
        alarm: alarm,
      );
    }
  }

  Future<void> _snooze(Task task) async {
    await _at(
      _snoozeId(task.id),
      DateTime.now().add(const Duration(hours: 1)),
      'Snoozed reminder',
      task.title,
      payload: task.id,
    );
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

  Future<void> _at(
    int id,
    DateTime when,
    String title,
    String body, {
    required String payload,
    bool alarm = false,
  }) async {
    if (when.isBefore(DateTime.now())) return;
    await _plugin.zonedSchedule(
      id,
      title,
      body,
      tz.TZDateTime.from(when, tz.local),
      alarm ? _alarmDetails : _details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: payload,
    );
  }

  Future<void> resyncAll(Iterable<Task> tasks) async {
    for (final t in tasks) {
      await scheduleFor(t);
    }
  }

  // --- Daily digest -------------------------------------------------------

  static const _digestId = 999999999;

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

    await _plugin.zonedSchedule(
      _digestId,
      'Deadlines today',
      body,
      when,
      _digestDetails,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }
}
