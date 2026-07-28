import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/task_store.dart';
import '../sync/sync_service.dart';
import '../theme.dart';

Future<void> showSyncSettings(BuildContext context, SyncService sync) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Ink0.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _SettingsSheet(sync: sync),
  );
}

class _SettingsSheet extends StatefulWidget {
  const _SettingsSheet({required this.sync});
  final SyncService sync;

  @override
  State<_SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<_SettingsSheet> {
  late final _url = TextEditingController(text: widget.sync.baseUrl);
  late final _token = TextEditingController(text: widget.sync.token);
  late SyncMethod _method = widget.sync.method;

  @override
  void dispose() {
    _url.dispose();
    _token.dispose();
    super.dispose();
  }

  String get _status {
    final s = widget.sync;
    switch (s.state) {
      case SyncState.off:
        return 'Sync is off. Tasks stay on this phone.';
      case SyncState.working:
        return 'Syncing…';
      case SyncState.offline:
        return 'No connection. Changes will go up when you are back online.';
      case SyncState.failed:
        return s.lastError ?? 'Last sync failed.';
      case SyncState.idle:
        final at = s.lastSyncedAt?.toLocal();
        return at == null
            ? 'Connected. Not synced yet.'
            : 'Last synced ${DateFormat('d MMM, h:mm a').format(at)}';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 22,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: ListenableBuilder(
        listenable: widget.sync,
        builder: (context, _) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Sync',
                style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    color: Ink0.text)),
            const SizedBox(height: 6),
            Text(
              'The app works fully offline. Turn on sync to keep the same '
              'list across your devices.',
              style: TextStyle(fontSize: 13, color: Ink0.muted, height: 1.4),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _MethodChip(
                  label: 'Off',
                  selected: _method == SyncMethod.off,
                  onTap: () => setState(() => _method = SyncMethod.off),
                ),
                _MethodChip(
                  label: 'Google Drive',
                  selected: _method == SyncMethod.drive,
                  onTap: () => setState(() => _method = SyncMethod.drive),
                ),
                _MethodChip(
                  label: 'Your server',
                  selected: _method == SyncMethod.server,
                  onTap: () => setState(() => _method = SyncMethod.server),
                ),
              ],
            ),
            const SizedBox(height: 18),
            if (_method == SyncMethod.off)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () async {
                    await widget.sync.turnOff();
                    if (context.mounted) Navigator.of(context).pop();
                  },
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: BorderSide(color: Ink0.line),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Confirm sync off'),
                ),
              )
            else if (_method == SyncMethod.drive)
              _DriveSection(sync: widget.sync)
            else
              _ServerSection(sync: widget.sync, url: _url, token: _token),
            if (_method != SyncMethod.off) ...[
              const SizedBox(height: 14),
              Text(_status,
                  style: TextStyle(
                      fontSize: 12.5, color: Ink0.muted, height: 1.4)),
            ],
          ],
        ),
      ),
    );
  }
}

class _MethodChip extends StatelessWidget {
  const _MethodChip(
      {required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 13)),
      selected: selected,
      onSelected: (_) => onTap(),
      backgroundColor: Ink0.surfaceHi,
      selectedColor: Ink0.line,
      side: BorderSide(color: selected ? Colors.transparent : Ink0.line),
      labelStyle: TextStyle(color: Ink0.text),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    );
  }
}

class _DriveSection extends StatelessWidget {
  const _DriveSection({required this.sync});
  final SyncService sync;

