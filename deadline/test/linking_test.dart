import 'package:deadline/models/note.dart';
import 'package:deadline/models/task.dart';
import 'package:deadline/utils/linking.dart';
import 'package:flutter_test/flutter_test.dart';

Note _note(String id, String title, {String? body}) =>
    Note(id: id, title: title, body: body);

Task _task(String id, String title, {String? notes}) => Task(
      id: id,
      title: title,
      notes: notes,
      dueAt: DateTime.utc(2026, 11, 20, 17),
    );

void main() {
  group('LinkParser.parse', () {
    test('finds note and task links with offsets into the raw string', () {
      const text = 'See [[Exact Note Title]] and [[tasks:Pay rent]].';
      final links = LinkParser.parse(text);

      expect(links, hasLength(2));
      expect(links.first.target, 'Exact Note Title');
      expect(links.first.isTask, isFalse);
      const noteToken = '[[Exact Note Title]]';
      expect(links.first.start, text.indexOf(noteToken));
      expect(links.first.end, text.indexOf(noteToken) + noteToken.length);
      expect(text.substring(links.first.start, links.first.end), noteToken);

      expect(links.last.target, 'Pay rent');
      expect(links.last.isTask, isTrue);
      const taskToken = '[[tasks:Pay rent]]';
      expect(text.substring(links.last.start, links.last.end), taskToken);
      expect(links.last.end, links.last.start + taskToken.length);
    });

    test('returns non-overlapping links in document order', () {
      const text = '[[A]][[B]] and [[C]]';
      final links = LinkParser.parse(text);

      expect(links.map((l) => l.target), ['A', 'B', 'C']);
      expect(links[0].end, links[1].start);
      expect(text.substring(links[1].start, links[1].end), '[[B]]');
      expect(links[2].start, greaterThan(links[1].end));
    });

    test('trims titles and accepts a case-insensitive tasks: prefix', () {
      final links = LinkParser.parse(
        '[[  Spaced Title  ]] [[TASKS: Submit report ]] [[Tasks:Trip]]',
      );

      expect(
        links.map((l) => (l.target, l.isTask)),
        [
          ('Spaced Title', false),
          ('Submit report', true),
          ('Trip', true),
        ],
      );
    });

    test('ignores malformed, empty and null input without throwing', () {
      expect(LinkParser.parse(null), isEmpty);
      expect(LinkParser.parse(''), isEmpty);
      expect(LinkParser.parse('   '), isEmpty);
      expect(
        LinkParser.parse('[[ ]] [[   ]] [[tasks:]] [[TASKS:  ]]'),
        isEmpty,
      );
      expect(LinkParser.parse('[[unclosed and [single] and []'), isEmpty);
      expect(LinkParser.parse('[[A]B]] [[[C]]] [[[[D]]]]'), isEmpty);
    });
  });

  group('LinkParser.strip', () {
    test('keeps the display title and drops the brackets and task prefix', () {
      expect(
        LinkParser.strip('See [[Exact Note Title]] and [[tasks:Pay rent]].'),
        'See Exact Note Title and Pay rent.',
      );
    });

    test('leaves malformed links untouched and handles null/empty', () {
      expect(LinkParser.strip(null), '');
      expect(LinkParser.strip(''), '');
      expect(
        LinkParser.strip('a [[ ]] b [[unclosed'),
        'a [[ ]] b [[unclosed',
      );
      expect(LinkParser.strip('[[[C]]]'), '[[[C]]]');
    });

    test('preserves surrounding text and existing markup', () {
      expect(
        LinkParser.strip('<b>[[A]]</b>\n- [[tasks:B]]'),
        '<b>A</b>\n- B',
      );
    });
  });

  group('BacklinkIndex', () {
    test('finds note-body backlinks with trimmed, case-insensitive titles', () {
      final index = BacklinkIndex([
        _note('n1', 'Meeting notes',
            body: 'See [[Ideas]] and [[tasks:Pay rent]]'),
        _note('n2', 'Other', body: 'Nothing here'),
      ]);

      expect(
        index.forTarget('  ideas  ', isTask: false),
        [
          const Backlink(
            sourceId: 'n1',
            sourceTitle: 'Meeting notes',
            sourceIsTask: false,
          ),
        ],
      );
      expect(index.forTarget('IDEAS', isTask: true), isEmpty);
    });

    test('finds backlinks in task notes and separates note from task targets',
        () {
      final index = BacklinkIndex(
        [_note('n1', 'Budget note', body: '[[tasks:Pay rent]]')],
        [
          _task('t1', 'Pay rent',
              notes: 'See [[Budget]] and [[tasks:Pay rent]]'),
        ],
      );

      expect(
        index.forTarget('Budget', isTask: false).map((b) => b.sourceId),
        ['t1'],
      );
      expect(
        index.forTarget('pay rent', isTask: true).map((b) => b.sourceId),
        ['n1', 't1'],
      );
    });

    test('scans task titles as sources too', () {
      final index = BacklinkIndex([], [
        _task('t2', 'Follow up [[Project X]]'),
      ]);

      expect(
        index.forTarget('project x', isTask: false),
        [
          const Backlink(
            sourceId: 't2',
            sourceTitle: 'Follow up [[Project X]]',
            sourceIsTask: true,
          ),
        ],
      );
    });

    test('lists a source once per target even when linked repeatedly', () {
      final index = BacklinkIndex([
        _note('n1', 'A', body: '[[Same]] then [[same]] again'),
        _note('n2', 'B', body: '[[SAME]]'),
      ]);

      expect(
        index.forTarget('Same', isTask: false),
        [
          const Backlink(
            sourceId: 'n1',
            sourceTitle: 'A',
            sourceIsTask: false,
          ),
          const Backlink(
            sourceId: 'n2',
            sourceTitle: 'B',
            sourceIsTask: false,
          ),
        ],
      );
    });

    test('identical note and task titles stay separate targets', () {
      final index = BacklinkIndex([
        _note('n1', 'N', body: '[[Shared]]'),
        _note('n2', 'M', body: '[[tasks:Shared]]'),
      ]);

      expect(index.forTarget('shared', isTask: false).single.sourceId, 'n1');
      expect(index.forTarget('shared', isTask: true).single.sourceId, 'n2');
    });

    test('outgoing returns the links written in a note body', () {
      final note = _note('n1', 'N', body: 'Hi [[A]] [[tasks:B]]');
      final index = BacklinkIndex([note], []);

      expect(index.outgoing(note).map((l) => l.target), ['A', 'B']);
      expect(index.outgoing(note).map((l) => l.isTask), [false, true]);
      expect(BacklinkIndex().outgoing(_note('empty', 'Empty')), isEmpty);
    });

    test('empty and malformed sources produce no backlinks or throws', () {
      final index = BacklinkIndex(
        [
          _note('n1', 'N'),
          _note('n2', 'M', body: '[[ ]] [[unclosed [[tasks:]]'),
        ],
        [_task('t1', 'T')],
      );

      expect(index.forTarget('', isTask: false), isEmpty);
      expect(index.forTarget('anything', isTask: false), isEmpty);
      expect(index.forTarget('anything', isTask: true), isEmpty);
      expect(BacklinkIndex().forTarget('x', isTask: false), isEmpty);
    });
  });
}
