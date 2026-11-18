import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:deadline/data/local_db.dart';
import 'package:deadline/data/task_store.dart';
import 'package:deadline/models/task.dart';
import 'package:deadline/services/location_alerts.dart';
import 'package:deadline/services/platform_bridge.dart';
import 'package:deadline/theme.dart';
import 'package:deadline/ui/calendar_page.dart';
import 'package:deadline/ui/note_form_sheet.dart';

const _channel = MethodChannel('deadline/platform');

void _answer(String method, String code, String message) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, (call) async {
    if (call.method == method) {
      throw PlatformException(code: code, message: message);
    }
    return null;
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('bridge permission errors are reported, not swallowed', () {
    test('voice memo start surfaces the microphone message', () async {
      _answer('startAudioRecording', 'microphone_permission',
          'Microphone access is off. Allow Microphone in Settings to record a voice memo.');
      await expectLater(
        PlatformBridge.startAudioRecording(),
        throwsA(isA<BridgeException>()
            .having((e) => e.code, 'code', 'microphone_permission')
            .having((e) => e.message, 'message', contains('Microphone'))),
      );
    });

    test('voice memo stop surfaces a revoked microphone', () async {
      _answer('stopAudioRecording', 'microphone_permission',
          'Microphone access was revoked.');
      await expectLater(
        PlatformBridge.stopAudioRecording(),
        throwsA(isA<BridgeException>()),
      );
    });

    test('transcribe reports no speech-to-text app', () async {
      _answer('transcribe', 'speech_unavailable',
          'No speech-to-text app is installed on this phone.');
      await expectLater(
        PlatformBridge.transcribe(),
        throwsA(isA<BridgeException>()
            .having((e) => e.message, 'message', contains('speech-to-text'))),
      );
    });

    test('calendar read reports a revoked permission', () async {
      _answer('calendarEvents', 'calendar_permission',
          'Calendar access was revoked. Allow it in Settings to import deadlines.');
      await expectLater(
        PlatformBridge.calendarEvents(
            from: DateTime(2026, 11), to: DateTime(2026, 11, 30)),
        throwsA(isA<BridgeException>()
            .having((e) => e.code, 'code', 'calendar_permission')),
      );
    });

    test('calendar write reports a revoked permission', () async {
      _answer('addCalendarEvent', 'calendar_write_permission',
          'Calendar access was revoked. Allow it in Settings to export deadlines.');
      await expectLater(
        PlatformBridge.addCalendarEvent(
            title: 'Review', start: DateTime(2026, 11, 18)),
        throwsA(isA<BridgeException>()),
      );
    });

    test('current location reports a revoked permission', () async {
      _answer('currentLocation', 'location_permission',
          'Location access is off. Allow Location in Settings for place reminders.');
      await expectLater(
        PlatformBridge.currentLocation(),
        throwsA(isA<BridgeException>()),
      );
    });

    test('geofence registration reports background location denial', () async {
      _answer('addProximityAlert', 'background_location_permission',
          'Choose “Allow all the time” in Settings so place reminders work when the app is closed.');
      await expectLater(
        PlatformBridge.addProximityAlert(
          id: 't1',
          latitude: -1.2,
          longitude: 36.8,
          radiusMeters: 200,
          label: 'Work',
        ),
        throwsA(isA<BridgeException>()
            .having((e) => e.code, 'code', 'background_location_permission')),
      );
    });

    test('missing plugin still behaves as unsupported, not an error', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, null);
      expect(await PlatformBridge.startAudioRecording(), isNull);
      expect(
          await PlatformBridge.addCalendarEvent(
              title: 'x', start: DateTime(2026)),
          isFalse);
    });
  });

  group('location errors reach the UI notifier', () {
    test('register records the message and a later success clears it',
        () async {
      LocationAlerts.lastError.value = null;
      _answer('addProximityAlert', 'location_permission',
          'Location access is off. Allow Location in Settings for place reminders.');
      await LocationAlerts.register(Task(
        id: 't1',
        title: 'Pay rent',
        dueAt: DateTime(2026, 11, 18).toUtc(),
        locationAlert: const LocationAlert(
            label: 'Town', latitude: -1.2, longitude: 36.8, radiusMeters: 200),
      ));
      expect(
          LocationAlerts.lastError.value, contains('Location access is off'));

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, (call) async => true);
      await LocationAlerts.unregister('t1');
      expect(LocationAlerts.lastError.value, isNull);
    });
  });

  group('UI shows the native reason', () {
    testWidgets('voice memo button shows the microphone message',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      SharedPreferences.setMockInitialValues({});
      _answer('startAudioRecording', 'microphone_permission',
          'Microphone access is off. Allow Microphone in Settings to record a voice memo.');

      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showNoteForm(context),
              child: const Text('Open form'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('Open form'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Voice memo'));
      await tester.pumpAndSettle();

      expect(
        find.text(
            'Microphone access is off. Allow Microphone in Settings to record a voice memo.'),
        findsOneWidget,
      );
    });

    testWidgets('calendar export shows the calendar permission message',
        (tester) async {
      final store = TaskStore(
        _EmptyTasksDb([
          Task(
              id: 't1',
              title: 'Pay rent',
              dueAt: DateTime(2026, 11, 18, 9).toUtc()),
        ]),
        startTicker: false,
      );
      await store.load();
      _answer('addCalendarEvent', 'calendar_write_permission',
          'Calendar access is off. Allow Calendar in Settings to export deadlines.');

      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: Scaffold(body: CalendarPage(store: store)),
      ));
      await tester.pumpAndSettle();

      // Open the overflow menu then tap "Export deadlines to device".
      await tester.tap(find.byIcon(Icons.sync));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Export deadlines to device'));
      await tester.pumpAndSettle();

      expect(
        find.text(
            'Calendar access is off. Allow Calendar in Settings to export deadlines.'),
        findsOneWidget,
      );
    });
  });

  group('Android declares background location', () {
    test('manifest keeps the ACCESS_BACKGROUND_LOCATION permission', () {
      final candidates = [
        File('android/app/src/main/AndroidManifest.xml'),
        File('../android/app/src/main/AndroidManifest.xml'),
      ];
      final manifest = candidates.firstWhere(
        (f) => f.existsSync(),
        orElse: () => throw StateError('AndroidManifest.xml not found'),
      );
      expect(manifest.readAsStringSync(),
          contains('android.permission.ACCESS_BACKGROUND_LOCATION'));
    });
  });
}

class _EmptyTasksDb extends LocalDb {
  _EmptyTasksDb(this._tasks);

  final List<Task> _tasks;

  @override
  Future<List<Task>> all() async => List.unmodifiable(_tasks);

  @override
  Future<List<Task>> archivedTasks() async => const [];

  @override
  Future<List<String>> distinctTags() async => const [];
}
