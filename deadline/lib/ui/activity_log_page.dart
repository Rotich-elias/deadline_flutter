import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/activity_log.dart';
import '../theme.dart';

/// Local history of edits made on this device. The log is shared by deadlines
/// and notes, so both tabs can open the same view.
class ActivityLogPage extends StatefulWidget {
  const ActivityLogPage({super.key, required this.log});

  final ActivityLog log;

  @override
  State<ActivityLogPage> createState() => _ActivityLogPageState();
}

class _ActivityLogPageState extends State<ActivityLogPage> {
  List<ActivityEntry> _entries = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final entries = await widget.log.recent();
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _loading = false;
    });
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _clear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Ink0.surface,
        title: const Text('Clear activity history?'),
        content: const Text(
          'This only removes the on-device history. Your notes and deadlines '
          'are not affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.log.clear();
    await _load();
    _toast('Activity history cleared.');
  }

  IconData _iconFor(String action) {
    final lower = action.toLowerCase();
    if (lower.contains('creat')) return Icons.add_circle_outline;
    if (lower.contains('archiv') || lower.contains('delet')) {
      return Icons.archive_outlined;
    }
    if (lower.contains('complet') || lower.contains('reopen')) {
      return Icons.check_circle_outline;
    }
    if (lower.contains('comment')) return Icons.chat_bubble_outline;
    return Icons.edit_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<ActivityEntry>>{};
    for (final entry in _entries) {
      final key = DateFormat('EEEE, d MMM y').format(entry.at.toLocal());
      groups.putIfAbsent(key, () => []).add(entry);
    }

    return Scaffold(
      backgroundColor: Ink0.bg,
      appBar: AppBar(
        backgroundColor: Ink0.bg,
        title: const Text('Activity'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
          if (_entries.isNotEmpty)
            IconButton(
              tooltip: 'Clear history',
              onPressed: _clear,
              icon: const Icon(Icons.delete_sweep_outlined),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _entries.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.history, size: 52, color: Ink0.muted),
                        const SizedBox(height: 14),
                        Text(
                          'No activity yet',
                          style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: Ink0.text),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Creating, editing, completing and archiving notes '
                          'or deadlines will appear here.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 13, color: Ink0.muted),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                  children: [
                    for (final day in groups.keys) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
                        child: Text(
                          day.toUpperCase(),
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.7,
                            color: Ink0.muted,
                          ),
                        ),
                      ),
                      for (final entry in groups[day]!) _row(entry),
                    ],
                  ],
                ),
    );
  }

  Widget _row(ActivityEntry entry) {
    return Card(
      color: Ink0.surface,
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 3),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Ink0.line),
      ),
      child: ListTile(
        dense: true,
        leading: Icon(_iconFor(entry.action), size: 18, color: Ink0.muted),
        title: Text(entry.action,
            style: TextStyle(fontSize: 13.5, color: Ink0.text)),
        subtitle: entry.detail == null || entry.detail!.trim().isEmpty
            ? Text(DateFormat('h:mm a').format(entry.at.toLocal()),
                style: TextStyle(fontSize: 11.5, color: Ink0.muted))
            : Text(
                '${entry.detail} · ${DateFormat('h:mm a').format(entry.at.toLocal())}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, color: Ink0.muted),
              ),
      ),
    );
  }
}
