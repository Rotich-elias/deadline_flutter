import 'package:flutter/material.dart';

import '../services/platform_bridge.dart';
import '../theme.dart';
import '../utils/company.dart';
import 'powered_by_footer.dart';
import 'privacy_page.dart';

/// Small About screen: app identity, installed version and the company link.
class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  String? _version;

  @override
  void initState() {
    super.initState();
    PlatformBridge.appVersion().then((version) {
      if (!mounted || version == null || version.isEmpty) return;
      setState(() => _version = version);
    });
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
