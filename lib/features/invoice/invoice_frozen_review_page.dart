import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../recognition_ai/recognition_ai_status_indicator.dart';
import 'daily_capture_entry_shell.dart';
import 'gemini/gemini_invoice_review.dart';
import 'gemini/gemini_invoice_review_client.dart';
import 'gemini/gemini_invoice_review_coordinator.dart';
import 'gemini/gemini_invoice_settings.dart';
import 'gemini/gemini_invoice_settings_repository.dart';
import 'google_mlkit_traditional_invoice_recognizer.dart';
import 'image_capture_staging.dart';
import 'invoice_automatic_recognition_coordinator.dart';
import 'invoice_capture_review_flow.dart';
import 'invoice_live_capture_page.dart';
import 'invoice_local_recognition_coordinator.dart';
import 'invoice_recognition_evidence_exporter.dart';
import 'invoice_review_form_view_model.dart';
import 'mobile_scanner_invoice_qr_decoder.dart';
import 'traditional_invoice_ocr_review.dart';
import 'traditional_tax_id_temporal_repair.dart';

class InvoiceFrozenReviewPage extends StatefulWidget {
  const InvoiceFrozenReviewPage({
    super.key,
    required this.liveResult,
    this.reviewFlowCoordinator,
    this.geminiReviewCoordinator,
    this.evidenceExporter = const InvoiceRecognitionEvidenceExporter(),
  });

  static const String routeName = 'invoice-frozen-review';
  static const String routePath = '/invoice-capture/live/review';
  static const Key geminiAcknowledgementKey = Key('invoice_frozen_gemini_ack');
  static const Key forceGeminiKey = Key('invoice_frozen_force_gemini');
  static const Key exportEvidenceKey = Key('invoice_frozen_export_evidence');
  static const Key aiStatusKey = Key('invoice_frozen_ai_status');
  static const Key aiRunningStatusKey = Key('invoice_frozen_ai_running_status');

  final InvoiceLiveCaptureResult liveResult;
  final InvoiceCaptureReviewFlowCoordinator? reviewFlowCoordinator;
  final GeminiInvoiceReviewCoordinator? geminiReviewCoordinator;
  final InvoiceRecognitionEvidenceExporter evidenceExporter;

  @override
  State<InvoiceFrozenReviewPage> createState() =>
      _InvoiceFrozenReviewPageState();
}

class _InvoiceFrozenReviewPageState extends State<InvoiceFrozenReviewPage> {
  late final ImageCaptureStagingItem _item;
  late final InvoiceCaptureReviewFlowCoordinator _reviewFlowCoordinator;
  late final GeminiInvoiceReviewCoordinator _geminiReviewCoordinator;
  InvoiceCaptureReviewFlowResult? _localResult;
  GeminiInvoiceReviewExecution? _geminiExecution;
  GeminiInvoiceEscalationDecision? _geminiDecision;
  bool _geminiComparisonAcknowledged = false;
  bool _automaticGeminiAttempted = false;
  InvoiceRecognitionEvidenceExportResult? _evidenceResult;
  String? _error;
  bool _busy = true;
  bool _geminiBusy = false;
  bool _evidenceBusy = false;
  Timer? _geminiElapsedTimer;
  DateTime? _geminiStartedAt;
  Duration _geminiElapsed = Duration.zero;
  String _geminiActiveModel = GeminiInvoiceSettings.defaultModel;
  String _geminiProgressMessage = '正在確認可用 API Key 與模型…';
  int _geminiPhysicalAttemptOrdinal = 0;

