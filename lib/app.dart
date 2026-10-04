import 'dart:async';

import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'features/invoice/invoice_award_automatic_refresh_runtime.dart';
import 'routing/app_router.dart';

class MyFinanceApp extends StatefulWidget {
  const MyFinanceApp({super.key});

  @override
  State<MyFinanceApp> createState() => _MyFinanceAppState();
}

class _MyFinanceAppState extends State<MyFinanceApp>
    with WidgetsBindingObserver {
  bool _catchUpDispatchActive = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_runAwardForegroundCatchUp());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_runAwardForegroundCatchUp());
    }
  }

  Future<void> _runAwardForegroundCatchUp() async {
    if (_catchUpDispatchActive) return;
    _catchUpDispatchActive = true;
    try {
      await runProductionInvoiceAwardForegroundCatchUp();
    } catch (_) {
      // Automatic refresh is strictly best-effort. Manual Award Check remains
      // available and all LKG repositories fail closed on unsuccessful work.
    } finally {
      _catchUpDispatchActive = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'My Finance App',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      routerConfig: appRouter,
    );
  }
}
