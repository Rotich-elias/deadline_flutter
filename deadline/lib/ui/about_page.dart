import 'package:flutter/material.dart';

import '../models/app_update.dart';
import '../services/platform_bridge.dart';
import '../services/update_service.dart';
import '../theme.dart';
import '../utils/company.dart';
import 'powered_by_footer.dart';
import 'privacy_page.dart';
import 'update_dialog.dart';

/// Small About screen: app identity, installed version and the company link.
class AboutPage extends StatefulWidget {
  const AboutPage({super.key, this.updateService});

  /// Injectable so tests (and alternate deployments) can point at a fake API.
  final UpdateService? updateService;

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  String? _version;
  bool _checking = false;
  AppUpdate? _available;

  UpdateService get _updates => widget.updateService ?? const UpdateService();

  @override
  void initState() {
    super.initState();
    PlatformBridge.appVersion().then((version) {
      if (!mounted || version == null || version.isEmpty) return;
      setState(() => _version = version);
    });
  }

  Future<void> _checkForUpdates() async {
    if (_checking) return;
    setState(() => _checking = true);

    final current = _version ?? await PlatformBridge.appVersion();
    if (current == null || current.isEmpty) {
      if (mounted) {
        setState(() => _checking = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not read the installed version.')),
        );
      }
      return;
    }

    final update = await _updates.check(current);
    if (!mounted) return;
    setState(() {
      _checking = false;
      _available = update;
    });
    if (update == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You’re up to date.')),
      );
    } else {
      await offerUpdate(context, update: update, currentVersion: current);
    }
  }

  Future<void> _openWebsite() async {
    final opened = await PlatformBridge.openUrl(Company.websiteUrl);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content:
            Text('Could not open a browser. Visit ${Company.websiteLabel}'),
      ));
    }
  }

  Future<void> _openPrivacy() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const PrivacyPolicyPage(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Ink0.bg,
      appBar: AppBar(
        backgroundColor: Ink0.bg,
        surfaceTintColor: Colors.transparent,
        title: const Text('About'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        children: [
          Card(
            color: Ink0.surface,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: Ink0.line),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
              child: Column(
                children: [
                  Icon(Icons.edit_calendar_outlined,
                      size: 52, color: Ink0.text),
                  const SizedBox(height: 12),
                  Text(
                    'Deadlines&Notes',
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      color: Ink0.text,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'Offline-first deadline and note tracker',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: Ink0.muted),
                  ),
                  if (_version != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      'Version $_version',
                      style: TextStyle(fontSize: 12, color: Ink0.muted),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Card(
            color: Ink0.surface,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: Ink0.line),
            ),
            child: Column(
              children: [
                ListTile(
                  key: const Key('about-website'),
                  leading: Icon(Icons.public_outlined, color: Ink0.muted),
                  title: Text('Website',
                      style: TextStyle(fontSize: 14, color: Ink0.text)),
                  subtitle: Text(Company.websiteLabel,
                      style: TextStyle(fontSize: 12, color: Ink0.muted)),
                  trailing:
                      Icon(Icons.open_in_new, size: 16, color: Ink0.muted),
                  onTap: _openWebsite,
                ),
                Divider(height: 1, color: Ink0.line),
                ListTile(
                  key: const Key('about-privacy'),
                  leading: Icon(Icons.privacy_tip_outlined, color: Ink0.muted),
                  title: Text('Privacy policy',
                      style: TextStyle(fontSize: 14, color: Ink0.text)),
                  trailing: Icon(Icons.chevron_right, color: Ink0.muted),
                  onTap: _openPrivacy,
                ),
                Divider(height: 1, color: Ink0.line),
                ListTile(
                  key: const Key('about-update'),
                  leading: _checking
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Ink0.muted,
                          ),
                        )
                      : Icon(Icons.system_update_alt_outlined,
                          color: Ink0.muted),
                  title: Text('Check for updates',
                      style: TextStyle(fontSize: 14, color: Ink0.text)),
                  subtitle: _available == null
                      ? null
                      : Text(
                          _available!.latestVersion == null
                              ? 'New version available'
                              : 'Version ${_available!.latestVersion} available',
                          style: TextStyle(fontSize: 12, color: Ink0.muted),
                        ),
                  trailing: Icon(Icons.chevron_right, size: 16, color: Ink0.muted),
                  onTap: _checking ? null : _checkForUpdates,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const PoweredByFooter(padding: EdgeInsets.symmetric(vertical: 16)),
        ],
      ),
    );
  }
}