  @override
  void initState() {
    super.initState();
    final capture = widget.liveResult;
    _item = ImageCaptureStagingItem(
      id: 'invoice-review-${DateTime.now().microsecondsSinceEpoch}',
      intent: DailyCaptureIntent.invoice,
      source: capture.origin == InvoiceCaptureOrigin.gallery
          ? ImageCaptureStagingSource.gallery
          : ImageCaptureStagingSource.camera,
      localReference: capture.localReference,
      fileName: capture.fileName,
      status: ImageCaptureStagingStatus.pendingReview,
      createdAt: DateTime.now(),
    );
    _reviewFlowCoordinator =
        widget.reviewFlowCoordinator ??
        InvoiceCaptureReviewFlowCoordinator(
          recognitionCoordinator: InvoiceAutomaticRecognitionCoordinator(
            qrRunner: InvoiceLocalRecognitionCoordinator(
              decoder: NativeInvoiceQrDecoder(),
            ).recognize,
            ocrRunner: const TraditionalInvoiceOcrCoordinator(
              recognizer: GoogleMlKitTraditionalInvoiceRecognizer(),
            ).recognize,
          ),
        );
    if (widget.geminiReviewCoordinator != null) {
      _geminiReviewCoordinator = widget.geminiReviewCoordinator!;
    } else {
      const settingsRepository = GeminiInvoiceSettingsRepository();
      _geminiReviewCoordinator = GeminiInvoiceReviewCoordinator(
        settingsStore: settingsRepository,
        client: _ProgressReportingGeminiInvoiceReviewClient(
          delegate: GeminiInvoiceReviewClient(),
          onAttempt: _onGeminiPhysicalAttempt,
        ),
      );
      settingsRepository.load().then((settings) {
        if (!mounted) return;
        setState(() => _geminiActiveModel = settings.model);
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _runLocalAndEscalate());
  }

  @override
  void dispose() {
    _geminiElapsedTimer?.cancel();
    super.dispose();
  }

  InvoiceRecognitionRequestedRoute get _requestedRoute =>
      widget.liveResult.origin == InvoiceCaptureOrigin.gallery
      ? InvoiceRecognitionRequestedRoute.automatic
      : switch (widget.liveResult.classification) {
          InvoiceLiveClassification.electronic =>
            InvoiceRecognitionRequestedRoute.electronicInvoiceQr,
          InvoiceLiveClassification.traditional =>
            InvoiceRecognitionRequestedRoute.traditionalInvoiceOcr,
          InvoiceLiveClassification.searching =>
            InvoiceRecognitionRequestedRoute.automatic,
        };

  PositionalTaxIdTemporalRepairResult get _liveTemporalTaxRepair {
    if (widget.liveResult.origin != InvoiceCaptureOrigin.liveCamera ||
        widget.liveResult.classification !=
            InvoiceLiveClassification.traditional) {
      return const PositionalTaxIdTemporalRepairResult.none();
    }
    final observations = <PositionalTaxIdFrameObservation>[];
    for (final sample in widget.liveResult.liveHistory) {
      if (sample.snapshot.classification !=
          InvoiceLiveClassification.traditional) {
        continue;
      }
      final invoiceNumber = sample.snapshot.invoiceNumber.trim();
      if (invoiceNumber.isEmpty) continue;
      final rawCandidate = extractUnverifiedPositionalHeaderTaxIdFromLines(
        rawLines: sample.rawLines,
        invoiceNumber: invoiceNumber,
      );
      if (rawCandidate == null) continue;
      observations.add(
        PositionalTaxIdFrameObservation(
          invoiceNumber: invoiceNumber,
          rawCandidate: rawCandidate,
        ),
      );
    }
    if (observations.length < 2) {
      return const PositionalTaxIdTemporalRepairResult.none();
    }
    final current = observations.last;
    return resolvePositionalTaxIdTemporalRepair(
      history: observations.sublist(0, observations.length - 1),
      currentInvoiceNumber: current.invoiceNumber,
      currentRawCandidate: current.rawCandidate,
    );
  }

  Future<void> _runLocalAndEscalate() async {
    try {
      final local = await _reviewFlowCoordinator.recognize(
        image: _item,
        requestedRoute: _requestedRoute,
      );
      if (!mounted) return;
      final decision = const GeminiInvoiceEscalationPolicy().evaluate(
        local.recognitionResult,
      );
      setState(() {
        _localResult = local;
        _geminiDecision = decision;
        _busy = false;
      });
      await _maybeRunAutomaticGemini(local);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '影像本機辨識失敗：${error.runtimeType}';
      });
    }
  }

  Future<void> _maybeRunAutomaticGemini(
    InvoiceCaptureReviewFlowResult local,
  ) async {
    if (_automaticGeminiAttempted) return;
    _automaticGeminiAttempted = true;
    await _runGemini(local, forceReview: false, automatic: true);
  }

