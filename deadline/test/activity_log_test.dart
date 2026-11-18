import 'package:deadline/services/activity_log.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ActivityLog> freshLog() async {
    SharedPreferences.setMockInitialValues({});
    return ActivityLog(await SharedPreferences.getInstance());
  }

  group('ActivityLog', () {
    test('records entries newest first', () async {
      final log = await freshLog();
      await log.record('created', detail: 'Task A', entityId: 'a');
      await log.record('completed', detail: 'Task B');
      final entries = await log.recent();
      expect(entries.map((e) => e.action), ['completed', 'created']);
      expect(entries.last.entityId, 'a');
      expect(entries.last.detail, 'Task A');
    });

    test('honours the limit', () async {
      final log = await freshLog();
      for (var i = 0; i < 5; i++) {
        await log.record('event $i');
      }
      expect((await log.recent(limit: 2)).map((e) => e.action),
          ['event 4', 'event 3']);
      expect((await log.recent(limit: 0)), isEmpty);
    });

    test('survives a new instance reading the same store', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await ActivityLog(prefs).record('synced');
      final again = ActivityLog(await SharedPreferences.getInstance());
      expect((await again.recent()).single.action, 'synced');
    });

    test('clear removes the stored history', () async {
      final log = await freshLog();
      await log.record('one');
      await log.clear();
      expect(await log.recent(), isEmpty);
    });

    test('ignores corrupt stored data', () async {
      SharedPreferences.setMockInitialValues({ActivityLog.storageKey: '{oops'});
      final log = ActivityLog(await SharedPreferences.getInstance());
      expect(await log.recent(), isEmpty);
      await log.record('after corruption');
      expect((await log.recent()).single.action, 'after corruption');
    });

    test('entry json round trips', () {
      final entry = ActivityEntry(
        at: DateTime.utc(2026, 11, 18, 12),
        action: 'archived',
        detail: 'Note',
        entityId: 'n1',
      );
      final copy = ActivityEntry.fromJson(entry.toJson());
      expect(copy.action, 'archived');
      expect(copy.entityId, 'n1');
      expect(copy.at, entry.at);
    });
  });
}