  @override
  Widget build(BuildContext context) {
    final account = sync.driveAccount;
    if (account == null) {
      return SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: () => sync.signInWithGoogle(),
          icon: const Icon(Icons.login, size: 18),
          label: const Text('Sign in with Google'),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Ink0.surfaceHi,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(Icons.account_circle, color: Ink0.muted, size: 28),
              const SizedBox(width: 10),
              Expanded(
                child: Text(account.email,
                    style: TextStyle(fontSize: 13.5, color: Ink0.text)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => sync.syncNow(),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: BorderSide(color: Ink0.line),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Sync now'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton(
                onPressed: () => sync.signOutOfGoogle(),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: BorderSide(color: Ink0.line),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Sign out'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ServerSection extends StatelessWidget {
  const _ServerSection(
      {required this.sync, required this.url, required this.token});
  final SyncService sync;
  final TextEditingController url;
  final TextEditingController token;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: url,
          keyboardType: TextInputType.url,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: 'Server address',
            hintText: 'https://tasks.example.com',
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: token,
          autocorrect: false,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Access token'),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: sync.configured ? () => sync.syncNow() : null,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: BorderSide(color: Ink0.line),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Sync now'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                onPressed: () async {
                  await sync.saveServerSettings(
                      url: url.text, tok: token.text);
                  if (context.mounted) Navigator.of(context).pop();
                },
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Save'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

Future<void> showAppearanceSettings(BuildContext context, AppTheme appTheme) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Ink0.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _AppearanceSheet(appTheme: appTheme),
  );
}

class _AppearanceSheet extends StatelessWidget {
  const _AppearanceSheet({required this.appTheme});
  final AppTheme appTheme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 22,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: ListenableBuilder(
        listenable: appTheme,
        builder: (context, _) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Appearance',
                style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    color: Ink0.text)),
            const SizedBox(height: 16),
            _ThemeOption(
              label: 'System',
              icon: Icons.brightness_auto,
              selected: appTheme.mode == ThemeMode.system,
              onTap: () => appTheme.setMode(ThemeMode.system),
            ),
            const SizedBox(height: 8),
            _ThemeOption(
              label: 'Light',
              icon: Icons.light_mode_outlined,
              selected: appTheme.mode == ThemeMode.light,
              onTap: () => appTheme.setMode(ThemeMode.light),
            ),
            const SizedBox(height: 8),
            _ThemeOption(
              label: 'Dark',
              icon: Icons.dark_mode_outlined,
              selected: appTheme.mode == ThemeMode.dark,
              onTap: () => appTheme.setMode(ThemeMode.dark),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThemeOption extends StatelessWidget {
  const _ThemeOption({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: selected ? Ink0.surfaceHi : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? Ink0.text : Ink0.line),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: Ink0.text),
            const SizedBox(width: 10),
            Expanded(
              child: Text(label,
                  style: TextStyle(fontSize: 14.5, color: Ink0.text)),
            ),
            if (selected) Icon(Icons.check, size: 18, color: Ink0.text),
          ],
        ),
      ),
    );
  }
}

Future<void> showDigestSettings(BuildContext context, TaskStore store) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Ink0.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _DigestSheet(store: store),
  );
}

class _DigestSheet extends StatefulWidget {
  const _DigestSheet({required this.store});
  final TaskStore store;

  @override
  State<_DigestSheet> createState() => _DigestSheetState();
}

class _DigestSheetState extends State<_DigestSheet> {
  late bool _enabled = widget.store.digestEnabled;
  late TimeOfDay _time = TimeOfDay(
    hour: widget.store.digestHour,
    minute: widget.store.digestMinute,
  );

  Future<void> _pickTime() async {
    final t = await showTimePicker(context: context, initialTime: _time);
    if (t != null) setState(() => _time = t);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 22,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Daily digest',
              style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  color: Ink0.text)),
          const SizedBox(height: 6),
          Text(
            'One notification each morning with how many tasks are open '
            'and overdue — instead of a ping for every reminder.',
            style: TextStyle(fontSize: 13, color: Ink0.muted, height: 1.4),
          ),
          const SizedBox(height: 18),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _enabled,
            onChanged: (v) => setState(() => _enabled = v),
            activeThumbColor: Ink0.text,
            title: Text('Send daily digest',
                style: TextStyle(color: Ink0.text, fontSize: 14)),
          ),
          const SizedBox(height: 6),
          InkWell(
            onTap: _enabled ? _pickTime : null,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                color: Ink0.surfaceHi,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.access_time,
                      size: 16,
                      color: _enabled ? Ink0.muted : Ink0.line),
                  const SizedBox(width: 8),
                  Text(_time.format(context),
                      style: TextStyle(
                          fontSize: 14,
                          color: _enabled ? Ink0.text : Ink0.muted)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () async {
                await widget.store.saveDigestSettings(
                  enabled: _enabled,
                  hour: _time.hour,
                  minute: _time.minute,
                );
                if (context.mounted) Navigator.of(context).pop();
              },
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape:
                    RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Save',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }
}
