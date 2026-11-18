import 'package:deadline/services/note_import.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('quick note shortcut arriving while running is counted',
      (tester) async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('deadline/notifications'),
      (call) async => call.method == 'takeSharedNotes' ? <Object?>[] : null,
    );

    final inbox = SharedNotesInbox.instance;
    await inbox.start();
    final before = inbox.quickNoteRequests;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
      'deadline/notifications',
      const StandardMethodCodec()
          .encodeMethodCall(const MethodCall('quickNote')),
      (_) {},
    );
    await tester.pumpAndSettle();

    expect(inbox.quickNoteRequests, before + 1);
  });
}
