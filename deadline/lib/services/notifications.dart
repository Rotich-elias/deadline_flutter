import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../data/local_db.dart';
// Our Task.Priority would collide with flutter_local_notifications' Priority,
// which is the one this file uses for Android notification importance.
import '../models/app_update.dart';
import '../models/task.dart' hide Priority;
import '../utils/company.dart';
import 'home_widget_service.dart';

const _markDoneAction = 'mark_done';
const _snoozeAction = 'snooze_1h';

/// Payload prefix for update notifications. Keeps a tap from being mistaken
/// for a task id when the response is routed by [_handleResponse].
const _updatePayloadPrefix = 'update:';

/// SharedPreferences keys for update-notification dedup and tap hand-off.
const _shownUpdateKey = 'notifications.updateShown';
const _pendingUpdateKey = 'notifications.pendingUpdate';

/// A reminder inside this many minutes of the deadline is treated as
/// critical: maximum importance, hard to miss.
const _alarmThresholdMinutes = 60;

/// Versioned channel ids. Android locks a channel's importance, sound and
/// pop-up behaviour when it is first created, so older installs that created
/// the original `deadlines` channel keep its settings forever. Bumping the id
/// gives every install a fresh channel that is guaranteed to pop up and play
/// the phone's notification tone.
const _reminderChannelId = 'deadlines_reminders_v2';
const _reminderChannelName = 'Deadline reminders';
const _alarmChannelId = 'deadlines_alarm_v2';
const _alarmChannelName = 'Urgent deadline alerts';
const _updateChannelId = 'deadlines_updates_v1';
const _updateChannelName = 'App updates';
const _channelsMigratedKey = 'notifications.channels_v2';

const _reminderChannel = AndroidNotificationChannel(
  _reminderChannelId,
  _reminderChannelName,
  description: 'A pop-up reminder before a task is due',
  importance: Importance.max,
  playSound: true,
  enableVibration: true,
  showBadge: true,
);

const _alarmChannel = AndroidNotificationChannel(
  _alarmChannelId,
  _alarmChannelName,
  description: 'Pop-up alert when a task is due within the hour or overdue',
  importance: Importance.max,
  playSound: true,
  enableVibration: true,
  showBadge: true,
);

const _updateChannel = AndroidNotificationChannel(
  _updateChannelId,
  _updateChannelName,
  description: 'Lets you know when a new version is ready to install',
  importance: Importance.defaultImportance,
  playSound: true,
  enableVibration: false,
  showBadge: true,
);

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

/// Head-up reminder: maximum importance plus the default notification sound,
/// so it behaves like a WhatsApp or SMS alert. The tone is whatever the user
/// has picked for this channel in Android settings.
const _details = NotificationDetails(
  android: AndroidNotificationDetails(
    _reminderChannelId,
    _reminderChannelName,
    channelDescription: 'A pop-up reminder before a task is due',
    importance: Importance.max,
    priority: Priority.max,
    category: AndroidNotificationCategory.reminder,
    visibility: NotificationVisibility.public,
    channelShowBadge: true,
    playSound: true,
    enableVibration: true,
    actions: _androidActions,
  ),
  iOS: DarwinNotificationDetails(categoryIdentifier: 'deadlineActions'),
);

