import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import 'taiwan_business_calendar_annual_check_receipt.dart';
import 'taiwan_business_calendar_annual_source_check.dart';
import 'taiwan_business_calendar_csv_import.dart';
import 'taiwan_business_calendar_official_116_stage.dart';
import 'taiwan_business_calendar_package_service.dart';
import 'taiwan_business_calendar_pinned_116_install.dart';
import 'transaction_repository.dart';

/// B2.13: read-only status and bounded SHA preview, followed by a separate
/// explicit owner-confirmed, atomic 116-year calendar installation action.
/// No account/transaction rows or unrelated calendar years are written.
class TaiwanBusinessCalendarStatusPage extends StatefulWidget {
  const TaiwanBusinessCalendarStatusPage({
    super.key,
    this.databaseProvider,
    this.csvBytesPicker,
    this.officialSourceCheck,
    this.receiptStore,
    this.clock,
  });

  static const routeName = 'taiwan-business-calendar-status';
  static const routePath = '/taiwan-business-calendar';
  static const annualCheckKey = Key('b2-official-116-annual-source-check');
  static const previewKey = Key('b2-official-116-csv-preview');
  static const installKey = Key('b2-official-116-csv-install');
  static const cancelInstallKey = Key('b2-official-116-install-cancel');
  static const confirmInstallKey = Key('b2-official-116-install-confirm');

  final Future<DatabaseExecutor> Function()? databaseProvider;
  final Future<Uint8List?> Function()? csvBytesPicker;
  final Future<TaiwanBusinessCalendarAnnualSourceResult> Function()?
      officialSourceCheck;
  final TaiwanBusinessCalendarAnnualCheckReceiptStore? receiptStore;
  final DateTime Function()? clock;

  @override
  State<TaiwanBusinessCalendarStatusPage> createState() =>
      _TaiwanBusinessCalendarStatusPageState();
}

