import 'package:deadline/models/task.dart';
import 'package:deadline/theme.dart';
import 'package:deadline/ui/task_form_sheet.dart';
import 'package:deadline/utils/smart_extract.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

TextField _field(WidgetTester tester, String hint) =>
    tester.widget<TextField>(find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText == hint));

void main() {
  group('local smart extraction', () {
    final now = DateTime(2026, 11, 17, 10);

    test('relative day, time and hashtag are pulled out of the title', () {
      final draft = extractSmartDraft(
        'Submit report tomorrow 5pm #ICT3052',
        now: now,
      );
      expect(draft.title, 'Submit report');
      expect(draft.tag, 'ICT3052');
      expect(draft.due, DateTime(2026, 11, 18, 17));
      expect(draft.checklist, isEmpty);
    });

    test('checklist markers become steps and other lines become notes', () {
      final draft = extractSmartDraft(
        'Email lecturer today\n'
        '- collect receipts\n'
        '[x] print form\n'
        '1. upload file\n'
        'Extra note',
        now: now,
      );
      expect(draft.title, 'Email lecturer');
      expect(
          draft.checklist, ['collect receipts', 'print form', 'upload file']);
      expect(draft.notes, 'Extra note');
      expect(draft.due, DateTime(2026, 11, 17, 17));
    });

    test('ISO date and 24-hour time are understood', () {
      final draft = extractSmartDraft('2026-11-20 14:30 Pay rent', now: now);
      expect(draft.title, 'Pay rent');
      expect(draft.due, DateTime(2026, 11, 20, 14, 30));
    });

    test('slash dates, named months and a tag line are understood', () {
      final slash = extractSmartDraft(
        '17/11/2026 meeting at 9:30 am',
        now: now,
      );
      expect(slash.title, 'meeting');
      expect(slash.due, DateTime(2026, 11, 17, 9, 30));

      final named = extractSmartDraft(
        'Tag: Work\nFinish slides next week',
        now: now,
      );
      expect(named.tag, 'Work');
      expect(named.title, 'Finish slides');
      expect(named.due, DateTime(2026, 11, 24, 17));
    });

    test('a bare time that has passed rolls to tomorrow', () {
      final draft = extractSmartDraft('call at 8am', now: now);
      expect(draft.title, 'call');
      expect(draft.due, DateTime(2026, 11, 18, 8));
    });

    test('a due-prefixed date line leaves no connective in the title', () {
      final draft = extractSmartDraft('Due: 20 Nov 2026\nPay fees', now: now);
      expect(draft.title, 'Pay fees');
      expect(draft.due, DateTime(2026, 11, 20, 17));
    });

    test('empty input yields an empty draft', () {
      expect(extractSmartDraft('   \n  ', now: now).isEmpty, isTrue);
    });
  });

  group('smart paste UI', () {
    testWidgets('paste fills the editable form and saves a real task',
        (tester) async {
      Task? saved;
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async => saved = await showTaskForm(context),
              child: const Text('Open form'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('Open form'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Paste text to fill this form'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byWidgetPredicate((w) =>
            w is TextField &&
            (w.decoration?.hintText ?? '').startsWith('e.g. Submit report')),
        'Submit report tomorrow 5pm #ICT3052\n'
        '- collect receipts\n'
        '- email lecturer',
      );
      await tester.tap(find.text('Extract'));
      await tester.pumpAndSettle();

      expect(_field(tester, 'e.g. ICT3052 forensics report').controller?.text,
          'Submit report');
      expect(_field(tester, 'Tag — e.g. ICT3052').controller?.text, 'ICT3052');
      expect(find.text('0/2'), findsOneWidget);

      await tester.ensureVisible(find.text('Add task'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add task'));
      await tester.pumpAndSettle();

      expect(saved, isNotNull);
      final result = saved!;
      expect(result.title, 'Submit report');
      expect(result.tag, 'ICT3052');
      expect(result.checklist.map((i) => i.title),
          ['collect receipts', 'email lecturer']);
      expect(result.dueLocal.hour, 17);
    });
  });
}
