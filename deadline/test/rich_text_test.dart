import 'package:deadline/models/note.dart';
import 'package:deadline/theme.dart';
import 'package:deadline/ui/note_form_sheet.dart';
import 'package:deadline/utils/markup.dart';
import 'package:deadline/utils/rich_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('markup helpers', () {
    test('plain notes are unchanged', () {
      const body = '[  ] Parks and recreation\n[v] Other mommy';
      expect(stripMarkup(body), body);
      expect(Note(id: 'n', title: 'N', body: body).plainBody, body);
    });

    test('tags are stripped and bullet lines get a bullet', () {
      const body = '<b>Important</b> <i>note</i>\n- <u>first</u>\n- second';
      expect(stripMarkup(body), 'Important note\n• first\n• second');
    });

    test('wrapping a selection and unwrapping it again', () {
      final wrapped = toggleTag('Hello world', 6, 11, 'b');
      expect(wrapped.text, 'Hello <b>world</b>');
      expect(wrapped.start, 9);
      expect(wrapped.end, 14);

      final unwrapped =
          toggleTag(wrapped.text, wrapped.start, wrapped.end, 'b');
      expect(unwrapped.text, 'Hello world');
    });

    test('a collapsed caret gets an empty pair ready for typing', () {
      final result = toggleTag('Hello', 5, 5, 'i');
      expect(result.text, 'Hello<i></i>');
      expect(result.start, 8);
      expect(result.end, 8);
    });

    test('bullets toggle on and off the caret line only', () {
      final added = toggleBullet('one\ntwo\nthree', 5);
      expect(added.text, 'one\n- two\nthree');
      expect(added.start, 7);

      final removed = toggleBullet(added.text, added.start);
      expect(removed.text, 'one\ntwo\nthree');
      expect(removed.start, 5);
    });
  });

  group('rich text rendering', () {
    TextSpan span(String body) => buildRichSpan(
          body,
          base: const TextStyle(fontSize: 16),
          highlight: const Color(0xFFE4C441),
          bullet: Colors.grey,
        );

    test('inline tags become styled spans', () {
      final children = span('a <b>bold</b> and <i>italic</i>').children!;
      expect(children.map((s) => (s as TextSpan).text),
          ['a ', 'bold', ' and ', 'italic']);
      expect((children[1] as TextSpan).style?.fontWeight, FontWeight.w700);
      expect((children[3] as TextSpan).style?.fontStyle, FontStyle.italic);
    });

    test('unknown or unmatched tags are shown literally', () {
      final children = span('x <script>y</script> </b>z').children!;
      expect(children.map((s) => (s as TextSpan).text).join(),
          'x <script>y</script> </b>z');
    });

    test('bullet lines render a leading bullet span', () {
      final children = span('- <u>step</u>').children!;
      expect((children.first as TextSpan).text, '•  ');
      expect((children[1] as TextSpan).text, 'step');
      expect((children[1] as TextSpan).style?.decoration,
          TextDecoration.underline);
    });
  });

  group('note editor', () {
    testWidgets('format buttons insert markup around the typed text',
        (tester) async {
      Note? saved;
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async => saved = await showNoteForm(context),
              child: const Text('Open form'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('Open form'));
      await tester.pumpAndSettle();
      final title = find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.hintText == 'Title');
      await tester.enterText(title, 'Draft');

      final body = find.byWidgetPredicate((w) =>
          w is TextField && w.decoration?.hintText == 'Write something…');
      await tester.enterText(body, 'Read this');
      final controller = tester.widget<TextField>(body).controller!;
      controller.selection =
          TextSelection(baseOffset: 0, extentOffset: controller.text.length);
      await tester.pump();
      await tester.tap(find.byTooltip('Bold'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(body).controller!.text,
          contains('<b>Read this</b>'));

      final save = find.text('Add note');
      await tester.ensureVisible(save);
      await tester.pumpAndSettle();
      await tester.tap(save);
      await tester.pumpAndSettle();

      expect(saved, isNotNull);
      final result = saved!;
      expect(result.body, contains('<b>Read this</b>'));
      expect(result.plainBody, 'Read this');
    });
  });
}
