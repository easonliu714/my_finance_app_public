import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:sqflite/sqflite.dart';

import 'taiwan_business_calendar_annual_check_receipt.dart';
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
    this.receiptStore,
  });

  static const noticeKey = Key('b2-annual-foreground-notice');
  final Future<DatabaseExecutor> Function()? databaseProvider;
  final DateTime Function()? clock;
  final TaiwanBusinessCalendarAnnualCheckReceiptStore? receiptStore;

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
      final year = now.toUtc().add(const Duration(hours: 8)).year;
      // B2.14f: foreground eligibility must honor the same verified
      // digest-bound, same-Taipei-day receipt as the manual status page.
      // An advisory preferences failure cannot suppress a manual check.
      final current = await _service.status(db, year);
      DateTime? checkedAt;
      if (current != null &&
          current.isContiguous &&
          current.sequence > 0 &&
          current.digest.isNotEmpty) {
        try {
          checkedAt = await (widget.receiptStore ??
                  const TaiwanBusinessCalendarAnnualCheckReceiptStore())
              .readVerified(year: year, digest: current.digest, now: now);
        } catch (_) {
          // Fail open for the manual notice only; never infer a source check.
        }
      }
      var decision = await _service.annualUpdateDecision(
        db, now, lastCheckedAt: checkedAt,
      );
      if (checkedAt != null &&
          decision == CalendarAnnualUpdateDecision.checkedToday) {
        // A concurrent year-package replacement invalidates the old
        // receipt. Re-evaluate without it rather than hiding the notice.
        final latest = await _service.status(db, year);
        if (latest == null ||
            !latest.isContiguous ||
            latest.sequence != current?.sequence ||
            latest.revision != current?.revision ||
            latest.digest != current?.digest ||
            latest.sourceUrl != current?.sourceUrl ||
            latest.rowCount != current?.rowCount) {
          decision = await _service.annualUpdateDecision(db, now);
        }
      }
      if (!mounted || generation != _generation) return;
      setState(() {
        _nextYear = year + 1;
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
              onPressed: () async {
                // B2.14g: popping the status route does not trigger an
                // Android lifecycle resume. Re-read the advisory receipt
                // and installed-year status without network or DB writes.
                await context.pushNamed<void>(
                  TaiwanBusinessCalendarStatusPage.routeName,
                );
                if (mounted) await _refresh();
              },
              child: const Text('查看日曆'),
            ),
          ],
        ),
      ),
    );
  }
}
