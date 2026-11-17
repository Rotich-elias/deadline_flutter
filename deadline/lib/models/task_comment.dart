import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// One note in a task's discussion. Comments live inside the task row as JSON,
/// like checklist items, so they travel with the normal task sync payload.
class TaskComment {
  const TaskComment({
    required this.id,
    required this.author,
    required this.body,
    required this.createdAt,
  });

  factory TaskComment.create({
    required String author,
    required String body,
  }) =>
      TaskComment(
        id: _uuid.v4(),
        author: author.trim().isEmpty ? 'Me' : author.trim(),
        body: body.trim(),
        createdAt: DateTime.now().toUtc(),
      );

  final String id;
  final String author;
  final String body;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'author': author,
        'body': body,
        'created_at': createdAt.toIso8601String(),
      };

  factory TaskComment.fromJson(Map<String, dynamic> json) => TaskComment(
        id: (json['id'] ?? '').toString(),
        author: (json['author'] ?? 'Me').toString(),
        body: (json['body'] ?? '').toString(),
        createdAt:
            DateTime.tryParse((json['created_at'] ?? '').toString())?.toUtc() ??
                DateTime.now().toUtc(),
      );
}
