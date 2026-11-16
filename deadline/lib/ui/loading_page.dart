import 'package:flutter/material.dart';

import '../theme.dart';
import 'powered_by_footer.dart';

const _accent = Color(0xFF5C8DEF);

/// Branded boot screen shown while the database, reminders, sync settings and
/// appearance preference are loaded. It paints the same background as the
/// native splash, so the hand-off from the platform splash is seamless.
class LoadingPage extends StatefulWidget {
  const LoadingPage({super.key, this.message = 'Getting things ready'});

  /// The branded block, exposed so tests can assert it is centred (the native
  /// splash artwork is positioned to match it).
  static const contentKey = Key('loading-content');

  final String message;

  @override
  State<LoadingPage> createState() => _LoadingPageState();
}

class _LoadingPageState extends State<LoadingPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Ink0.bg,
      // The branded block sits in the exact centre of the window, with no
      // intro animation: the native splash (generated from the same artwork,
      // see assets/splash/) is drawn centred by Android, so the hand-off to
      // this page is a straight pixel-on-pixel continuation.
      // Brand artwork is drawn at fixed sizes (assets/splash/), so the block
      // ignores the user's font-size setting. Otherwise the text would grow
      // ~10% at font scale 1.1 and the splash hand-off would visibly change
      // size. Nothing here is content the user needs scaled.
      body: MediaQuery.withNoTextScaling(
        child: Stack(
          children: [
            Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    key: LoadingPage.contentKey,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _Logo(pulse: _pulse),
                      const SizedBox(height: 26),
                      Text(
                        'Deadlines&Notes',
                        style: TextStyle(
                          fontSize: 25,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.5,
                          color: Ink0.text,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Sorting what is due next.',
                        style: TextStyle(
                          fontSize: 13.5,
                          // Material 3 body letter spacing, mirrored in the
                          // splash artwork (tool/generate_splash.py).
                          letterSpacing: 0.25,
                          color: Ink0.muted,
                        ),
                      ),
                      const SizedBox(height: 34),
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          valueColor:
                              const AlwaysStoppedAnimation<Color>(_accent),
                          backgroundColor: Ink0.line,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          widget.message,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12.5,
                            letterSpacing: 0.25,
                            color: Ink0.muted,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const Align(
              alignment: Alignment.bottomCenter,
              child: SafeArea(
                top: false,
                child: PoweredByFooter(
                  padding: EdgeInsets.only(top: 8, bottom: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo({required this.pulse});

  final Animation<double> pulse;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 132,
      height: 132,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: pulse,
            builder: (context, _) => Container(
              width: 124,
              height: 124,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    _accent.withValues(alpha: 0.10 + 0.10 * pulse.value),
                    _accent.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
          Container(
            width: 92,
            height: 92,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Ink0.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Ink0.line),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.28),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Image.asset(
              'assets/icon/icon.png',
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown when startup fails (database, notifications or preferences). Keeps the
/// branded chrome and offers a retry instead of leaving a black screen.
class BootErrorView extends StatelessWidget {
  const BootErrorView({super.key, required this.onRetry, this.detail});

  final VoidCallback onRetry;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Ink0.bg,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline,
                          size: 44, color: Color(0xFFFF6B6B)),
                      const SizedBox(height: 16),
                      Text(
                        'Could not start',
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                          color: Ink0.text,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Something went wrong while opening your data. '
                        'Nothing has been deleted — try again.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13.5,
                          height: 1.45,
                          color: Ink0.muted,
                        ),
                      ),
                      if (detail != null && detail!.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        Text(
                          detail!,
                          textAlign: TextAlign.center,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            height: 1.4,
                            color: Ink0.muted.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                      const SizedBox(height: 22),
                      FilledButton.icon(
                        onPressed: onRetry,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Try again'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const PoweredByFooter(
              padding: EdgeInsets.only(top: 8, bottom: 12),
            ),
          ],
        ),
      ),
    );
  }
}
