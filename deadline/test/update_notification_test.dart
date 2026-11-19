import 'dart:convert';

import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:deadline/models/app_update.dart';
import 'package:deadline/services/notifications.dart';
import 'package:deadline/utils/company.dart';

const _payloadPrefix = 'update:';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final calls = <MethodCall>[];
  Map<dynamic, dynamic>? launchDetails;

  setUp(() {
    calls.clear();
    launchDetails = null;
    SharedPreferences.setMockInitialValues(const {});
    Notifications.instance.updateTapped.value = false;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();

    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('flutter_timezone'),
      (call) async {
        calls.add(call);
        return call.method == 'getLocalTimezone' ? 'UTC' : null;
      },
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('dexterous.com/flutter/local_notifications'),
      (call) async {
        calls.add(call);
        switch (call.method) {
          case 'getNotificationAppLaunchDetails':
            return launchDetails;
          case 'initialize':
          case 'areNotificationsEnabled':
          case 'canScheduleExactNotifications':
            return true;
          default:
            return null;
        }
      },
    );
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  test('posts one update notification per discovered version', () async {
    const update = AppUpdate(latestVersion: '1.0.25', url: Company.apkUrl);

    expect(await Notifications.instance.showUpdateNotification(update), isTrue);

    final shown = calls.where((c) => c.method == 'show').toList();
    expect(shown, hasLength(1));
    final args = shown.single.arguments! as Map<dynamic, dynamic>;
    expect(args['id'], -424244);
    expect(args['title'], 'Update available');
    expect(args['body'], contains('1.0.25'));

    final payload = args['payload'] as String;
    expect(payload, startsWith(_payloadPrefix));
    final info =
        jsonDecode(payload.substring(_payloadPrefix.length)) as Map<String, dynamic>;
    expect(info['key'], '1.0.25');
    expect(info['url'], Company.apkUrl);
    expect(info['version'], '1.0.25');

    // A repeat check for the same release stays silent.
    expect(await Notifications.instance.showUpdateNotification(update), isFalse);
    expect(calls.where((c) => c.method == 'show'), hasLength(1));

    // A newer release gets its own notification.
    const newer = AppUpdate(latestVersion: '1.0.26', url: Company.apkUrl);
    expect(await Notifications.instance.showUpdateNotification(newer), isTrue);
    expect(calls.where((c) => c.method == 'show'), hasLength(2));
  });

  test('a tap hands the update to the app and clears the notification', () async {
    const update = AppUpdate(latestVersion: '1.0.25', url: Company.apkUrl);
    await Notifications.instance.showUpdateNotification(update);
    final shown = calls.firstWhere((c) => c.method == 'show');
    final payload = (shown.arguments! as Map<dynamic, dynamic>)['payload'] as String;

    await notificationBackgroundHandler(NotificationResponse(
      notificationResponseType: NotificationResponseType.selectedNotification,
      id: -424244,
      payload: payload,
    ));

    expect(Notifications.instance.updateTapped.value, isTrue);
    expect(calls.where((c) => c.method == 'cancel'), isNotEmpty);

    final pending = await Notifications.instance.takePendingUpdate();
    expect(pending, isNotNull);
    expect(pending!.latestVersion, '1.0.25');
    expect(pending.url, Company.apkUrl);
    expect(Notifications.instance.updateTapped.value, isFalse);
    expect(await Notifications.instance.takePendingUpdate(), isNull);
  });

  test('a cold-start launch payload records the pending update', () async {
    const update = AppUpdate(latestVersion: '1.0.25', url: Company.apkUrl);
    await Notifications.instance.showUpdateNotification(update);
    final shown = calls.firstWhere((c) => c.method == 'show');
    final payload = (shown.arguments! as Map<dynamic, dynamic>)['payload'] as String;

    launchDetails = <dynamic, dynamic>{
      'notificationLaunchedApp': true,
      'notificationResponse': <dynamic, dynamic>{
        'notificationId': -424244,
        'notificationResponseType':
            NotificationResponseType.selectedNotification.index,
        'payload': payload,
      },
    };

    await Notifications.instance.handleLaunchNotification();
    final pending = await Notifications.instance.takePendingUpdate();
    expect(pending?.latestVersion, '1.0.25');
  });

  test('a fingerprint-only update produces a generic prompt after a tap',
      () async {
    const url = 'https://example.test/download/deadlines-notes';
    const update = AppUpdate(url: url, updateKey: '"v2"|Wed, 18 Nov 2026');
    expect(await Notifications.instance.showUpdateNotification(update), isTrue);

    final shown = calls.firstWhere((c) => c.method == 'show');
    final args = shown.arguments! as Map<dynamic, dynamic>;
    expect(args['body'], 'A new version is ready — tap to install.');

    final payload = args['payload'] as String;
    await notificationBackgroundHandler(NotificationResponse(
      notificationResponseType: NotificationResponseType.selectedNotification,
      id: -424244,
      payload: payload,
    ));

    final pending = await Notifications.instance.takePendingUpdate();
    expect(pending!.latestVersion, isNull);
    expect(pending.url, url);
    expect(pending.updateKey, update.updateKey);
  });
}
