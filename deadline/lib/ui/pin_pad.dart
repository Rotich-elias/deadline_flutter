import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/app_lock_service.dart';
import '../theme.dart';

/// Opens the PIN pad in a bottom sheet and returns the entered PIN, or null
/// when the user dismisses it. [validate] returns an error message to keep the
/// sheet open, or null to accept the PIN.
Future<String?> showPinSheet(
  BuildContext context, {
  required String title,
  String? subtitle,
  Future<String?> Function(String pin)? validate,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Ink0.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: PinPad(
        title: title,
        subtitle: subtitle,
        validate: validate,
      ),
    ),
  );
}

/// A 4-digit PIN entry pad, shared by the lock screen and the settings flows.
/// The dots fill as digits are tapped and the PIN submits itself at length,
/// so there is no extra confirm button.
class PinPad extends StatefulWidget {
  const PinPad({
    super.key,
    required this.title,
    this.subtitle,
    this.validate,
    this.icon,
    this.onBiometric,
    this.popOnSuccess = true,
    this.onSuccess,
  });

  final String title;
  final String? subtitle;
  final Future<String?> Function(String pin)? validate;
  final IconData? icon;
  final VoidCallback? onBiometric;

  /// When true the pad pops its route with the entered PIN on success.
  final bool popOnSuccess;
  final ValueChanged<String>? onSuccess;

  @override
  State<PinPad> createState() => _PinPadState();
}

class _PinPadState extends State<PinPad> {
  String _digits = '';
  String? _error;
  bool _busy = false;

  void _tap(String digit) {
    if (_busy || _digits.length >= AppLockService.pinLength) return;
    HapticFeedback.selectionClick();
    setState(() {
      _digits += digit;
      _error = null;
    });
    if (_digits.length == AppLockService.pinLength) _submit();
  }

  void _backspace() {
    if (_busy || _digits.isEmpty) return;
    setState(() {
      _digits = _digits.substring(0, _digits.length - 1);
      _error = null;
    });
  }

  Future<void> _submit() async {
    final pin = _digits;
    setState(() => _busy = true);

    String? error;
    try {
      error = await widget.validate?.call(pin);
    } catch (_) {
      error = 'Could not check that PIN. Try again.';
    }
    if (!mounted) return;

    if (error == null) {
      setState(() => _busy = false);
      widget.onSuccess?.call(pin);
      if (mounted && widget.popOnSuccess) Navigator.of(context).pop(pin);
      return;
    }

    HapticFeedback.mediumImpact();
    if (!mounted) return;
    setState(() {
      _error = error;
      _digits = '';
      _busy = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.icon != null) ...[
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: Ink0.surfaceHi,
              shape: BoxShape.circle,
              border: Border.all(color: Ink0.line),
            ),
            child: Icon(widget.icon, size: 27, color: Ink0.muted),
          ),
          const SizedBox(height: 16),
        ],
        Text(
          widget.title,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
            color: Ink0.text,
          ),
        ),
        if (widget.subtitle != null) ...[
          const SizedBox(height: 7),
          Text(
            widget.subtitle!,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13.5, color: Ink0.muted, height: 1.4),
          ),
        ],
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < AppLockService.pinLength; i++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                width: 14,
                height: 14,
                margin: const EdgeInsets.symmetric(horizontal: 7),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i < _digits.length ? Ink0.text : Colors.transparent,
                  border: Border.all(
                    color: i < _digits.length ? Ink0.text : Ink0.line,
                    width: 1.5,
                  ),
                ),
              ),
          ],
        ),
        SizedBox(
          height: 34,
          child: Center(
            child: AnimatedOpacity(
              opacity: _error == null ? 0 : 1,
              duration: const Duration(milliseconds: 150),
              child: Text(
                _error ?? '',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFFFF6B6B),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
        SizedBox(
          width: 280,
          child: _Keypad(
            onDigit: _tap,
            onBackspace: _backspace,
            onBiometric: widget.onBiometric,
            enabled: !_busy,
          ),
        ),
      ],
    );
  }
}

class _Keypad extends StatelessWidget {
  const _Keypad({
    required this.onDigit,
    required this.onBackspace,
    required this.onBiometric,
    required this.enabled,
  });

  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final VoidCallback? onBiometric;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: 12);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _row(['1', '2', '3']),
        gap,
        _row(['4', '5', '6']),
        gap,
        _row(['7', '8', '9']),
        gap,
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            if (onBiometric != null)
              _PadKey(
                onTap: enabled ? onBiometric : null,
                tooltip: 'Use fingerprint',
                child: Icon(Icons.fingerprint, size: 28, color: Ink0.text),
              )
            else
              const SizedBox(width: _PadKey.size),
            _PadKey(
              onTap: enabled ? () => onDigit('0') : null,
              child: Text(
                '0',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                  color: Ink0.text,
                ),
              ),
            ),
            _PadKey(
              onTap: enabled ? onBackspace : null,
              tooltip: 'Delete',
              child:
                  Icon(Icons.backspace_outlined, size: 22, color: Ink0.muted),
            ),
          ],
        ),
      ],
    );
  }

  Widget _row(List<String> digits) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (final d in digits)
          _PadKey(
            onTap: enabled ? () => onDigit(d) : null,
            child: Text(
              d,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w600,
                color: Ink0.text,
              ),
            ),
          ),
      ],
    );
  }
}

class _PadKey extends StatelessWidget {
  const _PadKey({
    required this.child,
    this.onTap,
    this.tooltip,
  });

  static const double size = 70;

  final Widget child;
  final VoidCallback? onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final key = Material(
      color: Ink0.surfaceHi,
      shape: CircleBorder(side: BorderSide(color: Ink0.line)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: Center(child: child),
        ),
      ),
    );

    if (tooltip == null) return key;
    return Tooltip(message: tooltip!, child: key);
  }
}
