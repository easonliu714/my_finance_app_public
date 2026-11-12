import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:share_plus/share_plus.dart';

import 'features/invoice/invoice_award_cloud_artifact_downloader.dart';
import 'features/invoice/invoice_award_cloud_candidate_scope.dart';
import 'features/invoice/invoice_award_cloud_publication_parser.dart';
import 'issue13_lab_l1_cursor.dart';
import 'issue13_lab_l1_bounded_run.dart';
import 'issue13_lab_l1_dispatch_fence.dart';
import 'issue13_lab_l1_evidence_bundle.dart';
import 'issue13_lab_search_result.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const Cloud500DiagnosticApp());
}

// Test-only deterministic hooks avoid fake-clock filesystem I/O in widget tests.
// The production entry point always uses the original platform-backed paths.
class Cloud500DiagnosticTestHooks {
  // The optional shorter timeout is a test seam; production retains 30 seconds.
  const Cloud500DiagnosticTestHooks({this.initialize, this.writeLog, this.shareEvidenceBundle, this.initializationTimeout});
  final Duration? initializationTimeout;
  final Future<void> Function()? initialize;
  final Future<void> Function(String)? writeLog;
  final Future<void> Function()? shareEvidenceBundle;
}

class Cloud500DiagnosticApp extends StatelessWidget {
  const Cloud500DiagnosticApp({super.key, this.testHooks});
  final Cloud500DiagnosticTestHooks? testHooks;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Cloud500 PDF Lab',
      theme: ThemeData(useMaterial3: true),
      home: Cloud500DiagnosticPage(testHooks: testHooks),
    );
  }
}

class Cloud500DiagnosticPage extends StatefulWidget {
  const Cloud500DiagnosticPage({super.key, this.testHooks});
  final Cloud500DiagnosticTestHooks? testHooks;

  @override
  State<Cloud500DiagnosticPage> createState() =>
      _Cloud500DiagnosticPageState();
}

class _Cloud500DiagnosticPageState extends State<Cloud500DiagnosticPage> {
  static const _channel = MethodChannel('pdf_text');
  static const _searchActionLabel = 'Android PdfRenderer Binary Search';
  static final _publicationUri =
      Uri.parse('https://invoice.etax.nat.gov.tw/cloudNowNumber.html');
  static const _periodId = '115-07-08';
  static const _expectedSha256 =
      'f50d0dcebc7497c51ce2eea9da9525232e638fdc4103decc6a8e0a1c1dac5571';
  static const _expectedBytes = 135200798;
  static const _labBranch = String.fromEnvironment(
    'LAB_BRANCH',
    defaultValue: 'unknown-branch',
  );
  static const _labHead = String.fromEnvironment(
    'LAB_HEAD',
    defaultValue: 'unknown-head',
  );
  static const _labBackend = String.fromEnvironment(
    'LAB_BACKEND',
    defaultValue: 'unknown-backend',
  );

  final _candidateController = TextEditingController();
  final _evidenceWindowController = TextEditingController(text: '1');
  final _scrollController = ScrollController();
  final _logLines = <String>[];

  Directory? _labDirectory;
  File? _dartLogFile;
  File? _pdfFile;
  File? _lastL1BatchFile;
  OfficialCloudAwardArtifactReference? _reference;
  bool _busy = false;
  bool _initialized = false;
  bool _initializationExpired = false;

  // Initialization must complete before any Lab action touches files/native code.
  bool get _actionsDisabled => _busy || !_initialized || _initializationExpired;
  LabSearchResult? _searchResult;
  String _status = '初始化中…';
  String _runtimeVersion = '讀取中…';
  String _runtimePackage = '讀取中…';

  @override
  void initState() {
    super.initState();
    unawaited(_initializeSafely());
  }

