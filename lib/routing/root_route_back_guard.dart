import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class RootRouteBackGuard extends StatelessWidget {
  const RootRouteBackGuard({
    super.key,
    required this.child,
    this.fallbackLocation = '/',
    this.onFallback,
  });

  static const Key fallbackButtonKey = Key('root_route_back_fallback');

  final Widget child;
  final String fallbackLocation;
  final VoidCallback? onFallback;

  void _fallback(BuildContext context) {
    final callback = onFallback;
    if (callback != null) {
      callback();
      return;
    }
    context.go(fallbackLocation);
  }

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    return PopScope<Object?>(
      canPop: canPop,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _fallback(context);
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          child,
          if (!canPop)
            PositionedDirectional(
              start: 4,
              top: 4,
              child: SafeArea(
                child: Material(
                  color: Colors.transparent,
                  child: IconButton(
                    key: fallbackButtonKey,
                    tooltip: '返回首頁',
                    onPressed: () => _fallback(context),
                    icon: const Icon(Icons.arrow_back),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
