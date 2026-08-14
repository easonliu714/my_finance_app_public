import 'dart:async';

import 'package:flutter/material.dart';

/// Shows a short-lived toast at the top of the app using the root [Overlay].
///
/// P2.29.1 / #98: transaction feedback must stay above the content and must not
/// cover the bottom number pad. This service intentionally avoids
/// [ScaffoldMessenger] and [SnackBar] positioning so route transitions and
/// scaffold changes do not push the message back to the bottom.
class TopOverlayToast {
  TopOverlayToast._();

  static OverlayEntry? _currentEntry;
  static Timer? _dismissTimer;

  static void show(
    BuildContext context,
    String message, {
    Duration duration = const Duration(milliseconds: 1100),
  }) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    dismiss();

    final entry = OverlayEntry(
      builder: (context) => _TopOverlayToastEntry(message: message),
    );

    _currentEntry = entry;
    overlay.insert(entry);

    _dismissTimer = Timer(duration, () {
      if (_currentEntry == entry) {
        entry.remove();
        _currentEntry = null;
      }
      _dismissTimer = null;
    });
  }

  static void dismiss() {
    _dismissTimer?.cancel();
    _dismissTimer = null;
    _currentEntry?.remove();
    _currentEntry = null;
  }
}

class _TopOverlayToastEntry extends StatelessWidget {
  const _TopOverlayToastEntry({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final topPadding = MediaQuery.paddingOf(context).top;

    return Positioned(
      top: topPadding + 12,
      left: 24,
      right: 24,
      child: IgnorePointer(
        child: Material(
          color: Colors.transparent,
          child: Center(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: theme.colorScheme.inverseSurface.withValues(alpha: 0.94),
                borderRadius: BorderRadius.circular(18),
                boxShadow: const [
                  BoxShadow(
                    blurRadius: 16,
                    offset: Offset(0, 6),
                    color: Color(0x33000000),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                child: Text(
                  message,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onInverseSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
