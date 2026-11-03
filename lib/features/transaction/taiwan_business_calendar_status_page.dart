import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import 'taiwan_business_calendar_csv_import.dart';
import 'taiwan_business_calendar_official_116_stage.dart';
import 'taiwan_business_calendar_package_service.dart';
import 'transaction_repository.dart';

/// B2 owner-facing, read-only annual status and bounded official-file preview.
/// No production calendar/transaction row is changed by this page.
class TaiwanBusinessCalendarStatusPage extends StatefulWidget {
  const TaiwanBusinessCalendarStatusPage({
    super.key,
    this.databaseProvider,
    this.csvBytesPicker,
    this.clock,
  });

  static const routeName = 'taiwan-business-calendar-status';
  static const routePath = '/taiwan-business-calendar';
  static const previewKey = Key('b2-official-116-csv-preview');

  final Future<DatabaseExecutor> Function()? databaseProvider;
  final Future<Uint8List?> Function()? csvBytesPicker;
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

  Future<void> _loadReadOnlyStatus() async {
    try {
      final db = await _database();
      final now = (widget.clock ?? DateTime.now)();
      // B2: status labels and database years must use the same Taiwan date
      // as annualUpdateDecision, including UTC year-end rollover.
      final taipeiYear = now.toUtc().add(const Duration(hours: 8)).year;
      final current = await _service.status(db, taipeiYear);
      final next = await _service.status(db, taipeiYear + 1);
      final decision = await _service.annualUpdateDecision(db, now);
      if (!mounted) return;
      setState(() {
        _currentStatus = '$taipeiYear 年：${_coverage(current)}';
        _nextStatus = '${taipeiYear + 1} 年：${_coverage(next)}';
        _annualDecision = _decision(decision);
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _currentStatus = '讀取失敗；不推定年度資料已驗證';
        _nextStatus = '讀取失敗；不推定年度資料已驗證';
        _annualDecision = '資料庫狀態不可確認；保持 HOLD';
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
          if (_loading) const LinearProgressIndicator(),
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
            onPressed: _checking ? null : _previewCsv,
            icon: const Icon(Icons.file_open_outlined),
            label: const Text('選擇官方 CSV（僅預檢）'),
          ),
          const SizedBox(height: 8),
          Text(_fileResult),
          const SizedBox(height: 16),
          const Text('正式年度安裝仍需修訂日期與來源驗證、'
              '交易式回復測試及 Owner 確認；此頁不宣稱已完成安裝。'),
        ],
      ),
    );
  }
}
