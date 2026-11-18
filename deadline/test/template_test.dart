import 'package:deadline/models/note.dart';
import 'package:deadline/theme.dart';
import 'package:deadline/ui/note_form_sheet.dart';
import 'package:deadline/ui/template_picker.dart';
import 'package:deadline/utils/templates.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 11, 17, 19, 30);

  group('built-in note templates', () {
    test('there is a small, uniquely named set', () {
      expect(builtInNoteTemplates.length, greaterThanOrEqualTo(4));
      expect(builtInNoteTemplates.map((t) => t.id).toSet(),
          hasLength(builtInNoteTemplates.length));
      for (final template in builtInNoteTemplates) {
        expect(template.title, isNotEmpty);
        expect(template.description, isNotEmpty);
        expect(template.body, contains('\n- '));
      }
    });

    test('placeholders are filled in local time', () {
      final draft = builtInNoteTemplates.first.apply(now: now);
      expect(draft.title, contains('17 Nov 2026'));
      expect(draft.body, isNot(contains('{{')));
      expect(draft.tag, 'journal');
    });

    test('templates do not reference weekdays unless they use the placeholder',
        () {
      for (final template in builtInNoteTemplates) {
        final draft = template.apply(now: now);
        expect(draft.title, isNot(contains('{{weekday}}')));
        expect(draft.body, isNot(contains('{{date}}')));
      }
    });

    test('applying a template creates no note — only a text draft', () {
      final draft = builtInNoteTemplates
          .firstWhere((t) => t.id == 'project')
          .apply(now: now);
      expect(draft.title, 'Project outline');
      expect(draft.body, contains('Milestones'));
      expect(draft.tag, 'project');
    });
  });

  group('template UI', () {
    testWidgets('initial values pre-fill an editable note form',
        (tester) async {
      Note? saved;
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async => saved = await showNoteForm(
                context,
                initialTitle: 'Draft title',
                initialBody: '- first step',
                initialTag: 'draft',
              ),
              child: const Text('Open form'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('Open form'));
      await tester.pumpAndSettle();
      final title = find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.hintText == 'Title');
      final body = find.byWidgetPredicate((w) =>
          w is TextField && w.decoration?.hintText == 'Write something…');
      expect(tester.widget<TextField>(title).controller!.text, 'Draft title');
      expect(tester.widget<TextField>(body).controller!.text, '- first step');

      await tester.enterText(title, 'Edited title');
      await tester.enterText(body, '- edited step');
      await tester.pumpAndSettle();
      final save = find.text('Add note');
      await tester.ensureVisible(save);
      await tester.pumpAndSettle();
      await tester.tap(save);
      await tester.pumpAndSettle();

      expect(saved, isNotNull);
      expect(saved!.title, 'Edited title');
      expect(saved!.body, '- edited step');
    });

    testWidgets('picking a template opens its draft in the editor',
        (tester) async {
      Note? saved;
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                final template = await showTemplatePicker(context);
                if (template == null) return;
                final draft = template.apply(now: now);
                saved = await showNoteForm(
                  context,
                  initialTitle: draft.title,
                  initialBody: draft.body,
                  initialTag: draft.tag,
                );
              },
              child: const Text('Templates'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('Templates'));
      await tester.pumpAndSettle();
      expect(find.text('Start from a template'), findsOneWidget);
      await tester.tap(find.text('Project outline'));
      await tester.pumpAndSettle();

      final body = find.byWidgetPredicate((w) =>
          w is TextField && w.decoration?.hintText == 'Write something…');
      expect(tester.widget<TextField>(body).controller!.text,
          contains('Milestones'));

      final save = find.text('Add note');
      await tester.ensureVisible(save);
      await tester.pumpAndSettle();
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(saved!.tag, 'project');
    });
  });
}
