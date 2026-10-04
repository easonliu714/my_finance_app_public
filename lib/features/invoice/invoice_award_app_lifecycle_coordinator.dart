import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'invoice_award_period_catalog.dart';
import 'invoice_award_runtime_scheduler.dart';
import 'invoice_award_automatic_refresh_runner.dart';

/// App-wide lifecycle bridge for Issue #13 automatic official-number refresh.
///
/// Native AlarmManager delivery is captured whenever the app process starts or
/// returns to foreground, regardless of the visible route. This widget performs
/// no navigation and owns no MOF parsing logic. After persisting a due marker
/// it may invoke the shared headless runner, which composes the existing
/// production general/cloud acquisition authorities in foreground.
class InvoiceAwardAppLifecycleCoordinator extends StatefulWidget {
  const InvoiceAwardAppLifecycleCoordinator({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  State<InvoiceAwardAppLifecycleCoordinator> createState() =>
      _InvoiceAwardAppLifecycleCoordinatorState();
}

class _InvoiceAwardAppLifecycleCoordinatorState
    extends State<InvoiceAwardAppLifecycleCoordinator>
    with WidgetsBindingObserver {
  bool _captureActive = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_captureNativeWake());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_captureNativeWake());
    }
  }

  Future<void> _captureNativeWake() async {
    if (_captureActive) return;
    _captureActive = true;
    try {
      final preferences = await SharedPreferences.getInstance();
      final scheduler = InvoiceAwardRuntimeScheduler(
        repository: InvoiceAwardRuntimeStateRepository(preferences),
      );
      await scheduler.captureNativeWakeForForeground();

      final now = DateTime.now();
      final selectedPeriod = InvoiceAwardRecentPeriodCatalog.defaultAt(now);
      final due = await scheduler.foregroundCatchUpDue(
        nowLocal: now,
        periodId: selectedPeriod.period.id,
      );
      if (!due) return;

      final runner = InvoiceAwardCanonicalAutomaticRefreshRunner(
        scheduler: scheduler,
      );
      await runner.refresh(selectedPeriod: selectedPeriod);
    } on MissingPluginException {
      // Widget/unit test hosts have no Android MethodChannel implementation.
    } on PlatformException {
      // Best-effort scheduling must never make app startup fail.
    } finally {
      _captureActive = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
