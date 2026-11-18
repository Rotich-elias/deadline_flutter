import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:deadline/services/app_lock_service.dart';
import 'package:deadline/services/note_draft_service.dart';
import 'package:deadline/services/platform_bridge.dart';
import 'package:deadline/theme.dart';
import 'package:deadline/ui/note_form_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('note draft survival', () {
    test('save, peek and take round-trip then clear', () async {
      SharedPreferences.setMockInitialValues({});
      final drafts = NoteDraftService();
      const draft = NoteDraft(
        title: 'Camera draft',
        body: 'Body text',
        tag: 'work',
        notebook: 'Ideas',
        labels: ['a', 'b'],
        draftId: 'draft-1',
        existingId: null,
      );

      await drafts.save(draft);
      expect((await drafts.peek())?.title, 'Camera draft');
      final taken = await drafts.take();
      expect(taken?.draftId, 'draft-1');
      expect(taken?.labels, ['a', 'b']);
      expect(await drafts.peek(), isNull);
    });

    test('corrupt saved draft is ignored', () async {
      SharedPreferences.setMockInitialValues({NoteDraftService.key: '{oops'});
      expect(await NoteDraftService().peek(), isNull);
    });
  });

  group('camera channel', () {
    test('native errors become CameraCaptureException', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('deadline/platform'),
        (call) async {
          if (call.method == 'capturePhoto') {
            throw PlatformException(
                code: 'camera_start', message: 'Could not open camera');
          }
          return null;
        },
      );

      expect(
        PlatformBridge.capturePhoto(),
        throwsA(isA<CameraCaptureException>()
            .having((e) => e.message, 'message', 'Could not open camera')),
      );
    });

    test('pending capture path is consumed from native', () async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('deadline/platform'),
        (call) async {
          calls.add(call);
          return call.method == 'takePendingCapture'
              ? '/cache/captures/photo.jpg'
              : null;
        },
      );

      expect(await PlatformBridge.takePendingCapture(),
          '/cache/captures/photo.jpg');
      expect(calls.single.method, 'takePendingCapture');
    });
  });

  test('external capture suppression expires with its timeout', () async {
    final lock = AppLockService();
    expect(lock.externalCaptureActive, isFalse);

    lock.beginExternalCapture(timeout: const Duration(milliseconds: 40));
    expect(lock.externalCaptureActive, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(lock.externalCaptureActive, isFalse);

    lock.beginExternalCapture();
    expect(lock.externalCaptureActive, isTrue);
    lock.endExternalCapture();
    expect(lock.externalCaptureActive, isFalse);
  });

  testWidgets('a draft interrupted by the camera is restored into the form',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({
      NoteDraftService.key:
          '{"title":"Camera draft","body":"Body text","tag":"work",'
              '"notebook":"Ideas","labels":["a"],"draftId":"draft-2"}',
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('deadline/platform'),
      (call) async => null,
    );

    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.dark),
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async => await showNoteForm(context),
            child: const Text('Open form'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Open form'));
    await tester.pumpAndSettle();

    final title = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText == 'Title');
    final body = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText == 'Write something…');
    expect(tester.widget<TextField>(title).controller!.text, 'Camera draft');
    expect(tester.widget<TextField>(body).controller!.text, 'Body text');
  });
}