  @override
  void dispose() {
    _candidateController.dispose();
    _evidenceWindowController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // Bound startup: a stalled platform/filesystem future must enter HOLD.
  // A late completion cannot re-enable actions after timeout or failure.
  Future<void> _initializeSafely() async {
    try {
      final testStartup = widget.testHooks?.initialize;
      // Keep the production 30-second fail-closed boundary; a short test
      // duration makes fake-clock timeout regression deterministic.
      final startupTimeout = widget.testHooks?.initializationTimeout ??
          const Duration(seconds: 30);
      if (testStartup == null) {
        await _initialize().timeout(startupTimeout);
      } else {
        await testStartup().timeout(startupTimeout);
        if (mounted && !_initializationExpired) {
          setState(() { _initialized = true; _status = '就緒'; });
        }
      }
    } catch (_) {
      _initializationExpired = true;
      if (!mounted) return;
      setState(() {
        _initialized = false;
        _status = 'LAB_INIT_HOLD';
      });
    }
  }

  Future<void> _initialize() async {
    final packageInfo = await PackageInfo.fromPlatform();
    _runtimeVersion = '${packageInfo.version}+${packageInfo.buildNumber}';
    _runtimePackage = packageInfo.packageName;
    final support = await getApplicationSupportDirectory();
    final lab = Directory(
      '${support.path}${Platform.pathSeparator}issue13_cloud500_diag',
    );
    await lab.create(recursive: true);
    final log = File(
      '${lab.path}${Platform.pathSeparator}issue13_cloud500_diag.log',
    );
    final pdf = File(
      '${lab.path}${Platform.pathSeparator}$_expectedSha256.pdf',
    );
    _labDirectory = lab;
    _dartLogFile = log;
    _pdfFile = pdf;
    await _log(
      'LAB_START runtime_version=$_runtimeVersion package=$_runtimePackage '
      'branch=$_labBranch head=$_labHead backend=$_labBackend period=$_periodId',
    );
    await _log('LAB_DIR=${lab.path}');
    await _log('EXPECTED_SHA256=$_expectedSha256');
    await _log('EXPECTED_BYTES=$_expectedBytes');
    if (await pdf.exists()) {
      await _log('LOCAL_PDF_PRESENT path=${pdf.path} bytes=${await pdf.length()}');
    }
    if (mounted && !_initializationExpired) {
      setState(() {
        _initialized = true;
        _status = '就緒';
      });
    }
  }

  Future<void> _run(String label, Future<void> Function() action) async {
    if (_actionsDisabled) return;
    setState(() {
      _busy = true;
      _status = label;
      if (label == _searchActionLabel) _searchResult = null;
    });
    try {
      await _log('ACTION_BEGIN name=$label');
      await action();
      await _log('ACTION_OK name=$label');
      if (mounted) {
        setState(() => _status = label == _searchActionLabel
            ? (_searchResult?.statusLabel ?? '診斷搜尋：HOLD')
            : '$label：完成');
      }
    } catch (error, stack) {
      // L1: Unwritable/full diagnostic logs must not suppress visible failure.
      Object? logWriteFailure;
      try {
        await _log('ACTION_FAIL name=$label error=$error');
        await _log('STACK=${stack.toString().replaceAll('\n', ' | ')}');
      } catch (loggingError) {
        logWriteFailure = loggingError;
      }
      if (mounted) {
        setState(() {
          if (label == _searchActionLabel) {
            _searchResult ??= LabSearchResult.hold(
              candidate: _candidateController.text.trim().toUpperCase(),
              reason: 'ACTION_FAILED_OR_TIMEOUT',
            );
            _status = _searchResult!.statusLabel;
          } else {
            _status = '$label：失敗：$error'
                '${logWriteFailure == null ? '' : ' [LAB_LOG_WRITE_FAILED]'}';
          }
        });
        // The share action is near the bottom of a long ListView. Report
        // failures at the viewport, not only in the off-screen header/log.
        final message = label == 'Share bounded L1 evidence bundle'
            ? '分包匯出失敗：$error。請選擇第1、2…包，每包最多12批；'
                '原始JSONL及續傳頁碼不變，請勿清除資料。'
            : '$label：失敗：$error';
        final visibleMessage = logWriteFailure == null
            ? message
            : '$message [LAB_LOG_WRITE_FAILED]';
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            content: Text(visibleMessage),
            duration: const Duration(seconds: 10),
          ));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _log(String message) async {
    final now = DateTime.now().toIso8601String();
    final line = '$now $message';
    final file = _dartLogFile;
    final testWriter = widget.testHooks?.writeLog;
    if (testWriter != null) {
      await testWriter(line);
    } else if (file != null) {
      await file.writeAsString('$line\n', mode: FileMode.append, flush: true);
    }
    if (!mounted) return;
    setState(() {
      _logLines.add(line);
      if (_logLines.length > 600) {
        _logLines.removeRange(0, _logLines.length - 600);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  Future<OfficialCloudAwardArtifactReference> _loadReference() async {
    if (_reference != null) return _reference!;
    await _log('PUBLICATION_FETCH_BEGIN uri=$_publicationUri');
    final response = await http.get(
      _publicationUri,
      headers: const <String, String>{
        HttpHeaders.acceptHeader: 'text/html,application/xhtml+xml',
      },
    );
    await _log(
      'PUBLICATION_FETCH_END status=${response.statusCode} bytes=${response.bodyBytes.length}',
    );
    if (response.statusCode != 200) {
      throw StateError('PUBLICATION_HTTP_${response.statusCode}');
    }
    final html = utf8.decode(response.bodyBytes, allowMalformed: false);
    final parsed = const MinistryOfFinanceCloudAwardPublicationHtmlParser().parse(
      sourceUri: _publicationUri,
      html: html,
      expectedPeriodId: _periodId,
      fetchedAt: DateTime.now().toUtc(),
    );
    final reference = parsed.artifacts.singleWhere(
      (item) => item.tierCode == 'cloud-500',
    );
    await _log(
      'CLOUD500_REFERENCE artifact=${reference.artifactId} uri=${reference.sourceUri}',
    );
    _reference = reference;
    return reference;
  }

  Future<String> _sha256(File file, {String stage = 'SHA256'}) async {
    final sink = Sha256().newHashSink();
    var read = 0;
    var nextLog = 16 * 1024 * 1024;
    final started = Stopwatch()..start();
    await for (final chunk in file.openRead()) {
      sink.add(chunk);
      read += chunk.length;
      if (read >= nextLog) {
        await _log(
          '$stage progress_bytes=$read elapsed_ms=${started.elapsedMilliseconds}',
        );
        nextLog += 16 * 1024 * 1024;
      }
    }
    sink.close();
    final hash = await sink.hash();
    final value = hash.bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    await _log(
      '$stage complete bytes=$read sha256=$value elapsed_ms=${started.elapsedMilliseconds}',
    );
    return value;
  }

  Future<File> _ensureExactPdf() async {
    final file = _pdfFile;
    if (file == null) throw StateError('LAB_NOT_INITIALIZED');

    if (await file.exists()) {
      final bytes = await file.length();
      await _log('LOCAL_VALIDATE_BEGIN path=${file.path} bytes=$bytes');
      if (bytes == _expectedBytes) {
        final sha = await _sha256(file, stage: 'LOCAL_SHA256');
        if (sha == _expectedSha256) {
          await _log('LOCAL_VALIDATE_PASS');
          return file;
        }
      }
      await _log('LOCAL_VALIDATE_FAIL deleting_invalid_copy=true');
      await file.delete();
    }

    final reference = await _loadReference();
    final partial = File('${file.path}.partial');
    if (await partial.exists()) await partial.delete();

    final client = http.Client();
    IOSink? output;
    try {
      final request = http.Request('GET', reference.sourceUri);
      request.headers[HttpHeaders.acceptHeader] = 'application/pdf';
      await _log('PDF_DOWNLOAD_BEGIN uri=${reference.sourceUri}');
      final response = await client.send(request);
      await _log(
        'PDF_DOWNLOAD_HEADERS status=${response.statusCode} '
        'declared=${response.contentLength} contentType=${response.headers[HttpHeaders.contentTypeHeader]}',
      );
      if (response.statusCode != 200) {
        throw StateError('PDF_HTTP_${response.statusCode}');
      }

      final hashSink = Sha256().newHashSink();
      output = partial.openWrite(mode: FileMode.writeOnly);
      final prefix = <int>[];
      var total = 0;
      var nextLog = 8 * 1024 * 1024;
      final started = Stopwatch()..start();

      await for (final chunk in response.stream) {
        if (prefix.length < 5) {
          prefix.addAll(chunk.take(min(5 - prefix.length, chunk.length)));
        }
        total += chunk.length;
        hashSink.add(chunk);
        output.add(chunk);
        if (total >= nextLog) {
          final seconds = max(started.elapsedMilliseconds / 1000.0, 0.001);
          await _log(
            'PDF_DOWNLOAD_PROGRESS bytes=$total '
            'rate_bps=${(total / seconds).round()} elapsed_ms=${started.elapsedMilliseconds}',
          );
          nextLog += 8 * 1024 * 1024;
        }
      }
      await output.flush();
      await output.close();
      output = null;
      hashSink.close();
      final hash = await hashSink.hash();
      final sha = hash.bytes
          .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
          .join();
      await _log(
        'PDF_DOWNLOAD_COMPLETE bytes=$total sha256=$sha '
        'elapsed_ms=${started.elapsedMilliseconds}',
      );

      if (String.fromCharCodes(prefix) != '%PDF-') {
        throw StateError('PDF_MAGIC_INVALID');
      }
      if (total != _expectedBytes) {
        throw StateError('PDF_BYTES_MISMATCH expected=$_expectedBytes actual=$total');
      }
      if (sha != _expectedSha256) {
        throw StateError('PDF_SHA_MISMATCH expected=$_expectedSha256 actual=$sha');
      }
      await partial.rename(file.path);
      await _log('PDF_PROMOTED path=${file.path}');
      return file;
    } finally {
      client.close();
      try {
        await output?.flush();
        await output?.close();
      } catch (_) {}
    }
  }

  Future<void> _openSystemViewer() async {
    final file = await _ensureExactPdf();
    await _log('SYSTEM_VIEWER_BEGIN path=${file.path}');
    await _channel.invokeMethod<void>(
      'openExternalPdf',
      <String, Object?>{'path': file.path},
    );
    await _log('SYSTEM_VIEWER_DISPATCHED');
  }

  // ignore: unused_element
  Future<Map<String, Object?>> _openPdfium(File file) async {
    final timer = Stopwatch()..start();
    await _log('PDFIUM_DIRECT_OPEN_BEGIN path=${file.path}');
    final opened = await _channel.invokeMapMethod<String, Object?>(
      'openPdfiumSession',
      <String, Object?>{'path': file.path},
    );
    await _log(
      'PDFIUM_DIRECT_OPEN_RETURN elapsed_ms=${timer.elapsedMilliseconds} result=$opened',
    );
    if (opened == null) throw StateError('PDFIUM_OPEN_NULL');
    return opened;
  }

  Future<Map<String, dynamic>> _runPlatformProbe({
    required String candidate,
    String? requestIdOverride,
    Future<void> Function()? beforeDispatch,
  }) async {
    final file = await _ensureExactPdf();
    final lab = _labDirectory;
    if (lab == null) throw StateError('LAB_NOT_INITIALIZED');
    final requestId = requestIdOverride ??
        DateTime.now().microsecondsSinceEpoch.toString();
    final resultFile = File(
      '${lab.path}${Platform.pathSeparator}platform_probe_$requestId.json',
    );
    if (await resultFile.exists()) await resultFile.delete();

    await _log(
      'PLATFORM_PROBE_DISPATCH request=$requestId candidate=$candidate '
      'backend=android.graphics.pdf.PdfRenderer',
    );
    // Persist the in-flight marker before native renderer dispatch.
    if (beforeDispatch != null) await beforeDispatch();
    await _channel.invokeMethod<void>(
      'startPlatformPdfProbe',
      <String, Object?>{
        'path': file.path,
        'resultPath': resultFile.path,
        'requestId': requestId,
        'candidate': candidate,
      },
    );

    var lastUpdatedAt = 0;
    var lastPid = -1;
    var lastStage = 'DISPATCHED';
    var lastReportAt = DateTime.now();
    while (true) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (!await resultFile.exists()) continue;
      Map<String, dynamic> decoded;
      try {
        decoded = jsonDecode(await resultFile.readAsString())
            as Map<String, dynamic>;
      } on FormatException {
        continue;
      }
      if (decoded['request_id']?.toString() != requestId) continue;
      final status = decoded['status']?.toString() ?? '';
      final stage = decoded['stage']?.toString() ?? '';
      final pid = (decoded['pid'] as num?)?.toInt() ?? -1;
      final updatedAt = (decoded['updated_at_ms'] as num?)?.toInt() ?? 0;
      final elapsed = (decoded['elapsed_ms'] as num?)?.toInt() ?? 0;
      lastPid = pid;
      lastStage = stage;

      if (updatedAt > lastUpdatedAt) {
        lastUpdatedAt = updatedAt;
        lastReportAt = DateTime.now();
        await _log(
          'PLATFORM_PROBE_PROGRESS status=$status stage=$stage pid=$pid '
          'elapsed_ms=$elapsed page=${decoded['current_page'] ?? 0} '
          'pages_read=${decoded['pages_read'] ?? 0} '
          'page_count=${decoded['page_count'] ?? 0}',
        );
      }

      if (status == 'complete') {
        await _log('PLATFORM_PROBE_COMPLETE result=$decoded');
        return decoded;
      }
      if (status == 'failure') {
        await _log('PLATFORM_PROBE_FAILURE result=$decoded');
        return decoded;
      }

      if (DateTime.now().difference(lastReportAt) >
          const Duration(seconds: 8)) {
        final info = await _channel.invokeMapMethod<String, Object?>(
          'inspectPdfiumOpenProbeProcess',
          <String, Object?>{'pid': lastPid},
        );
        await _log(
          'PLATFORM_PROBE_STALE_HEARTBEAT stage=$lastStage pid=$lastPid '
          'process_info=$info',
        );
        if (info?['running'] != true) {
          await _log(
            'PLATFORM_PROBE_PROCESS_EXIT_CONFIRMED '
            'reason=${info?['reason']} status=${info?['status']} '
            'pss=${info?['pss']} rss=${info?['rss']} '
            'description=${info?['description']}',
          );
          return <String, dynamic>{
            'status': 'process_exit',
            'stage': lastStage,
            'pid': lastPid,
            'process_info': info,
          };
        }
        lastReportAt = DateTime.now();
      }
    }
  }


  // A durable cursor advances only after a complete native four-page batch.
  // Restart, native death and partial output cannot silently skip a page.
  Future<LabL1Batch> _exportNextL1Batch() async {
    final lab = _labDirectory;
    if (lab == null) throw StateError('LAB_NOT_INITIALIZED');
    final fence = LabL1DispatchFence(lab);
    // Timeout or crash does not prove the isolated process has exited.
    await fence.requireClear();
    final cursor = File('${lab.path}/l1-next-page.txt');
    final raw = await cursor.exists() ? await cursor.readAsString() : '1';
    final first = int.tryParse(raw.trim());
    if (first == null || first < 1 || first > 100000) {
      throw StateError('L1_CURSOR_INVALID_OR_COMPLETE');
    }
    // A finalized batch may exist even if the UI crashed before cursor save.
    final recovered = await LabL1Cursor.recover(lab, first, _expectedSha256);
    if (recovered != null) {
      await _persistL1Cursor(cursor, recovered.last + 1);
      _lastL1BatchFile = recovered.file;
      await _log('L1_RECOVERED_COMPLETED_BATCH first=$first '
          'last=${recovered.last} global_not_win=HOLD');
      return recovered;
    }
    await _requireL1ExportStorageBudget();
    final requestId = DateTime.now().microsecondsSinceEpoch.toString();
    final result = await _runPlatformProbe(
      candidate: 'LAB_L1_EXPORT:$first',
      requestIdOverride: requestId,
      beforeDispatch: () => fence.begin(
        firstPage: first,
        requestId: requestId,
        pdfSha256: _expectedSha256,
      ),
    );
    if (result['status'] != 'complete' ||
        result['start_page'] != first ||
        result['batch_only'] != true ||
        result['pdf_sha256'] != _expectedSha256) {
      throw StateError('L1_NATIVE_BATCH_HOLD result=$result');
    }
    final last = (result['end_page'] as num?)?.toInt();
    final count = (result['page_count'] as num?)?.toInt();
    final path = result['export_path']?.toString() ?? '';
    if (last == null || count == null || path.isEmpty) {
      throw StateError('L1_NATIVE_BATCH_INCOMPLETE');
    }
    final checked = await LabL1Cursor.verify(
      lab, File(path), first, _expectedSha256, last: last, count: count,
    );
    // Only terminal native success and strict JSONL verification clear it.
    // Finalized-batch recovery then covers a crash before cursor save.
    await fence.complete(
      firstPage: first,
      requestId: requestId,
      pdfSha256: _expectedSha256,
    );
    await _persistL1Cursor(cursor, checked.last + 1);
    _lastL1BatchFile = checked.file;
    await _log('L1_PARTIAL_BATCH_CAPTURED first=$first last=${checked.last} '
        'total=${checked.count} global_not_win=HOLD');
    return checked;
  }


  // Include interrupted .part files in the retained-evidence quota. Do not
  // delete audit evidence automatically or claim an incomplete chain is done.
  Future<int> _l1RetainedBytes() async {
    final lab = _labDirectory;
    if (lab == null) throw StateError('LAB_NOT_INITIALIZED');
    var total = 0;
    await for (final entry in lab.list(followLinks: false)) {
      final name = entry.uri.pathSegments.last;
      if (!name.startsWith('l1-pages-') ||
          !(name.endsWith('.jsonl') || name.endsWith('.jsonl.part'))) {
        continue;
      }
      if (entry is! File) throw StateError('L1_RETAINED_ENTRY_UNTRUSTED');
      total += await entry.length();
      if (total > LabL1BoundedRun.maxRetainedBytes) return total;
    }
    return total;
  }

  Future<void> _requireL1ExportStorageBudget() async {
    final retained = await _l1RetainedBytes();
    if (retained >
        LabL1BoundedRun.maxRetainedBytes - LabL1BoundedRun.maxBatchBytes) {
      throw StateError('L1_RETAINED_STORAGE_BUDGET_HOLD');
    }
  }

  Future<int> _readL1NextPage() async {
    final lab = _labDirectory;
    if (lab == null) throw StateError('LAB_NOT_INITIALIZED');
    final cursor = File('${lab.path}/l1-next-page.txt');
    final raw = await cursor.exists() ? await cursor.readAsString() : '1';
    return int.tryParse(raw.trim()) ?? 0;
  }

  // At most 8 native four-page batches, 256 MiB retained JSONL and 2 min
  // per native batch. Timeout is an unknown-process HOLD, never auto-retry.
  Future<void> _exportBoundedL1Run() async {
    final result = await LabL1BoundedRun.run(
      readNextPage: _readL1NextPage,
      retainedBytes: _l1RetainedBytes,
      captureNext: _exportNextL1Batch,
    );
    await _log('L1_BOUNDED_RUN batches=${result.batches} '
        'next_page=${result.nextPage} total=${result.pageCount} '
        'cursor_reached_end=${result.reachedFinalPage} '
        'official_full_page_evidence=HOLD global_not_win=HOLD');
  }

  Future<void> _persistL1Cursor(File cursor, int next) async {
    final pending = File('${cursor.path}.part');
    await pending.writeAsString('$next\n', flush: true);
    await pending.rename(cursor.path);
  }

  Future<void> _shareL1Batch() async {
    final file = _lastL1BatchFile;
    if (file == null || !await file.exists()) {
      throw StateError('L1_NO_COMPLETED_BATCH');
    }
    await SharePlus.instance.share(ShareParams(
      subject: 'Issue13 Lab L1 partial Android PDF page evidence',
      files: <XFile>[XFile(file.path)],
    ));
  }

  // Explicit one-tap share of verified contiguous Lab JSONL batches and
  // bounded Lab-only debug logs. The official PDF and finance DB are excluded.
  Future<void> _shareL1EvidenceBundle() async {
    final lab = _labDirectory;
    if (lab == null) throw StateError('LAB_NOT_INITIALIZED');
    final index = int.tryParse(_evidenceWindowController.text.trim());
    if (index == null || index < 1) {
      throw StateError('L1_BUNDLE_WINDOW_INDEX_INVALID');
    }
    final result = await LabL1EvidenceBundle.create(
      lab: lab,
      labHead: _labHead,
      windowIndex: index,
    );
    await _log('L1_EVIDENCE_BUNDLE_READY '
        'window_index=$index '
        'last_page=${result.manifest['last_page']} '
        'batches=${result.manifest['batch_count']} '
        'zip_sha256=${result.zipSha256} '
        'official_full_page_evidence=HOLD global_not_win=HOLD');
    await SharePlus.instance.share(ShareParams(
      subject: 'Issue13 Lab bounded JSONL chain + SHA manifest + debug logs',
      files: <XFile>[XFile(result.file.path)],
    ));
  }

  Future<void> _testPlatformOpenOnly() async {
    final result = await _runPlatformProbe(candidate: '');
    if (result['status'] != 'complete') {
      throw StateError('PLATFORM_PDF_OPEN_FAILED result=$result');
    }
    await _log(
      'PLATFORM_OPEN_ONLY_PASS page_count=${result['page_count']}',
    );
  }

  // Present a bounded single-PDF diagnostic outcome; never formal NOT_WIN.
  Future<void> _platformBinarySearch() async {
    final candidate = _candidate();
    final result = await _runPlatformProbe(candidate: candidate);
    final outcome = LabSearchResult.fromProbe(
      candidate: candidate,
      probe: result,
    );
    if (mounted) setState(() => _searchResult = outcome);
    await _log(
      'PLATFORM_SEARCH_RESULT candidate=$candidate '
      'matched=${result['matched']} matched_page=${result['matched_page']} '
      'pages_read=${result['pages_read']} page_count=${result['page_count']} '
      'verdict=${outcome.verdict.name} mode=DIAGNOSTIC_ONLY '
      'global_not_win=HOLD',
    );
    if (outcome.verdict == LabSearchVerdict.hold) {
      throw StateError('PLATFORM_SEARCH_RESULT_HOLD');
    }
  }

  List<String> _invoiceTokens(String text) {
    final normalized = text.toUpperCase();
    final pattern = RegExp(r'[A-Z]\s*[A-Z](?:\s*[0-9]){8}');
    final values = <String>{};
    for (final match in pattern.allMatches(normalized)) {
      final before =
          match.start > 0 ? normalized.substring(match.start - 1, match.start) : '';
      final after = match.end < normalized.length
          ? normalized.substring(match.end, match.end + 1)
          : '';
      if (RegExp(r'[A-Z0-9]').hasMatch(before) ||
          RegExp(r'[A-Z0-9]').hasMatch(after)) {
        continue;
      }
      final value = match.group(0)!.replaceAll(RegExp(r'\s+'), '');
      if (RegExp(r'^[A-Z]{2}[0-9]{8}$').hasMatch(value)) values.add(value);
    }
    final sorted = values.toList()..sort();
    return sorted;
  }

  String _candidate() {
    final value = _candidateController.text
        .replaceAll(RegExp(r'[\s-]'), '')
        .toUpperCase();
    if (!RegExp(r'^[A-Z]{2}[0-9]{8}$').hasMatch(value)) {
      throw StateError('請輸入 2 個英文字母 + 8 位數字的發票號碼');
    }
    return value;
  }

  // ignore: unused_element
  Future<void> _directBinarySearch() async {
    final candidate = _candidate();
    final file = await _ensureExactPdf();
    await _log('DIRECT_SEARCH_BEGIN candidate=$candidate');
    final opened = await _openPdfium(file);
    final sessionId = opened['sessionId']?.toString() ?? '';
    final pageCount = (opened['length'] as num?)?.toInt() ?? 0;
    if (sessionId.isEmpty || pageCount <= 0) {
      throw StateError('PDFIUM_SESSION_INVALID');
    }

    final pageCache = <int, List<String>>{};
    var pagesRead = 0;

    Future<List<String>> readPage(int page) async {
      final cached = pageCache[page];
      if (cached != null) return cached;
      final timer = Stopwatch()..start();
      await _log('PAGE_CALL_BEGIN page=$page/$pageCount');
      final text = await _channel.invokeMethod<String>(
            'getPdfiumSessionPageText',
            <String, Object?>{'sessionId': sessionId, 'number': page},
          ) ??
          '';
      final tokens = _invoiceTokens(text);
      pagesRead += 1;
      pageCache[page] = tokens;
      await _log(
        'PAGE_CALL_END page=$page elapsed_ms=${timer.elapsedMilliseconds} '
        'chars=${text.length} tokens=${tokens.length} '
        'first=${tokens.isEmpty ? '-' : tokens.first} '
        'last=${tokens.isEmpty ? '-' : tokens.last}',
      );
      if (tokens.isEmpty) {
        throw StateError('PAGE_HAS_NO_INVOICE_TOKENS page=$page');
      }
      return tokens;
    }

    var low = 1;
    var high = pageCount;
    int? matchedPage;
    try {
      while (low <= high) {
        final middle = low + ((high - low) >> 1);
        final tokens = await readPage(middle);
        final first = tokens.first;
        final last = tokens.last;
        await _log(
          'BINARY_STEP candidate=$candidate low=$low high=$high middle=$middle '
          'first=$first last=$last',
        );
        if (candidate.compareTo(first) < 0) {
          high = middle - 1;
          await _log('BINARY_DECISION direction=LOWER new_high=$high');
          continue;
        }
        if (candidate.compareTo(last) > 0) {
          low = middle + 1;
          await _log('BINARY_DECISION direction=HIGHER new_low=$low');
          continue;
        }
        if (tokens.contains(candidate)) {
          matchedPage = middle;
          break;
        }
        for (final neighbor in <int>[middle - 1, middle + 1]) {
          if (neighbor < 1 || neighbor > pageCount) continue;
          if ((await readPage(neighbor)).contains(candidate)) {
            matchedPage = neighbor;
            break;
          }
        }
        break;
      }

      if (matchedPage == null && low > high) {
        for (final boundary in <int>{low, high}) {
          if (boundary < 1 || boundary > pageCount) continue;
          if ((await readPage(boundary)).contains(candidate)) {
            matchedPage = boundary;
            break;
          }
        }
      }
      await _log(
        'DIRECT_SEARCH_RESULT candidate=$candidate matched=${matchedPage != null} '
        'page=${matchedPage ?? 0} pages_read=$pagesRead page_count=$pageCount',
      );
    } finally {
      await _channel.invokeMethod<void>(
        'closePdfiumSession',
        <String, Object?>{'sessionId': sessionId},
      );
      await _log('DIRECT_SEARCH_SESSION_CLOSED');
    }
  }

  // ignore: unused_element
  Future<void> _productionWorkerSearch() async {
    final candidate = _candidate();
    final file = await _ensureExactPdf();
    final reference = await _loadReference();
    final artifact = OfficialCloudAwardDownloadedArtifact(
      reference: reference,
      file: file,
      sizeBytes: await file.length(),
      sha256: _expectedSha256,
    );
    await _log('WORKER_SEARCH_BEGIN candidate=$candidate');
    final result = await const PdfiumCloudAwardSortedPdfCandidateLookup()
        .findMatches(
      artifact: artifact,
      candidateInvoiceNumbers: <String>[candidate],
      onProgress: (progress) {
        unawaited(
          _log(
            'WORKER_PROGRESS stage=${progress.stage} '
            'candidate=${progress.candidateIndex}/${progress.candidateCount} '
            'page=${progress.pageNumber}/${progress.pageCount} '
            'pages_read=${progress.pagesRead} '
            'elapsed_ms=${progress.elapsed.inMilliseconds} '
            'eta_ms=${progress.estimatedRemaining?.inMilliseconds ?? -1} '
            'source=${progress.sourceBytesRead}/${progress.sourceBytesTotal}',
          ),
        );
      },
    );
    await _log(
      'WORKER_SEARCH_RESULT candidate=$candidate '
      'matched=${result.matchedInvoiceNumbers.contains(candidate)} '
      'matched_page=${result.matchedPageNumbers[candidate] ?? 0} '
      'pages_read=${result.pagesRead} page_count=${result.pageCount}',
    );
  }

  Future<void> _clearLogs() async {
    final file = _dartLogFile;
    if (file != null && await file.exists()) await file.delete();
    await _channel.invokeMethod<void>('clearCloud500LabNativeLog');
    if (mounted) {
      setState(() => _logLines.clear());
    }
    await _log('LOGS_CLEARED');
  }

  Future<String> _combinedLog() async {
    final buffer = StringBuffer();
    buffer.writeln('=== DART LAB LOG ===');
    final dart = _dartLogFile;
    if (dart != null && await dart.exists()) {
      buffer.writeln(await dart.readAsString());
    }
    buffer.writeln('=== NATIVE LAB LOG ===');
    final lab = _labDirectory;
    if (lab != null) {
      final native = File(
        '${lab.parent.path}${Platform.pathSeparator}'
        'issue13_cloud500_diag_native.log',
      );
      if (await native.exists()) {
        buffer.writeln(await native.readAsString());
      } else {
        // ApplicationSupportDirectory is normally files/issue13_cloud500_diag;
        // the plugin log is one level above in files/.
        final alternate = File(
          '${lab.path}${Platform.pathSeparator}'
          'issue13_cloud500_diag_native.log',
        );
        if (await alternate.exists()) buffer.writeln(await alternate.readAsString());
      }
    }
    return buffer.toString();
  }

  Future<void> _shareLogs() async {
    final text = await _combinedLog();
    if (text.trim().isEmpty) throw StateError('目前沒有 log');
    await SharePlus.instance.share(
      ShareParams(
        subject: 'Issue #13 Cloud500 PDF Lab Debug Log',
        text: text,
      ),
    );
  }

  Future<void> _copyLogs() async {
    final text = await _combinedLog();
    await Clipboard.setData(ClipboardData(text: text));
    await _log('LOG_COPIED_TO_CLIPBOARD chars=${text.length}');
  }

  @override
  Widget build(BuildContext context) {
    final buttons = <Widget>[
      FilledButton(
        onPressed: _actionsDisabled
            ? null
            : () => _run('下載/驗證 115-07-08 \$500 PDF', () async {
                  await _ensureExactPdf();
                }),
        child: const Text('1. 下載／驗證官方 PDF'),
      ),
      FilledButton.tonal(
        onPressed:
            _actionsDisabled ? null : () => _run('系統 PDF Viewer', _openSystemViewer),
        child: const Text('2. 用系統 PDF Viewer 開啟'),
      ),
      FilledButton.tonal(
        onPressed: _actionsDisabled
            ? null
            : () => _run(
                  'Android PdfRenderer Open Only',
                  _testPlatformOpenOnly,
                ),
        child: const Text('3. Android PdfRenderer Open + PageCount'),
      ),
      TextField(
        controller: _candidateController,
        textCapitalization: TextCapitalization.characters,
        decoration: const InputDecoration(
          labelText: '指定發票號碼',
          hintText: '2 個英文字母 + 8 位數字',
          border: OutlineInputBorder(),
        ),
      ),
      FilledButton(
        onPressed: _actionsDisabled
            ? null
            : () => _run(
                  'Android PdfRenderer Binary Search',
                  _platformBinarySearch,
                ),
        child: const Text('4. Android PdfRenderer 指定號碼二分搜尋'),
      ),
      FilledButton.tonal(
        onPressed: _actionsDisabled ? null : () => _run(
          'L1 API35 bounded page export', () async {
            await _exportNextL1Batch();
          }),
        child: const Text('L1. 擷取下一批最多 4 頁（非完整判定）'),
      ),
      FilledButton.tonal(
        onPressed: _actionsDisabled ? null : () => _run(
          'L1 bounded multi-batch export', _exportBoundedL1Run),
        child: const Text('L1. 有界連續擷取最多 32 頁（非官方驗收）'),
      ),
      OutlinedButton(
        onPressed: _actionsDisabled ? null : () => _run(
          'Share partial L1 JSONL', _shareL1Batch),
        child: const Text('分享上一批 L1 JSONL'),
      ),
      TextField(
        controller: _evidenceWindowController,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(
          labelText: 'L1 證據匯出窗口編號（從 1 開始）',
          helperText: '每包最多12批；18批可選第1包(1–48)、第2包(49–72)。'
              '僅保留兩個輪替ZIP位置，請逐包分享保存。',
          border: OutlineInputBorder(),
        ),
      ),
      OutlinedButton(
        onPressed: _actionsDisabled ? null : () => _run(
          'Share bounded L1 evidence bundle',
          widget.testHooks?.shareEvidenceBundle ?? _shareL1EvidenceBundle),
        child: const Text('分包分享 JSONL＋SHA Manifest＋Debug Log'),
      ),
      const Text('每包僅包含有界JSONL、Manifest與Debug Log；'
          '不含官方PDF或帳本。Log可能含輸入號碼，僅分享給可信對象。'),
      const ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text('第三方 PDFium 2.0.1：已證實 native crash'),
        subtitle: Text(
          '已由實機 ApplicationExitInfo reason=5 / crash 證實。'
          '直接 PDFium 與 Production worker 測試已停用，避免重複觸發已知 native crash。',
        ),
      ),
      const Divider(),
      OutlinedButton(
        onPressed: _actionsDisabled ? null : () => _run('分享 Debug Log', _shareLogs),
        child: const Text('分享完整 Debug Log'),
      ),
      OutlinedButton(
        onPressed: _actionsDisabled ? null : () => _run('複製 Debug Log', _copyLogs),
        child: const Text('複製完整 Debug Log'),
      ),
      TextButton(
        onPressed: _actionsDisabled ? null : () => _run('清除 Log', _clearLogs),
        child: const Text('清除 Log'),
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('115-07-08 Cloud500 PDF Lab')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: SelectableText(
                  'Cloud500 PDF Lab $_runtimeVersion\n'
                  'package: $_runtimePackage\n'
                  'head: ${_labHead.length > 12 ? _labHead.substring(0, 12) : _labHead}\n'
                  'branch: $_labBranch\n'
                  'backend: $_labBackend',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _status,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (_searchResult != null) ...<Widget>[
              LabSearchResultCard(result: _searchResult!),
              const SizedBox(height: 8),
            ],
            SelectableText(
              'Expected bytes: $_expectedBytes\n'
              'SHA-256: $_expectedSha256\n'
              'Lab path: ${_labDirectory?.path ?? '-'}\n'
              'PDF path: ${_pdfFile?.path ?? '-'}',
            ),
            const SizedBox(height: 16),
            ...buttons.map(
              (button) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: button,
              ),
            ),
            const SizedBox(height: 8),
            Text('即時 Debug Log', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Container(
              height: 360,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                border: Border.all(color: Theme.of(context).dividerColor),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ListView.builder(
                controller: _scrollController,
                itemCount: _logLines.length,
                itemBuilder: (context, index) => SelectableText(
                  _logLines[index],
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