const _alarmDetails = NotificationDetails(
  android: AndroidNotificationDetails(
    _alarmChannelId,
    _alarmChannelName,
    channelDescription:
        'Pop-up alert when a task is due within the hour or overdue',
    importance: Importance.max,
    priority: Priority.max,
    category: AndroidNotificationCategory.alarm,
    visibility: NotificationVisibility.public,
    channelShowBadge: true,
    playSound: true,
    enableVibration: true,
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

const _updateDetails = NotificationDetails(
  android: AndroidNotificationDetails(
    _updateChannelId,
    _updateChannelName,
    channelDescription: 'Lets you know when a new version is ready to install',
    importance: Importance.defaultImportance,
    priority: Priority.defaultPriority,
    visibility: NotificationVisibility.public,
    channelShowBadge: true,
    playSound: true,
  ),
  iOS: DarwinNotificationDetails(),
);

/// Runs in whichever isolate the OS delivered the tap in — the running app,
/// or (if the app was not alive) a fresh background isolate with no access
/// to app state. Either way we go straight to the database.
@pragma('vm:entry-point')
Future<void> notificationBackgroundHandler(NotificationResponse response) {
  return _handleResponse(response);
}

Future<void> _foregroundHandler(NotificationResponse response) {
  return _handleResponse(response);
}

Future<void> _handleResponse(NotificationResponse response) async {
  final payload = response.payload;
  if (payload == null || payload.isEmpty) return;

  // Update taps carry a version/fingerprint instead of a task id. Record it
  // for the app to consume on the next frame; this also runs in a background
  // isolate after the app was killed, so SharedPreferences is the hand-off.
  if (payload.startsWith(_updatePayloadPrefix)) {
    await Notifications.instance._handleUpdateTap(
      payload.substring(_updatePayloadPrefix.length),
    );
    return;
  }

  final taskId = payload;

  // This also runs in a fresh background isolate that never went through
  // init(), so make sure the plugin and timezone data are ready before
  // cancelling reminders or scheduling a snooze.
  await Notifications.instance._ensureReady();

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

  /// The "Test alert" notification, also outside the task id range.
  static const _testId = -424243;

  /// The update prompt, outside both the task id and digest ranges.
  static const _updateId = -424244;

  /// Set when an update notification is tapped, so a live app can react
  /// immediately. The SharedPreferences flag covers the cold-start case.
  final ValueNotifier<bool> updateTapped = ValueNotifier<bool>(false);

  /// Native bridge for opening this app's reminder-channel settings page, so
  /// the user can pick the tone Android plays for reminders.
  static const _native = MethodChannel('deadline/notifications');

  /// Whether channels were already created or migrated in this isolate.
  bool _channelsReady = false;

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
    await _ensureChannels();
    _ready = true;
  }

  /// Creates the reminder channels, replacing the first-version ones once.
  ///
  /// A channel's importance, sound and pop-up behaviour cannot be changed
  /// after Android creates it — not by the app, and not by reinstalling over
  /// itself. The old `deadlines` channel was created at `high` importance
  /// without an explicit sound, so installs that had it get a silent banner
  /// forever. Deleting it once and moving to fresh `_v2` ids is the only way
  /// to guarantee a pop-up with the phone's notification tone.
  Future<void> _ensureChannels() async {
    if (_channelsReady) return;
    final android = _android;
    if (android == null) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      if (!(prefs.getBool(_channelsMigratedKey) ?? false)) {
        await android.deleteNotificationChannel('deadlines');
        await android.deleteNotificationChannel('deadlines_alarm');
        await prefs.setBool(_channelsMigratedKey, true);
      }
      await android.createNotificationChannel(_reminderChannel);
      await android.createNotificationChannel(_alarmChannel);
      await android.createNotificationChannel(_updateChannel);
      _channelsReady = true;
    } catch (e) {
      // Recreate next launch: channel creation is idempotent, and the pref
      // only sticks once the old channels are actually gone.
      debugPrint('Could not prepare notification channels: $e');
    }
  }

  /// Fires a reminder immediately so the user can confirm the pop-up and the
  /// tone without waiting for a real deadline.
  ///
  /// The alert carries an open task's id as its payload so the action buttons
  /// do something real: "Mark done" finishes that task and "Snooze 1h" sets a
  /// fresh reminder for it. Returns the task title used, or null when there
  /// was no open task to attach.
  Future<String?> showTestReminder() async {
    await _ensureReady();
    try {
      final db = LocalDb();
      await db.open();
      final open = await db.all();
      Task? sample;
      for (final task in open) {
        if (!task.done) {
          sample = task;
          break;
        }
      }

      await _plugin.show(
        _testId,
        sample == null ? 'Reminder test' : 'Reminder test: ${sample.title}',
        sample == null
            ? 'This is how a deadline reminder pops up and sounds.'
            : 'Try Mark done or Snooze 1h on this task.',
        _details,
        payload: sample?.id,
      );
      return sample?.title;
    } catch (e) {
      debugPrint('Could not show the test reminder: $e');
      return null;
    }
  }

  // --- App updates ---------------------------------------------------------

  /// Posts a single "Update available" notification for [update].
  ///
  /// Returns true only when a notification was actually shown. The same update
  /// (same version, or the APK fingerprint when no version is published) is
  /// never posted twice, so repeated launch/manual checks stay quiet.
  Future<bool> showUpdateNotification(AppUpdate update) async {
    try {
      if (!await areNotificationsEnabled()) return false;
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString(_shownUpdateKey) == update.updateKey) return false;

      await _ensureReady();
      final body = update.latestVersion == null
          ? 'A new version is ready — tap to install.'
          : 'Version ${update.latestVersion} is ready — tap to install.';
      // Carry the exact version/url across the tap, including a cold start.
      final info = jsonEncode(<String, dynamic>{
        'key': update.updateKey,
        'url': update.url,
        'version': update.latestVersion,
      });
      await _plugin.show(
        _updateId,
        'Update available',
        body,
        _updateDetails,
        payload: '$_updatePayloadPrefix$info',
      );
      await prefs.setString(_shownUpdateKey, update.updateKey);
      return true;
    } catch (e) {
      debugPrint('Could not show the update notification: $e');
      return false;
    }
  }

  /// Handles a tap on the update notification, in either isolate.
  Future<void> _handleUpdateTap(String info) async {
    if (info.isEmpty) return;
    try {
      await _ensureReady();
      await _plugin.cancel(_updateId);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_pendingUpdateKey, info);
      updateTapped.value = true;
    } catch (e) {
      debugPrint('Could not record the update tap: $e');
    }
  }

  /// Handles a notification tap that cold-started the app. The platform
  /// callback may run in a background isolate, so also read the launch payload
  /// on the main isolate as a fallback.
  Future<void> handleLaunchNotification() async {
    try {
      final details = await _plugin.getNotificationAppLaunchDetails();
      final payload = details?.notificationResponse?.payload;
      if (payload != null && payload.startsWith(_updatePayloadPrefix)) {
        await _handleUpdateTap(payload.substring(_updatePayloadPrefix.length));
      }
    } catch (e) {
      debugPrint('Could not read the launch notification: $e');
    }
  }

  /// Returns the update a notification was tapped for, clearing the flag.
  Future<AppUpdate?> takePendingUpdate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_pendingUpdateKey);
      if (raw == null || raw.isEmpty) {
        updateTapped.value = false;
        return null;
      }
      await prefs.remove(_pendingUpdateKey);
      updateTapped.value = false;

      try {
        final info = jsonDecode(raw) as Map<String, dynamic>;
        return AppUpdate(
          latestVersion: info['version'] as String?,
          url: (info['url'] as String?) ?? Company.apkUrl,
          updateKey: (info['key'] as String?) ?? raw,
        );
      } catch (_) {
        // Older/foreign payloads were just the update key.
        return AppUpdate(url: Company.apkUrl, updateKey: raw);
      }
    } catch (e) {
      debugPrint('Could not read the pending update: $e');
      return null;
    }
  }

  /// Opens Android's settings page for the reminder channel, where the user
  /// can change its sound, importance and pop-up behaviour. Returns false on
  /// platforms that have no such screen.
  Future<bool> openReminderChannelSettings() async {
    await _ensureReady();
    try {
      return await _native.invokeMethod<bool>(
            'openChannelSettings',
            {'channelId': _reminderChannelId},
          ) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException catch (e) {
      debugPrint('Could not open notification channel settings: $e');
      return false;
    }
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
