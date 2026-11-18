import 'package:flutter/material.dart';

import '../services/platform_bridge.dart';
import '../theme.dart';
import '../utils/company.dart';

/// Small credit line shown at the bottom of the app and on the loading page.
/// Tapping it opens the company website in the phone's browser.
class PoweredByFooter extends StatelessWidget {
  const PoweredByFooter({
    super.key,
    this.padding = const EdgeInsets.symmetric(vertical: 8),
  });

  final EdgeInsetsGeometry padding;

  Future<void> _openWebsite(BuildContext context) async {
    final opened = await PlatformBridge.openUrl(Company.websiteUrl);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content:
            Text('Could not open a browser. Visit ${Company.websiteLabel}'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Semantics(
        button: true,
        label: 'Open ${Company.name} website',
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () => _openWebsite(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: 'Powered by ',
                    style: TextStyle(color: Ink0.muted.withValues(alpha: 0.75)),
                  ),
                  TextSpan(
                    text: Company.name,
                    style: TextStyle(
                      color: Ink0.muted,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.1,
                    ),
                  ),
                ],
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11, height: 1.35),
            ),
          ),
        ),
      ),
    );
  }
}
