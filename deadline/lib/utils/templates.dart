import 'package:intl/intl.dart';

/// A built-in starting structure for a note. Templates are deliberately just
/// text: applying one opens the normal editor with a draft already filled in,
/// and nothing is saved until the user taps Save.
class NoteTemplate {
  const NoteTemplate({
    required this.id,
    required this.title,
    required this.description,
    required this.body,
    this.tag,
  });

  final String id;
  final String title;
  final String description;
  final String body;
  final String? tag;

  /// `{{date}}` and `{{weekday}}` are replaced with [now] in local time so a
  /// journal opened tonight is dated correctly even just after midnight UTC.
  ({String title, String body, String? tag}) apply({DateTime? now}) {
    final at = now ?? DateTime.now();
    String fill(String text) => text
        .replaceAll('{{date}}', DateFormat('d MMM y').format(at))
        .replaceAll('{{weekday}}', DateFormat('EEEE').format(at));
    return (
      title: fill(title),
      body: fill(body),
      tag: tag == null ? null : fill(tag!),
    );
  }
}

const builtInNoteTemplates = <NoteTemplate>[
  NoteTemplate(
    id: 'journal',
    title: '{{date}} — Journal',
    description: 'A quick daily reflection with prompts.',
    tag: 'journal',
    body: '''What happened today
- Write a line about today

What I learned
- One thing I learned

Grateful for
- One good thing

Tomorrow
- One thing to do''',
  ),
  NoteTemplate(
    id: 'meeting',
    title: 'Meeting agenda — {{date}}',
    description: 'Attendees, topics, decisions and follow-ups.',
    tag: 'meeting',
    body: '''Attendees
- Name

Agenda
- Topic to cover

Decisions
- Decision made

Action items
- Owner and due date''',
  ),
  NoteTemplate(
    id: 'project',
    title: 'Project outline',
    description: 'Goal, milestones, tasks and risks.',
    tag: 'project',
    body: '''Goal
- What success looks like

Milestones
- Milestone and date

Tasks
- Next action

Risks / blockers
- What could get in the way''',
  ),
  NoteTemplate(
    id: 'shopping',
    title: 'Shopping list',
    description: 'A short list you can tick off as you go.',
    tag: 'errands',
    body: '''- Item to buy
- Item to buy
- Item to buy''',
  ),
];