  void _startGeminiProgress() {
    _geminiElapsedTimer?.cancel();
    _geminiStartedAt = DateTime.now();
    _geminiElapsed = Duration.zero;
    _geminiPhysicalAttemptOrdinal = 0;
    _geminiProgressMessage = '正在確認可用 API Key 與模型…';
    _geminiElapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final started = _geminiStartedAt;
      if (!mounted || started == null) return;
      setState(() => _geminiElapsed = DateTime.now().difference(started));
    });
  }

  void _stopGeminiProgress() {
    _geminiElapsedTimer?.cancel();
    _geminiElapsedTimer = null;
    final started = _geminiStartedAt;
    if (started != null) {
      _geminiElapsed = DateTime.now().difference(started);
    }
  }

  void _onGeminiPhysicalAttempt(String model) {
    if (!mounted) return;
    setState(() {
      _geminiPhysicalAttemptOrdinal += 1;
      _geminiActiveModel = model;
      _geminiProgressMessage = _geminiPhysicalAttemptOrdinal == 1
          ? '正在辨識…'
          : '正在切換可用 Key／模型並重試…';
    });
  }

  Future<void> _runGemini(
    InvoiceCaptureReviewFlowResult local, {
    required bool forceReview,
    bool automatic = false,
  }) async {
    if (_geminiBusy) return;
    _startGeminiProgress();
    setState(() {
      _geminiBusy = true;
      _error = null;
      if (forceReview && !automatic) _geminiComparisonAcknowledged = false;
    });
    try {
      final execution = automatic
          ? await _geminiReviewCoordinator.reviewAutomatically(
              localResult: local.recognitionResult,
              localReference: _item.localReference,
            )
          : await _geminiReviewCoordinator.review(
              localResult: local.recognitionResult,
              localReference: _item.localReference,
              forceReview: forceReview,
            );
      if (!mounted) return;
      final previous = _geminiExecution;
      final merged = execution.withCumulativeAudit(
        requestCount: (previous?.requestCount ?? 0) + execution.requestCount,
        automaticUploadPerformed:
            (previous?.automaticUploadPerformed ?? false) ||
            execution.automaticUploadPerformed,
      );
      setState(() {
        _geminiExecution = merged;
        if (execution.model.trim().isNotEmpty) {
          _geminiActiveModel = execution.model;
        }
      });
    } catch (error) {
      if (mounted) setState(() => _error = 'AI 覆核失敗：${error.runtimeType}');
    } finally {
      _stopGeminiProgress();
      if (mounted) setState(() => _geminiBusy = false);
    }
  }

  Future<void> _exportEvidence() async {
    final local = _localResult;
    if (local == null || _evidenceBusy) return;
    setState(() {
      _evidenceBusy = true;
      _error = null;
    });
    try {
      final repair = _liveTemporalTaxRepair;
      final result = await widget.evidenceExporter.exportAndShare(
        item: _item,
        localResult: local,
        geminiExecution: _geminiExecution,
        captureContext: repair.accepted
            ? _captureContextWithTemporalTaxRepair(widget.liveResult, repair)
            : widget.liveResult,
      );
      if (!mounted) return;
      setState(() => _evidenceResult = result);
    } catch (error) {
      if (mounted) setState(() => _error = '證據包匯出失敗：${error.runtimeType}');
    } finally {
      if (mounted) setState(() => _evidenceBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final local = _localResult;
    final execution = _geminiExecution;
    final ai = execution?.candidate;
    final repair = _liveTemporalTaxRepair;
    final localTaxId = local == null
        ? ''
        : _localSellerTaxId(
            local,
            temporalRepair: repair.accepted ? repair.repairedValue : '',
          );
    final isGallery = widget.liveResult.origin == InvoiceCaptureOrigin.gallery;
    return Scaffold(
      appBar: AppBar(title: const Text('發票覆核')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: <Widget>[
          Card(
            child: ListTile(
              leading: Icon(
                isGallery
                    ? Icons.photo_outlined
                    : Icons.document_scanner_outlined,
              ),
              title: Text(isGallery ? '圖片發票' : widget.liveResult.classification.label),
              subtitle: Text(isGallery ? '圖片讀取' : 'Live 凍結影像'),
            ),
          ),
          if (_busy || _geminiBusy || _evidenceBusy) ...<Widget>[
            const SizedBox(height: 12),
            LinearProgressIndicator(
              semanticsLabel: _evidenceBusy
                  ? '證據包建立中'
                  : _geminiBusy
                  ? 'AI 覆核中'
                  : '本機辨識中',
            ),
          ],
          if (_geminiBusy) ...<Widget>[
            const SizedBox(height: 10),
            Card(
              key: InvoiceFrozenReviewPage.aiRunningStatusKey,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: RecognitionAiRunningStatusIndicator(
                  provider: 'Gemini',
                  activeModel: _geminiActiveModel,
                  elapsed: _geminiElapsed,
                  message: _geminiProgressMessage,
                ),
              ),
            ),
          ],
          if (_error != null) ...<Widget>[
            const SizedBox(height: 12),
            Card(child: ListTile(title: Text(_error!))),
          ],
          if (local != null) ...<Widget>[
            const SizedBox(height: 12),
            _CandidateCard(
              title: '本機辨識',
              subtitle: local.recognitionResult.message,
              fields: <(String, String)>[
                for (final field in local.formModel.fields)
                  if (field.key != InvoiceReviewFieldKey.sellerTaxId)
                    (field.label, field.value),
                ('賣方統編', localTaxId),
                if (repair.accepted)
                  ('統編證據', '${repair.observations} 個 Live frame'),
              ],
            ),
            const SizedBox(height: 12),
            if (_geminiDecision != null)
              Card(
                key: InvoiceFrozenReviewPage.aiStatusKey,
                child: ListTile(
                  leading: Icon(
                    _geminiDecision!.shouldReview
                        ? Icons.auto_awesome_outlined
                        : Icons.verified_outlined,
                  ),
                  title: Text(_aiStatusTitle(_geminiDecision!, execution)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(_aiStatusSubtitle(_geminiDecision!, execution)),
                      if (execution?.sessionContext != null) ...<Widget>[
                        const SizedBox(height: 6),
                        RecognitionAiStatusIndicator(
                          context: execution!.sessionContext!,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            if (ai != null) ...<Widget>[
              const SizedBox(height: 12),
              _CandidateCard(
                title: 'AI 第二意見',
                subtitle: _aiCandidateSubtitle(execution),
                fields: <(String, String)>[
                  ('發票號碼', ai.invoiceNumber),
                  ('期別', ai.invoicePeriod),
                  ('賣方統編', ai.sellerTaxId),
                  ('日期', ai.invoiceDate),
                  ('時間', ai.invoiceTime),
                  ('商家', ai.merchantName),
                  ('總金額', _amount(ai.totalAmount)),
                ],
              ),
              const SizedBox(height: 12),
              _ComparisonCard(
                local: local.formModel,
                localTaxId: localTaxId,
                ai: ai,
              ),
              CheckboxListTile(
                key: InvoiceFrozenReviewPage.geminiAcknowledgementKey,
                contentPadding: EdgeInsets.zero,
                value: _geminiComparisonAcknowledged,
                onChanged: (value) => setState(
                  () => _geminiComparisonAcknowledged = value == true,
                ),
                title: const Text('我已核對本機與 AI 結果'),
              ),
            ],
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              key: InvoiceFrozenReviewPage.forceGeminiKey,
              onPressed: _geminiBusy
                  ? null
                  : () => _runGemini(
                      local,
                      forceReview: _geminiDecision?.shouldReview != true,
                    ),
              icon: const Icon(Icons.auto_awesome_outlined),
              label: Text(ai == null ? 'AI 覆核' : '重新 AI 覆核'),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              key: InvoiceFrozenReviewPage.exportEvidenceKey,
              onPressed: _evidenceBusy ? null : _exportEvidence,
              icon: const Icon(Icons.archive_outlined),
              label: Text(_evidenceBusy ? '建立證據包中…' : '匯出辨識證據 ZIP'),
            ),
          ],
          if (_evidenceResult != null) ...<Widget>[
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text(
                      'Evidence ZIP 已建立',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      'Capture SHA-256：${_evidenceResult!.captureImageSha256}',
                    ),
                    Text(
                      'AI SHA-256：${_evidenceResult!.geminiInputSha256 ?? '尚未呼叫 AI'}',
                    ),
                    Text(
                      '同一影像：${_sameImageLabel(_evidenceResult!.geminiInputMatchesCapture)}',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ProgressReportingGeminiInvoiceReviewClient
    implements GeminiInvoiceReviewPort {
  _ProgressReportingGeminiInvoiceReviewClient({
    required this.delegate,
    required this.onAttempt,
  });

  final GeminiInvoiceReviewPort delegate;
  final void Function(String model) onAttempt;

  @override
  Future<GeminiInvoiceReviewCandidate> review({
    required String apiKey,
    required String model,
    required Uint8List imageBytes,
    required String mimeType,
    Map<String, Object?> localSummary = const <String, Object?>{},
  }) {
    onAttempt(model);
    return delegate.review(
      apiKey: apiKey,
      model: model,
      imageBytes: imageBytes,
      mimeType: mimeType,
      localSummary: localSummary,
    );
  }
}

String _aiStatusTitle(
  GeminiInvoiceEscalationDecision decision,
  GeminiInvoiceReviewExecution? execution,
) {
  if (execution?.status == GeminiInvoiceReviewExecutionStatus.success) {
    return execution!.invocationMode == GeminiInvoiceReviewInvocationMode.automatic
        ? '已自動 AI 覆核'
        : '已取得 AI 第二意見';
  }
  if (execution?.status == GeminiInvoiceReviewExecutionStatus.failed) {
    return 'AI 覆核失敗';
  }
  if (execution?.status == GeminiInvoiceReviewExecutionStatus.missingApiKey) {
    return 'AI 覆核需要 API Key';
  }
  if (execution?.status == GeminiInvoiceReviewExecutionStatus.skippedLocalComplete) {
    return '本機辨識完成';
  }
  return decision.shouldReview ? '建議 AI 覆核' : '本機辨識完成';
}

String _aiStatusSubtitle(
  GeminiInvoiceEscalationDecision decision,
  GeminiInvoiceReviewExecution? execution,
) {
  if (execution?.status == GeminiInvoiceReviewExecutionStatus.success) {
    return '請核對本機與 AI 欄位。';
  }
  if (execution?.status == GeminiInvoiceReviewExecutionStatus.failed ||
      execution?.status == GeminiInvoiceReviewExecutionStatus.missingApiKey ||
      execution?.status == GeminiInvoiceReviewExecutionStatus.invalidImage) {
    return execution!.message;
  }
  if (!decision.shouldReview) return '關鍵欄位完整，未自動送出影像。';
  if (execution?.automaticReviewSettingEnabled == true) {
    return '本機信心不足，已依設定啟動 AI 覆核。';
  }
  return '本機信心不足或欄位不完整。';
}

String _aiCandidateSubtitle(GeminiInvoiceReviewExecution? execution) {
  if (execution == null) return '第二意見';
  return execution.invocationMode == GeminiInvoiceReviewInvocationMode.automatic
      ? '自動覆核結果'
      : '手動覆核結果';
}

InvoiceLiveCaptureResult _captureContextWithTemporalTaxRepair(
  InvoiceLiveCaptureResult capture,
  PositionalTaxIdTemporalRepairResult repair,
) {
  final base = capture.liveSnapshot;
  final repairSnapshot = InvoiceLiveSnapshot(
    classification: base.classification,
    invoiceNumber: base.invoiceNumber,
    invoiceDate: base.invoiceDate,
    sellerTaxId: repair.repairedValue,
    hasSellerIdentityContext: true,
    totalAmount: base.totalAmount,
    qrCount: base.qrCount,
    hasValidLeftQr: base.hasValidLeftQr,
    score: base.score,
    stableObservations: base.stableObservations,
    canFreeze: base.canFreeze,
    message: base.message,
  );
  final repairEvidence = InvoiceLiveFrameEvidence(
    timestamp: DateTime.now(),
    snapshot: repairSnapshot,
    rawLines: <String>[
      'repairRule=${repair.rule}',
      'repairObservations=${repair.observations}',
      for (final raw in repair.rawCandidates) 'rawCandidate=$raw',
    ],
    sellerTaxIdCandidate: repair.repairedValue,
    sellerTaxIdSource: positionalTaxIdTemporalRepairSource,
    sellerTaxIdChecksumValid: true,
  );
  return InvoiceLiveCaptureResult(
    localReference: capture.localReference,
    fileName: capture.fileName,
    classification: capture.classification,
    autoFrozen: capture.autoFrozen,
    liveSnapshot: capture.liveSnapshot,
    origin: capture.origin,
    liveHistory: List<InvoiceLiveFrameEvidence>.unmodifiable(
      <InvoiceLiveFrameEvidence>[...capture.liveHistory, repairEvidence],
    ),
  );
}

String _localSellerTaxId(
  InvoiceCaptureReviewFlowResult local, {
  String temporalRepair = '',
}) {
  final explicit =
      local.formModel.fieldFor(InvoiceReviewFieldKey.sellerTaxId)?.value ?? '';
  if (explicit.trim().isNotEmpty) return explicit.trim();
  return temporalRepair.trim();
}

class _CandidateCard extends StatelessWidget {
  const _CandidateCard({
    required this.title,
    required this.subtitle,
    required this.fields,
  });

  final String title;
  final String subtitle;
  final List<(String, String)> fields;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(subtitle),
            for (final field in fields)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '${field.$1}：${field.$2.trim().isEmpty ? '—' : field.$2}',
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ComparisonCard extends StatelessWidget {
  const _ComparisonCard({
    required this.local,
    required this.localTaxId,
    required this.ai,
  });

  final InvoiceReviewFormViewModel local;
  final String localTaxId;
  final GeminiInvoiceReviewCandidate ai;

  @override
  Widget build(BuildContext context) {
    final localSeller =
        local.fieldFor(InvoiceReviewFieldKey.sellerName)?.value.trim() ?? '';
    final merchant = localSeller.startsWith('賣方統編') ? '' : localSeller;
    final rows = <(String, String, String, bool)>[
      (
        '發票號碼',
        local.fieldFor(InvoiceReviewFieldKey.invoiceNumber)?.value ?? '',
        ai.invoiceNumber,
        false,
      ),
      (
        '發票日期',
        local.fieldFor(InvoiceReviewFieldKey.invoiceDate)?.value ?? '',
        ai.invoiceDate,
        false,
      ),
      ('商家', merchant, ai.merchantName, false),
      ('賣方統編', localTaxId, ai.sellerTaxId, false),
      (
        '總金額',
        local.fieldFor(InvoiceReviewFieldKey.totalAmount)?.value ?? '',
        _amount(ai.totalAmount),
        true,
      ),
      (
        '發票期別',
        local.fieldFor(InvoiceReviewFieldKey.invoicePeriod)?.value ?? '',
        ai.invoicePeriod,
        false,
      ),
      (
        '交易時間',
        local.fieldFor(InvoiceReviewFieldKey.invoiceTime)?.value ?? '',
        ai.invoiceTime,
        false,
      ),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              '本機 ↔ AI 欄位比較',
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            for (final row in rows) ...<Widget>[
              const Divider(height: 18),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      row.$1,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Chip(
                    label: Text(
                      _compare(
                        row.$2,
                        row.$3,
                        numeric: row.$4,
                        invoicePeriod: row.$1 == '發票期別',
                      ),
                    ),
                  ),
                ],
              ),
              Text('本機：${row.$2.trim().isEmpty ? '—' : row.$2}'),
              Text('AI：${row.$3.trim().isEmpty ? '—' : row.$3}'),
            ],
          ],
        ),
      ),
    );
  }
}

String _amount(double? value) {
  if (value == null) return '';
  return value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toString();
}

String _compare(
  String local,
  String ai, {
  required bool numeric,
  bool invoicePeriod = false,
}) {
  final left = local.trim();
  final right = ai.trim();
  if (left.isEmpty && right.isEmpty) return 'BOTH_MISSING';
  if (left.isEmpty) return 'MISSING_LOCAL';
  if (right.isEmpty) return 'MISSING_AI';
  if (numeric) {
    final a = double.tryParse(left.replaceAll(',', ''));
    final b = double.tryParse(right.replaceAll(',', ''));
    if (a != null && b != null && a == b) return 'AGREE';
  } else if (invoicePeriod) {
    final a = normalizeInvoicePeriodForComparison(left);
    final b = normalizeInvoicePeriodForComparison(right);
    if (a.isNotEmpty && a == b) return 'AGREE';
  } else if (left == right) {
    return 'AGREE';
  }
  return 'CONFLICT';
}

String _sameImageLabel(bool? value) => value == null
    ? 'N/A'
    : value
    ? 'YES'
    : 'NO';
