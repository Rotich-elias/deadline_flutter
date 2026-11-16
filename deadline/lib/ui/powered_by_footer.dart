import 'package:flutter/material.dart';

import '../theme.dart';

/// Small credit line shown at the bottom of the app and on the loading page.
class PoweredByFooter extends StatelessWidget {
  const PoweredByFooter({
    super.key,
    this.padding = const EdgeInsets.symmetric(vertical: 8),
  });

  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: 'Powered by ',
              style: TextStyle(color: Ink0.muted.withValues(alpha: 0.75)),
            ),
            TextSpan(
              text: 'teto technologies',
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
    );
  }
}