class _TaiwanBusinessCalendarStatusPageState
    extends State<TaiwanBusinessCalendarStatusPage> {
  static const _official116Digest =
      'e30df188649bf5347db3ec43fa989af2cc8d93d793fbe5c9891601e6cce4acf3';
  static const _maxBytes = TaiwanBusinessCalendarOfficialCsvCodec.maxCsvBytes;
  static const _service = TaiwanBusinessCalendarPackageService();

  bool _loading = true;
  bool _checking = false;
  bool _annualChecking = false;
  bool _annualEligible = false;
  DateTime? _lastCheckedAtInThisPage;
  String _annualCheckResult = '官方來源尚未由本頁手動檢查。';
  Uint8List? _verifiedCsv;
  String _currentStatus = '讀取中…';
  String _nextStatus = '讀取中…';
  String _annualDecision = '讀取中…';
  String _fileResult = '尚未選擇檔案；不會安裝或修改任何日曆資料。';

  @override
  void initState() {
    super.initState();
    _loadReadOnlyStatus();
  }

  Future<DatabaseExecutor> _database() async =>
      widget.databaseProvider != null
          ? widget.databaseProvider!()
          : TransactionRepository.instance.database;

  String _coverage(CalendarPackageStatus? status) {
    if (status == null) return '尚未安裝已驗證的完整年度資料';
    if (!status.isContiguous || status.sequence < 1 || status.digest.isEmpty) {
      return '現有資料不完整或來源未驗證；禁止推定營業日';
    }
    return '${status.rowCount} 日已驗證，修訂序號 ${status.sequence}';
  }

  String _decision(CalendarAnnualUpdateDecision decision) =>
      switch (decision) {
        CalendarAnnualUpdateDecision.outsideDecember =>
          '尚未進入 12 月年度檢查時段',
        CalendarAnnualUpdateDecision.currentYearNotVerified =>
          '本年度資料尚未驗證；不可自動更新',
        CalendarAnnualUpdateDecision.beforeFirstBusinessDay =>
          '尚未到本年度 12 月首個官方營業日',
        CalendarAnnualUpdateDecision.nextYearUntrusted =>
          '次年度資料不完整；保留原資料',
        CalendarAnnualUpdateDecision.nextYearInstalled =>
          '次年度已安裝完整驗證資料',
        CalendarAnnualUpdateDecision.checkedToday =>
          '今日已檢查；不重複執行',
        CalendarAnnualUpdateDecision.checkOfficialSource =>
          '可人工檢查官方來源；不會自動下載或安裝',
      };

  TaiwanBusinessCalendarAnnualCheckReceiptStore get _receiptStore =>
      widget.receiptStore ??
      const TaiwanBusinessCalendarAnnualCheckReceiptStore();

  // Advisory preferences may fail; absence MUST allow explicit manual check.
  Future<DateTime?> _receipt(CalendarPackageStatus? current, DateTime now) async {
    if (current == null || !current.isContiguous ||
        current.sequence < 1 || current.digest.isEmpty) return null;
    try {
      return await _receiptStore.readVerified(
        year: current.year, digest: current.digest, now: now);
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadReadOnlyStatus() async {
    try {
      final db = await _database();
      final now = (widget.clock ?? DateTime.now)();
      // B2: status labels and database years must use the same Taiwan date
      // as annualUpdateDecision, including UTC year-end rollover.
      final taipeiYear = now.toUtc().add(const Duration(hours: 8)).year;
      final current = await _service.status(db, taipeiYear);
      final next = await _service.status(db, taipeiYear + 1);
      final saved = await _receipt(current, now);
      final decision = await _service.annualUpdateDecision(
        db, now, lastCheckedAt: saved ?? _lastCheckedAtInThisPage,
      );
      if (!mounted) return;
      setState(() {
        _currentStatus = '$taipeiYear 年：${_coverage(current)}';
        _nextStatus = '${taipeiYear + 1} 年：${_coverage(next)}';
        _annualDecision = _decision(decision);
        _annualEligible =
            decision == CalendarAnnualUpdateDecision.checkOfficialSource;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _currentStatus = '讀取失敗；不推定年度資料已驗證';
        _nextStatus = '讀取失敗；不推定年度資料已驗證';
        _annualDecision = '資料庫狀態不可確認；保持 HOLD';
        _annualEligible = false;
        _loading = false;
      });
    }
  }

  Future<Uint8List?> _pickBoundedCsv() async {
    final selection = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: <String>['csv'],
      withData: false,
    );
    if (selection == null) return null;
    final path = selection.files.single.path;
    if (path == null) throw const FormatException('無法安全讀取所選 CSV');
    final handle = await File(path).open();
    try {
      // Do not read an untrusted, arbitrarily large file into Dart memory.
      return Uint8List.fromList(await handle.read(_maxBytes + 1));
    } finally {
      await handle.close();
    }
  }

  Future<void> _previewCsv() async {
    if (_checking) return;
    setState(() {
      _checking = true;
      // A new selection revokes all earlier installation eligibility.
      _verifiedCsv = null;
      _fileResult = '正在有界檢查 CSV；尚未安裝。';
    });
    try {
      final bytes = await (widget.csvBytesPicker ?? _pickBoundedCsv)();
      if (!mounted) return;
      if (bytes == null) {
        setState(() => _fileResult = '已取消選取；資料未變更。');
        return;
      }
      if (bytes.isEmpty || bytes.lengthInBytes > _maxBytes) {
        throw const FormatException('CSV 必須非空且不超過 256 KiB');
      }
      final digest = await Sha256().hash(bytes);
      final actual = digest.bytes
          .map((value) => value.toRadixString(16).padLeft(2, '0'))
          .join();
      if (!mounted) return;
      if (actual != _official116Digest) {
        setState(() => _fileResult =
            'SHA-256 不符已驗證的 116 年官方 CSV；拒絕安裝，資料未變更。');
        return;
      }
      // B2.10: byte identity alone is insufficient for a success display.
      // Reuse production strict full-year staging; never write SQLite here.
      final staged =
          await const TaiwanBusinessCalendarOfficial116Stage().verify(bytes);
      if (!mounted) return;
      setState(() {
        // Snapshot only verified 6511-byte source; revalidate again on install.
        _verifiedCsv = Uint8List.fromList(bytes);
        _fileResult = '116 年官方來源 SHA-256 相符（${bytes.lengthInBytes} bytes）；'
            '完整年度 ${staged.days.length} 日／放假 ${staged.holidayCount} 日解析通過；'
            '僅完成身分與結構預檢，未安裝。';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _fileResult = 'CSV 讀取或驗證失敗；資料未變更。');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  // B2.13: preview is never installation authority. A second explicit tap
  // and affirmative dialog are required before acquiring a writable DB.
  Future<void> _installVerifiedCsv() async {
    final bytes = _verifiedCsv;
    if (_checking || bytes == null) return;
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('確認安裝 2027 年官方日曆？'),
        content: const Text(
          '僅將已核對 SHA-256 的 116 年原始 CSV，交易式安裝為 2027 年'
          '完整 365 日營業日曆。這會修改本機日曆資料；不會修改帳務。'
          '若已有較新版本、內容衝突或資料庫失敗，將拒絕並保留原資料。'
          '此動作不會啟用年度自動下載。',
        ),
        actions: <Widget>[
          TextButton(
            key: TaiwanBusinessCalendarStatusPage.cancelInstallKey,
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消，不安裝'),
          ),
          FilledButton(
            key: TaiwanBusinessCalendarStatusPage.confirmInstallKey,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('確認安裝 2027 年'),
          ),
        ],
      ),
    );
    if (!mounted || approved != true || !identical(_verifiedCsv, bytes)) {
      return;
    }
    setState(() {
      _checking = true;
      // Consent is one-shot; require a fresh preview for any later attempt.
      _verifiedCsv = null;
      _fileResult = '正在重新驗證官方 CSV 並執行交易式日曆安裝…';
    });
    try {
      final executor = await _database();
      // The existing service requires Database.transaction; never substitute
      // an unowned executor or create a second production connection.
      if (executor is! Database) {
        throw StateError('Calendar installation requires the canonical Database.');
      }
      final result = await const TaiwanBusinessCalendarPinned116Installer()
          .install(executor, bytes, userConfirmed: true);
      if (!mounted) return;
      setState(() {
        _fileResult = result.disposition ==
                CalendarPackageInstallDisposition.unchanged
            ? '2027 年官方日曆已存在且內容相同（365 日）；未重複寫入。'
            : '2027 年官方日曆已交易式安裝並驗證 365 日；帳務未變更。';
      });
      await _loadReadOnlyStatus();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _fileResult = '安裝拒絕或失敗；未確認任何新年度資料，'
            '請重新預檢官方 CSV。原日曆由交易式回復保護。';
      });
      await _loadReadOnlyStatus();
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }


  // B2.14b: a distinct explicit tap is the only network entry point.
  // Recheck eligibility before GET; successful same-day receipt is ephemeral.
  Future<void> _checkOfficialSource() async {
    if (_checking || _annualChecking || !_annualEligible) return;
    setState(() {
      _annualChecking = true;
      _annualCheckResult = '正在手動核對官方 116 年來源；不會安裝。';
    });
    try {
      final db = await _database();
      final now = (widget.clock ?? DateTime.now)();
      final year = now.toUtc().add(const Duration(hours: 8)).year;
      final current = await _service.status(db, year);
      final saved = await _receipt(current, now);
      final decision = await _service.annualUpdateDecision(
        db, now, lastCheckedAt: saved ?? _lastCheckedAtInThisPage,
      );
      if (decision != CalendarAnnualUpdateDecision.checkOfficialSource) {
        if (mounted) {
          setState(() => _annualCheckResult =
              '年度檢查條件已變更；未讀取官方檔案，也未寫入資料。');
          await _loadReadOnlyStatus();
        }
        return;
      }
      final result = widget.officialSourceCheck != null
          ? await widget.officialSourceCheck!()
          : await const TaiwanBusinessCalendarAnnualSourceCheck().check();
      if (!mounted) return;
      if (result.sha256 !=
              TaiwanBusinessCalendarOfficial116Stage.pinnedSha256 ||
          result.days != 365 ||
          result.holidays != 121) {
        throw const FormatException('Official source result is untrusted.');
      }
      final checkedAt = (widget.clock ?? DateTime.now)();
      // A calendar install or Taipei midnight may occur during HTTPS GET.
      final stillEligible = await _service.annualUpdateDecision(
        db, checkedAt, lastCheckedAt: saved ?? _lastCheckedAtInThisPage,
      );
      if (!mounted) return;
      if (stillEligible != CalendarAnnualUpdateDecision.checkOfficialSource) {
        setState(() => _annualCheckResult =
            '來源已核對但年度條件改變；未建立檢查紀錄或安裝。');
        await _loadReadOnlyStatus();
        return;
      }
      var durable = false;
      try {
        if (current != null && current.isContiguous &&
            current.year == year && current.sequence > 0 &&
            current.digest.isNotEmpty) {
          await _receiptStore.writeVerified(
            year: year, digest: current.digest, checkedAt: checkedAt);
          durable = true;
        }
      } catch (_) {
        // Storage failure never promotes source authority or calendar LKG.
      }
      if (!mounted) return;
      setState(() {
        _lastCheckedAtInThisPage = checkedAt;
        _annualCheckResult = durable
            ? '官方 116 年來源核對通過：365 日／121 放假日；'
                '本機當日檢查紀錄已保存，未安裝 2027 年日曆。'
            : '官方 116 年來源核對通過，但本機檢查紀錄未能保存；'
                '未安裝 2027 年日曆。';
      });
      await _loadReadOnlyStatus();
    } catch (_) {
      if (!mounted) return;
      setState(() => _annualCheckResult =
          '官方來源讀取或 SHA／年度結構驗證失敗；未安裝且未寫入資料。');
    } finally {
      if (mounted) setState(() => _annualChecking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('台灣營業日曆')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          const Text('年度資料狀態', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Text(_currentStatus),
          const SizedBox(height: 8),
          Text(_nextStatus),
          const SizedBox(height: 12),
          Text(_annualDecision),
          if (_annualEligible) ...<Widget>[
            const SizedBox(height: 8),
            OutlinedButton(
              key: TaiwanBusinessCalendarStatusPage.annualCheckKey,
              onPressed: (_checking || _annualChecking)
                  ? null
                  : _checkOfficialSource,
              child: const Text('手動核對官方 116 年來源（僅讀取）'),
            ),
          ],
          const SizedBox(height: 8),
          Text(_annualCheckResult),
          const Text('成功後僅保存本機當日檢查時間與來源雜湊；'
              '不是官方版本或安裝證明，亦不修改日曆或帳務。'),
          if (_loading || _annualChecking)
            const LinearProgressIndicator(),
          const Divider(height: 32),
          const Text('116 年（2027）官方 CSV 檔案預檢',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('請從行政院人事行政總處官方網站取得原始 CSV。'
              '目前核對官方來源 SHA-256 與完整年度日期、放假日結構；'
              '不會自動安裝、覆寫年度資料或修改帳務。'),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: TaiwanBusinessCalendarStatusPage.previewKey,
            onPressed: (_checking || _annualChecking) ? null : _previewCsv,
            icon: const Icon(Icons.file_open_outlined),
            label: const Text('選擇官方 CSV（僅預檢）'),
          ),
          const SizedBox(height: 8),
          Text(_fileResult),
          if (_verifiedCsv != null) ...<Widget>[
            const SizedBox(height: 12),
            FilledButton.icon(
              key: TaiwanBusinessCalendarStatusPage.installKey,
              onPressed: (_checking || _annualChecking) ? null : _installVerifiedCsv,
              icon: const Icon(Icons.verified_user_outlined),
              label: const Text('另行確認安裝 2027 年官方日曆'),
            ),
          ],
          const SizedBox(height: 16),
          const Text('僅在重新核對官方原始檔且明確確認後，才會交易式安裝。'
              '年度自動下載／更新尚未啟用；2026 年資料狀態不受此操作推定。'),
        ],
      ),
    );
  }
}
