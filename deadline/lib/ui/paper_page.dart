import 'package:flutter/material.dart';

import '../theme.dart';

const _gold = Color(0xFFE4C441);

/// A note drawn as a sheet from a notebook: soft shadow, bound left edge and
/// faint ruled lines. Used by both the list card and the full-page reader so
/// notes look like Samsung Notes sheets. Notes are identified by their title,
/// never by a generated "page" number.
class PaperPage extends StatelessWidget {
  const PaperPage({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.pinned = false,
    this.showLines = true,
    this.minHeight,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool pinned;
  final bool showLines;
  final double? minHeight;

  @override
  Widget build(BuildContext context) {
    final accent = pinned ? _gold : Ink0.line;
    return Container(
      constraints:
          minHeight == null ? null : BoxConstraints(minHeight: minHeight!),
      decoration: BoxDecoration(
        color: Ink0.surface,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(
          color: pinned ? _gold.withValues(alpha: 0.5) : Ink0.line,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x99000000),
            blurRadius: 9,
            offset: Offset(0, 3),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          if (showLines)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _RuledPainter(line: Ink0.muted, margin: accent),
                ),
              ),
            ),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Container(width: 4, color: accent.withValues(alpha: 0.8)),
          ),
          Padding(
            padding: padding,
            child: child,
          ),
        ],
      ),
    );
  }
}

class _RuledPainter extends CustomPainter {
  const _RuledPainter({required this.line, required this.margin});

  final Color line;
  final Color margin;

  @override
  void paint(Canvas canvas, Size size) {
    final horizontal = Paint()
      ..color = line.withValues(alpha: 0.07)
      ..strokeWidth = 1;
    for (var y = 44.0; y < size.height; y += 26) {
      canvas.drawLine(Offset(10, y), Offset(size.width - 10, y), horizontal);
    }
    final vertical = Paint()
      ..color = margin.withValues(alpha: 0.12)
      ..strokeWidth = 1;
    canvas.drawLine(const Offset(30, 0), Offset(30, size.height), vertical);
  }

  @override
  bool shouldRepaint(covariant _RuledPainter oldDelegate) =>
      oldDelegate.line != line || oldDelegate.margin != margin;
}
