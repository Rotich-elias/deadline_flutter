import 'package:flutter/material.dart';

import '../data/task_store.dart';
import '../models/shared_list.dart';
import '../sync/collaboration_api.dart';
import '../theme.dart';

/// Server-backed shared lists. This page only appears when server sync is
/// configured; offline and Drive users keep the exact same UI as before.
class SharedListsPage extends StatefulWidget {
  const SharedListsPage({
    super.key,
    required this.api,
    required this.store,
  });

  final CollaborationApi api;
  final TaskStore store;

  @override
  State<SharedListsPage> createState() => _SharedListsPageState();
}

class _SharedListsPageState extends State<SharedListsPage> {
  List<SharedList> _lists = const [];
  final Set<int> _expanded = <int>{};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<SharedList> _enrich(SharedList list) async {
    try {
      final members = await widget.api.members(list.id);
      final invitations = await widget.api.invitations(list.id);
      final taskIds = await widget.api.tasks(list.id);
      return list.copyWith(
        members: members,
        invitations: invitations,
        taskIds: taskIds,
      );
    } catch (_) {
      // The list itself is still usable even if one detail call fails.
      return list;
    }
  }

  Future<void> _reload() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final lists = await widget.api.lists();
      final enriched = <SharedList>[
        for (final list in lists) await _enrich(list),
      ];
      if (!mounted) return;
      setState(() {
        _lists = enriched;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _reloadOne(int id) async {
    try {
      final list = await _enrich(await widget.api.show(id));
      if (!mounted) return;
      setState(() {
        _lists = [
          for (final existing in _lists)
            if (existing.id == id) list else existing,
        ];
      });
    } catch (e) {
      _toast(e.toString());
    }
  }

  Future<String?> _prompt(
    String title,
    String hint, {
    String action = 'Save',
    bool obscure = false,
  }) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Ink0.surface,
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          obscureText: obscure,
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: Text(action),
          ),
        ],
      ),
    );
  }

  Future<void> _createList() async {
    final name = await _prompt('New shared list', 'e.g. Family tasks');
    if (name == null || name.trim().isEmpty) return;
    try {
      final list = await widget.api.create(name);
      _toast('Created "${list.name}".');
      await _reload();
    } catch (e) {
      _toast(e.toString());
    }
  }

  Future<void> _acceptInvite() async {
    final token = await _prompt(
      'Accept an invitation',
      'Paste the invitation token',
      action: 'Accept',
    );
    if (token == null || token.trim().isEmpty) return;
    try {
      final list = await widget.api.accept(token);
      _toast('Joined "${list.name}".');
      await _reload();
    } catch (e) {
      _toast(e.toString());
    }
  }

  Future<void> _lookupAccount() async {
    final navigator = Navigator.of(context);
    final email = await _prompt('Find an account', 'person@example.com',
        action: 'Look up');
    if (email == null || email.trim().isEmpty) return;
    try {
      final account = await widget.api.lookup(email);
      if (account == null) {
        _toast('No account found for that email.');
        return;
      }
      await navigator.push<void>(
        MaterialPageRoute<void>(
          builder: (_) => AlertDialog(
            backgroundColor: Ink0.surface,
            title: const Text('Account found'),
            content: Text(account.toString()),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      _toast(e.toString());
    }
  }

  Future<void> _invite(SharedList list) async {
    final email = await _prompt('Invite by email', 'person@example.com',
        action: 'Invite');
    if (email == null || email.trim().isEmpty) return;
    try {
      final invitation = await widget.api.invite(list.id, email);
      _toast('Invitation sent to ${invitation.email}.');
      await _reloadOne(list.id);
    } catch (e) {
      _toast(e.toString());
    }
  }

  Future<void> _attach(SharedList list) async {
    final available = widget.store.tasks
        .where((t) => !t.deleted && !list.taskIds.contains(t.id))
        .toList(growable: false);
    if (available.isEmpty) {
      _toast('All of your deadlines are already on this list.');
      return;
    }
    final taskId = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        backgroundColor: Ink0.surface,
        title: const Text('Attach a deadline'),
        children: [
          for (final task in available)
            SimpleDialogOption(
              key: Key('attach-${task.id}'),
              onPressed: () => Navigator.pop(dialogContext, task.id),
              child: Text(task.title, style: TextStyle(color: Ink0.text)),
            ),
        ],
      ),
    );
    if (taskId == null) return;
    try {
      await widget.api.attach(list.id, taskId);
      _toast('Deadline attached.');
      await _reloadOne(list.id);
    } catch (e) {
      _toast(e.toString());
    }
  }

  Future<void> _detach(SharedList list, String taskId) async {
    try {
      await widget.api.detach(list.id, taskId);
      _toast('Deadline detached from this list.');
      await _reloadOne(list.id);
    } catch (e) {
      _toast(e.toString());
    }
  }

  String _titleFor(String id) {
    for (final task in widget.store.tasks) {
      if (task.id == id) return task.title;
    }
    return id.substring(0, id.length.clamp(0, 8));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Ink0.bg,
      appBar: AppBar(
        backgroundColor: Ink0.bg,
        title: const Text('Shared lists'),
        actions: [
          IconButton(
            tooltip: 'Find an account',
            onPressed: _lookupAccount,
            icon: const Icon(Icons.person_search),
          ),
          IconButton(
            tooltip: 'Accept invitation',
            onPressed: _acceptInvite,
            icon: const Icon(Icons.mark_email_read_outlined),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createList,
        icon: const Icon(Icons.add),
        label: const Text('New list'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.cloud_off, size: 48, color: Ink0.muted),
                        const SizedBox(height: 14),
                        Text(_error!,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Ink0.text, fontSize: 14)),
                        const SizedBox(height: 14),
                        FilledButton(
                          onPressed: _reload,
                          child: const Text('Try again'),
                        ),
                      ],
                    ),
                  ),
                )
              : _lists.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.groups_outlined,
                                size: 52, color: Ink0.muted),
                            const SizedBox(height: 14),
                            Text(
                              'No shared lists yet',
                              style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                  color: Ink0.text),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Create one to attach deadlines, or accept an '
                              'invitation with the token you were sent.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 13, color: Ink0.muted),
                            ),
                          ],
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _reload,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
                        children: [
                          for (final list in _lists)
                            Card(
                              key: Key('shared-list-${list.id}'),
                              color: Ink0.surface,
                              elevation: 0,
                              margin: const EdgeInsets.symmetric(vertical: 5),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                                side: BorderSide(color: Ink0.line),
                              ),
                              child: ExpansionTile(
                                key: Key('shared-expand-${list.id}'),
                                initiallyExpanded: _expanded.contains(list.id),
                                onExpansionChanged: (open) => setState(() {
                                  if (open) {
                                    _expanded.add(list.id);
                                  } else {
                                    _expanded.remove(list.id);
                                  }
                                }),
                                iconColor: Ink0.muted,
                                collapsedIconColor: Ink0.muted,
                                leading: Icon(Icons.folder_shared_outlined,
                                    color: Ink0.muted),
                                title: Text(list.name,
                                    style: TextStyle(
                                        fontSize: 14, color: Ink0.text)),
                                subtitle: Text(
                                  list.ownerEmail ?? 'Shared with you',
                                  style: TextStyle(
                                      fontSize: 11.5, color: Ink0.muted),
                                ),
                                children: [
                                  _detailRow(
                                    icon: Icons.people_outline,
                                    label: 'MEMBERS',
                                    children: list.members.isEmpty
                                        ? const ['No members yet']
                                        : [
                                            for (final member in list.members)
                                              '${member.email} · ${member.role}${member.status == 'accepted' ? '' : ' (${member.status})'}',
                                          ],
                                  ),
                                  _detailRow(
                                    icon: Icons.mail_outline,
                                    label: 'INVITATIONS',
                                    children: list.invitations.isEmpty
                                        ? const ['No invitations yet']
                                        : [
                                            for (final invite
                                                in list.invitations)
                                              '${invite.email} · ${invite.status}',
                                          ],
                                  ),
                                  _detailRow(
                                    icon: Icons.check_circle_outline,
                                    label: 'DEADLINES',
                                    children: list.taskIds.isEmpty
                                        ? const ['No deadlines attached']
                                        : [
                                            for (final id in list.taskIds)
                                              _titleFor(id),
                                          ],
                                    taskIds: list.taskIds,
                                    list: list,
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                        16, 4, 16, 12),
                                    child: Wrap(
                                      spacing: 8,
                                      children: [
                                        TextButton.icon(
                                          onPressed: () => _invite(list),
                                          icon: const Icon(Icons.person_add_alt,
                                              size: 16),
                                          label: const Text('Invite'),
                                        ),
                                        TextButton.icon(
                                          onPressed: () => _attach(list),
                                          icon: const Icon(Icons.add_link,
                                              size: 16),
                                          label: const Text('Attach deadline'),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
    );
  }

  Widget _detailRow({
    required IconData icon,
    required String label,
    required List<String> children,
    SharedList? list,
    List<String> taskIds = const [],
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: Ink0.muted),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                      color: Ink0.muted)),
            ],
          ),
          const SizedBox(height: 4),
          for (var i = 0; i < children.length; i++)
            Row(
              children: [
                Expanded(
                  child: Text(children[i],
                      style: TextStyle(fontSize: 12.5, color: Ink0.text)),
                ),
                if (list != null && i < taskIds.length)
                  IconButton(
                    tooltip: 'Detach',
                    visualDensity: VisualDensity.compact,
                    icon: Icon(Icons.link_off, size: 16, color: Ink0.muted),
                    onPressed: () => _detach(list, taskIds[i]),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
