import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:sqflite/sqflite.dart';

import 'taiwan_business_calendar_package_service.dart';
import 'taiwan_business_calendar_status_page.dart';
import 'transaction_repository.dart';

/// B2.14a: read-only first foreground/resume December eligibility.
/// No source download, last-check write, inferred holiday or silent install.
class TaiwanBusinessCalendarForegroundNotice extends StatefulWidget {
  const TaiwanBusinessCalendarForegroundNotice({
    super.key,
    this.databaseProvider,
    this.clock,
  });

  static const noticeKey = Key('b2-annual-foreground-notice');
  final Future<DatabaseExecutor> Function()? databaseProvider;
  final DateTime Function()? clock;

  @override
  State<TaiwanBusinessCalendarForegroundNotice> createState() =>
      _TaiwanBusinessCalendarForegroundNoticeState();
}

class _TaiwanBusinessCalendarForegroundNoticeState
    extends State<TaiwanBusinessCalendarForegroundNotice>
    with WidgetsBindingObserver {
  static const _service = TaiwanBusinessCalendarPackageService();
  int _generation = 0;
  int _nextYear = 0;
  bool _eligible = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final generation = ++_generation;
    try {
      final db = await (widget.databaseProvider != null
          ? widget.databaseProvider!()
          : TransactionRepository.instance.database);
      final now = (widget.clock ?? DateTime.now)();
      final decision = await _service.annualUpdateDecision(db, now);
      if (!mounted || generation != _generation) return;
      setState(() {
        _nextYear = now.toUtc().add(const Duration(hours: 8)).year + 1;
        _eligible =
            decision == CalendarAnnualUpdateDecision.checkOfficialSource;
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() => _eligible = false);
    }
  }

  @override
  void dispose() {
    _generation++;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_eligible) return const SizedBox.shrink();
    return Card(
      key: TaiwanBusinessCalendarForegroundNotice.noticeKey,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text('$_nextYear 年官方日曆尚未安裝；'
                  '已到年度檢查時段，請手動核對官方來源。'),
            ),
            TextButton(
              onPressed: () => context.pushNamed(
                TaiwanBusinessCalendarStatusPage.routeName,
              ),
              child: const Text('查看日曆'),
            ),
          ],
        ),
      ),
    );
  }
}
