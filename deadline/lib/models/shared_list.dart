// Read-only views of the collaboration API payloads. All parsing is defensive:
// a missing relationship or a differently-cased key simply yields empty data
// rather than crashing the page.

class SharedMember {
  const SharedMember({
    required this.email,
    this.userId,
    this.name,
    this.role = 'member',
    this.status = 'accepted',
  });

  final String email;
  final Object? userId;
  final String? name;
  final String role;
  final String status;

  bool get isOwner => role == 'owner';

  factory SharedMember.fromJson(Map<String, dynamic> json) => SharedMember(
        email: (json['email'] ?? '').toString(),
        userId: json['user_id'],
        name: json['name'] as String?,
        role: (json['role'] ?? 'member').toString(),
        status: (json['status'] ?? 'accepted').toString(),
      );

  Map<String, dynamic> toJson() => {
        'email': email,
        if (userId != null) 'user_id': userId,
        if (name != null) 'name': name,
        'role': role,
        'status': status,
      };
}

class SharedInvitation {
  const SharedInvitation({
    required this.id,
    required this.email,
    required this.role,
    required this.status,
    this.token,
  });

  final int id;
  final String email;
  final String role;
  final String status;
  final String? token;

  bool get pending => status == 'pending';

  factory SharedInvitation.fromJson(Map<String, dynamic> json) =>
      SharedInvitation(
        id: (json['id'] as num?)?.toInt() ?? 0,
        email: (json['email'] ?? '').toString(),
        role: (json['role'] ?? 'member').toString(),
        status: (json['status'] ?? 'pending').toString(),
        token: json['token'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'role': role,
        'status': status,
        if (token != null) 'token': token,
      };
}

class SharedList {
  const SharedList({
    required this.id,
    required this.name,
    this.ownerEmail,
    this.ownerName,
    this.members = const [],
    this.invitations = const [],
    this.taskIds = const [],
  });

  final int id;
  final String name;
  final String? ownerEmail;
  final String? ownerName;
  final List<SharedMember> members;
  final List<SharedInvitation> invitations;
  final List<String> taskIds;

  factory SharedList.fromJson(Map<String, dynamic> json) {
    final owner = _map(json['owner']);
    return SharedList(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: (json['name'] ?? 'Untitled list').toString(),
      ownerEmail: (json['owner_email'] as String?)?.isNotEmpty == true
          ? json['owner_email'] as String
          : owner['email'] as String?,
      ownerName: owner['name'] as String?,
      members: _list(json['members'])
          .map((m) => SharedMember.fromJson(m))
          .toList(growable: false),
      invitations: _list(json['invitations'])
          .map((i) => SharedInvitation.fromJson(i))
          .toList(growable: false),
      taskIds: _list(json['tasks'])
          .map((t) => (t['id'] ?? '').toString())
          .where((id) => id.isNotEmpty)
          .toList(growable: false),
    );
  }

  SharedList copyWith({
    List<SharedMember>? members,
    List<SharedInvitation>? invitations,
    List<String>? taskIds,
  }) =>
      SharedList(
        id: id,
        name: name,
        ownerEmail: ownerEmail,
        ownerName: ownerName,
        members: members ?? this.members,
        invitations: invitations ?? this.invitations,
        taskIds: taskIds ?? this.taskIds,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (ownerEmail != null) 'owner_email': ownerEmail,
        if (ownerName != null)
          'owner': {'name': ownerName, 'email': ownerEmail},
        'members': members.map((m) => m.toJson()).toList(),
        'invitations': invitations.map((i) => i.toJson()).toList(),
        'tasks': [
          for (final id in taskIds) {'id': id}
        ],
      };

  static Map<String, dynamic> _map(Object? value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

  static List<Map<String, dynamic>> _list(Object? value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList(growable: false);
  }
}

class SharedAccount {
  const SharedAccount({
    required this.id,
    required this.email,
    this.name,
  });

  final Object? id;
  final String email;
  final String? name;

  factory SharedAccount.fromJson(Map<String, dynamic> json) => SharedAccount(
        id: json['id'],
        email: (json['email'] ?? '').toString(),
        name: json['name'] as String?,
      );

  @override
  String toString() => name == null ? email : '$name <$email>';
}
