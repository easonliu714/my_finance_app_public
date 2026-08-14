import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../capture/capture_help_button.dart';
import 'daily_capture_entry_shell.dart';
import 'flutter_image_picker_sources.dart';
import 'gemini/gemini_invoice_review.dart';
import 'gemini/gemini_invoice_review_client.dart';
import 'gemini/gemini_invoice_review_coordinator.dart';
import 'gemini/gemini_invoice_settings_repository.dart';
import 'gemini/gemini_invoice_validation_page.dart';
import 'google_mlkit_traditional_invoice_recognizer.dart';
import 'image_capture_staging.dart';
import 'invoice_automatic_recognition_coordinator.dart';
import 'invoice_capture_review_flow.dart';
import 'invoice_local_recognition_coordinator.dart';
import 'invoice_review_form_card.dart';
import 'invoice_review_form_view_model.dart';
import 'invoice_review_submission_gate.dart';
import 'manual_invoice_entry_page.dart';
import 'mobile_scanner_invoice_qr_decoder.dart';
import 'production_image_capture.dart';
import 'traditional_invoice_ocr_review.dart';

enum InvoiceRecognitionMode {
  automatic,
  traditionalOcr,
  qrPair,
  manual,
}

extension InvoiceRecognitionModeMetadata on InvoiceRecognitionMode {
  String get label {
    switch (this) {
      case InvoiceRecognitionMode.automatic:
        return '自動辨識';
      case InvoiceRecognitionMode.traditionalOcr:
        return '傳統發票 OCR';
      case InvoiceRecognitionMode.qrPair:
        return '二維碼發票';
      case InvoiceRecognitionMode.manual:
        return '手動輸入';
    }
  }

  IconData get icon {
    switch (this) {
      case InvoiceRecognitionMode.automatic:
        return Icons.auto_awesome_outlined;
      case InvoiceRecognitionMode.traditionalOcr:
        return Icons.text_snippet_outlined;
      case InvoiceRecognitionMode.qrPair:
        return Icons.qr_code_2_outlined;
      case InvoiceRecognitionMode.manual:
        return Icons.edit_note_outlined;
    }
  }

  bool get usesImage => this != InvoiceRecognitionMode.manual;

  InvoiceRecognitionRequestedRoute get requestedRoute {
    switch (this) {
      case InvoiceRecognitionMode.automatic:
        return InvoiceRecognitionRequestedRoute.automatic;
      case InvoiceRecognitionMode.traditionalOcr:
        return InvoiceRecognitionRequestedRoute.traditionalInvoiceOcr;
      case InvoiceRecognitionMode.qrPair:
        return InvoiceRecognitionRequestedRoute.electronicInvoiceQr;
      case InvoiceRecognitionMode.manual:
        return InvoiceRecognitionRequestedRoute.automatic;
    }
  }
}

class InvoiceCapturePage extends StatefulWidget {
  const InvoiceCapturePage({
    super.key,
    this.coordinator,
    this.reviewFlowCoordinator,
    this.geminiReviewCoordinator,
  });

  static const String routeName = 'invoice-capture';
  static const String routePath = '/invoice-capture';

  static const Key helpKey = Key('invoice_capture_help');
  static const Key automaticModeKey = Key('invoice_capture_mode_automatic');
  static const Key traditionalOcrModeKey =
      Key('invoice_capture_mode_traditional_ocr');
  static const Key qrPairModeKey = Key('invoice_capture_mode_qr_pair');
  static const Key manualModeKey = Key('invoice_capture_mode_manual');
  static const Key independentGeminiActionKey =
      Key('invoice_capture_independent_gemini_action');
  static const Key manualEntryActionKey =
      Key('invoice_capture_manual_entry_action');
  static const Key cameraActionKey = Key('invoice_capture_camera_action');
  static const Key galleryActionKey = Key('invoice_capture_gallery_action');
  static const Key stagedItemKey = Key('invoice_capture_staged_item');
  static const Key discardActionKey = Key('invoice_capture_discard_action');
  static const Key recognizeActionKey = Key('invoice_capture_recognize_action');
  static const Key recognitionStatusKey =
      Key('invoice_capture_recognition_status');
  static const Key reviewCardKey = Key('invoice_capture_review_card');
  static const Key geminiReviewActionKey =
      Key('invoice_capture_gemini_review_action');
  static const Key geminiReviewStatusKey =
      Key('invoice_capture_gemini_review_status');
  static const Key geminiComparisonKey =
      Key('invoice_capture_gemini_comparison');
  static const Key reviewCompleteMessageKey =
      Key('invoice_capture_review_complete_message');
  static const Key statusMessageKey = Key('invoice_capture_status_message');
  static const Key disclaimerKey = Key('invoice_capture_disclaimer');

  final ProductionImageCaptureCoordinator? coordinator;
  final InvoiceCaptureReviewFlowCoordinator? reviewFlowCoordinator;
  final GeminiInvoiceReviewCoordinator? geminiReviewCoordinator;

  @override
  State<InvoiceCapturePage> createState() => _InvoiceCapturePageState();
}

class _InvoiceCapturePageState extends State<InvoiceCapturePage> {
  late final ProductionImageCaptureCoordinator _coordinator;
  late final InvoiceCaptureReviewFlowCoordinator _reviewFlowCoordinator;
  late final GeminiInvoiceReviewCoordinator _geminiReviewCoordinator;
  InvoiceRecognitionMode _mode = InvoiceRecognitionMode.automatic;
  ProductionImageCaptureResult? _result;
  InvoiceCaptureReviewFlowResult? _reviewFlowResult;
  GeminiInvoiceReviewExecution? _geminiReviewExecution;
  String? _reviewCompletionMessage;
  bool _busy = false;
  bool _geminiReviewBusy = false;

  @override
  void initState() {
    super.initState();
    _coordinator = widget.coordinator ??
        ProductionImageCaptureCoordinator(
          stagingService: ImageCaptureStagingService(
            gallerySource: FlutterGalleryImageSource(),
            cameraSource: FlutterCameraImageSource(),
          ),
        );
    _reviewFlowCoordinator = widget.reviewFlowCoordinator ??
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
    _geminiReviewCoordinator = widget.geminiReviewCoordinator ??
        GeminiInvoiceReviewCoordinator(
          settingsStore: const GeminiInvoiceSettingsRepository(),
          client: GeminiInvoiceReviewClient(),
        );
  }

  @override
  Widget build(BuildContext context) {
    final item = _coordinator.currentItem;
    final reviewFlowResult = _reviewFlowResult;
    final geminiExecution = _geminiReviewExecution;
    return Scaffold(
      appBar: AppBar(
        title: const Text('發票辨識'),
        actions: const [
          CaptureHelpButton(
            key: InvoiceCapturePage.helpKey,
            dialogTitle: '發票辨識使用說明',
            sections: [
              CaptureHelpSection(
                title: '自動辨識',
                body: '由 App 判斷影像較適合傳統發票文字辨識或二維碼辨識。',
              ),
              CaptureHelpSection(
                title: '傳統發票 OCR',
                body: '適用沒有電子發票 QR Code 的紙本發票，辨識後仍需人工核對。',
              ),
              CaptureHelpSection(
                title: '二維碼發票',
                body: '電子發票通常有左右兩個 QR Code；後續可自動配對，也可手動指定左碼與右碼。',
              ),
              CaptureHelpSection(
                title: 'Gemini 獨立覆核',
                body: '啟用實驗功能後，弱本機候選可送交 Gemini 產生第二份候選。AI 結果不會覆寫本機結果，也不會自動建立交易。',
              ),
              CaptureHelpSection(
                title: '手動輸入',
                body: '無法清楚辨識時，可直接開啟人工發票輸入頁。',
              ),
              CaptureHelpSection(
                title: '資料用途',
                body: '發票資料只用於記帳與對獎，不是可向通路或財政部兌獎的憑證。',
              ),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _ModeChip(
                key: InvoiceCapturePage.automaticModeKey,
                mode: InvoiceRecognitionMode.automatic,
                selected: _mode == InvoiceRecognitionMode.automatic,
                onSelected: _selectMode,
              ),
              _ModeChip(
                key: InvoiceCapturePage.traditionalOcrModeKey,
                mode: InvoiceRecognitionMode.traditionalOcr,
                selected: _mode == InvoiceRecognitionMode.traditionalOcr,
                onSelected: _selectMode,
              ),
              _ModeChip(
                key: InvoiceCapturePage.qrPairModeKey,
                mode: InvoiceRecognitionMode.qrPair,
                selected: _mode == InvoiceRecognitionMode.qrPair,
                onSelected: _selectMode,
              ),
              _ModeChip(
                key: InvoiceCapturePage.manualModeKey,
                mode: InvoiceRecognitionMode.manual,
                selected: _mode == InvoiceRecognitionMode.manual,
                onSelected: _selectMode,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              key: InvoiceCapturePage.independentGeminiActionKey,
              onPressed: _busy || _geminiReviewBusy
                  ? null
                  : () => context.pushNamed(
                        GeminiInvoiceValidationPage.routeName,
                      ),
              icon: const Icon(Icons.auto_awesome_outlined),
              label: const Text('Gemini 獨立覆核'),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Gemini 是第二意見：影像會傳送至 Google Gemini API；結果與本機辨識分開保存於目前覆核畫面，不會自動寫入正式交易。',
          ),
          const SizedBox(height: 20),
          if (_mode.usesImage)
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    key: InvoiceCapturePage.cameraActionKey,
                    onPressed: _busy || _geminiReviewBusy
                        ? null
                        : () => _capture(ImageCaptureStagingSource.camera),
                    icon: const Icon(Icons.camera_alt_outlined),
                    label: const Text('開啟相機'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    key: InvoiceCapturePage.galleryActionKey,
                    onPressed: _busy || _geminiReviewBusy
                        ? null
                        : () => _capture(ImageCaptureStagingSource.gallery),
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('從相簿選擇'),
                  ),
                ),
              ],
            )
          else
            FilledButton.icon(
              key: InvoiceCapturePage.manualEntryActionKey,
              onPressed: () =>
                  context.pushNamed(ManualInvoiceEntryPage.routeName),
              icon: const Icon(Icons.edit_note_outlined),
              label: const Text('開啟手動輸入'),
            ),
          if (_busy || _geminiReviewBusy) ...[
            const SizedBox(height: 16),
            LinearProgressIndicator(
              semanticsLabel:
                  _geminiReviewBusy ? 'Gemini 覆核中' : '本機發票辨識中',
            ),
          ],
          if (_result != null && !_result!.hasStagedItem) ...[
            const SizedBox(height: 16),
            ListTile(
              key: InvoiceCapturePage.statusMessageKey,
              leading: const Icon(Icons.info_outline),
              title: Text(_result!.message),
            ),
          ],
          if (item != null) ...[
            const SizedBox(height: 16),
            Card(
              key: InvoiceCapturePage.stagedItemKey,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.fileName,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text('辨識方式：${_mode.label}'),
                    Text(
                      item.source == ImageCaptureStagingSource.camera
                          ? '來源：相機'
                          : '來源：相簿',
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          key: InvoiceCapturePage.recognizeActionKey,
                          onPressed: _busy || _geminiReviewBusy
                              ? null
                              : _recognizeCurrent,
                          icon: const Icon(Icons.document_scanner_outlined),
                          label: const Text('開始本機辨識'),
                        ),
                        OutlinedButton.icon(
                          key: InvoiceCapturePage.discardActionKey,
                          onPressed:
                              _busy || _geminiReviewBusy ? null : _discard,
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('丟棄影像'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (reviewFlowResult != null) ...[
            const SizedBox(height: 16),
            ListTile(
              key: InvoiceCapturePage.recognitionStatusKey,
              leading: Icon(
                reviewFlowResult.canOpenReview
                    ? Icons.fact_check_outlined
                    : Icons.info_outline,
              ),
              title: Text(reviewFlowResult.recognitionResult.message),
              subtitle: Text(
                reviewFlowResult.recognitionResult.selectedRouteReason,
              ),
            ),
            KeyedSubtree(
              key: InvoiceCapturePage.reviewCardKey,
              child: InvoiceReviewFormCard(
                initialModel: reviewFlowResult.formModel,
                onContinue: _completeReview,
              ),
            ),
            const SizedBox(height: 12),
            _GeminiReviewControlCard(
              execution: geminiExecution,
              busy: _geminiReviewBusy,
              recommended: const GeminiInvoiceEscalationPolicy()
                  .evaluate(reviewFlowResult.recognitionResult)
                  .shouldReview,
              onReview: item == null || _busy || _geminiReviewBusy
                  ? null
                  : () => _runGeminiReview(
                        reviewFlowResult,
                        forceReview: true,
                      ),
            ),
          ],
          if (geminiExecution != null) ...[
            const SizedBox(height: 12),
            ListTile(
              key: InvoiceCapturePage.geminiReviewStatusKey,
              leading: Icon(
                geminiExecution.status == GeminiInvoiceReviewExecutionStatus.success
                    ? Icons.auto_awesome_outlined
                    : Icons.info_outline,
              ),
              title: Text(geminiExecution.message),
              subtitle: Text('模型：${geminiExecution.model} · ${geminiExecution.decision.reason}'),
            ),
            if (geminiExecution.candidate != null && reviewFlowResult != null)
              _GeminiComparisonCard(
                key: InvoiceCapturePage.geminiComparisonKey,
                localModel: reviewFlowResult.formModel,
                aiCandidate: geminiExecution.candidate!,
              ),
          ],
          if (_reviewCompletionMessage != null) ...[
            const SizedBox(height: 12),
            ListTile(
              key: InvoiceCapturePage.reviewCompleteMessageKey,
              leading: const Icon(Icons.check_circle_outline),
              title: Text(_reviewCompletionMessage!),
            ),
          ],
          const SizedBox(height: 20),
          const Text(
            '發票紀錄僅供記帳與對獎，不能作為兌獎憑證。',
            key: InvoiceCapturePage.disclaimerKey,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  void _selectMode(InvoiceRecognitionMode mode) {
    if (_busy || _geminiReviewBusy || mode == _mode) return;
    setState(() {
      _mode = mode;
      _result = null;
      _reviewFlowResult = null;
      _geminiReviewExecution = null;
      _reviewCompletionMessage = null;
    });
  }

  Future<void> _capture(ImageCaptureStagingSource source) async {
    setState(() {
      _busy = true;
      _result = null;
      _reviewFlowResult = null;
      _geminiReviewExecution = null;
      _reviewCompletionMessage = null;
    });
    final result = source == ImageCaptureStagingSource.camera
        ? await _coordinator.captureFromCamera(intent: DailyCaptureIntent.invoice)
        : await _coordinator.captureFromGallery(intent: DailyCaptureIntent.invoice);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _result = result;
    });
  }

  Future<void> _recognizeCurrent() async {
    final item = _coordinator.currentItem;
    if (item == null || !_mode.usesImage) return;
    setState(() {
      _busy = true;
      _reviewFlowResult = null;
      _geminiReviewExecution = null;
      _reviewCompletionMessage = null;
    });
    final result = await _reviewFlowCoordinator.recognize(
      image: item,
      requestedRoute: _mode.requestedRoute,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _reviewFlowResult = result;
    });

    // Conservative automatic escalation: the coordinator itself checks the
    // secure feature flag and skips complete structured QR/local candidates.
    await _runGeminiReview(result, forceReview: false);
  }

  Future<void> _runGeminiReview(
    InvoiceCaptureReviewFlowResult localResult, {
    required bool forceReview,
  }) async {
    final item = _coordinator.currentItem;
    if (item == null || _geminiReviewBusy) return;
    setState(() {
      _geminiReviewBusy = true;
      if (forceReview) _geminiReviewExecution = null;
    });
    try {
      final execution = await _geminiReviewCoordinator.review(
        localResult: localResult.recognitionResult,
        localReference: item.localReference,
        forceReview: forceReview,
      );
      if (!mounted) return;
      setState(() => _geminiReviewExecution = execution);
    } finally {
      if (mounted) setState(() => _geminiReviewBusy = false);
    }
  }

  void _completeReview(InvoiceReviewFormViewModel model) {
    if (!model.canSubmitReviewSafely) return;
    setState(() {
      _reviewCompletionMessage =
          '覆核資料已確認；目前尚未建立正式發票或交易紀錄。';
    });
  }

  Future<void> _discard() async {
    setState(() => _busy = true);
    final result = await _coordinator.discardCurrent();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _result = result;
      _reviewFlowResult = null;
      _geminiReviewExecution = null;
      _reviewCompletionMessage = null;
    });
  }
}

class _GeminiReviewControlCard extends StatelessWidget {
  const _GeminiReviewControlCard({
    required this.execution,
    required this.busy,
    required this.recommended,
    required this.onReview,
  });

  final GeminiInvoiceReviewExecution? execution;
  final bool busy;
  final bool recommended;
  final VoidCallback? onReview;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Gemini 第二意見',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              recommended
                  ? '本機候選仍有缺欄位、警告或弱可信度，建議使用 Gemini 獨立覆核。'
                  : '本機候選已達保守門檻；預設不需要 AI，但仍可人工要求 Gemini 二次覆核。',
            ),
            if (execution != null) ...[
              const SizedBox(height: 8),
              Text('目前狀態：${execution!.message}'),
            ],
            const SizedBox(height: 10),
            FilledButton.tonalIcon(
              key: InvoiceCapturePage.geminiReviewActionKey,
              onPressed: onReview,
              icon: busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_awesome_outlined),
              label: Text(busy ? 'Gemini 覆核中…' : 'Gemini 二次覆核'),
            ),
            const SizedBox(height: 8),
            const Text(
              'AI 候選只供欄位比較；不會覆寫本機欄位、不會自動勾選覆核確認，也不會建立正式交易。',
            ),
          ],
        ),
      ),
    );
  }
}

class _GeminiComparisonCard extends StatelessWidget {
  const _GeminiComparisonCard({
    super.key,
    required this.localModel,
    required this.aiCandidate,
  });

  final InvoiceReviewFormViewModel localModel;
  final GeminiInvoiceReviewCandidate aiCandidate;

  @override
  Widget build(BuildContext context) {
    final localSeller = _localField(InvoiceReviewFieldKey.sellerName);
    final sellerTaxIdMatch = RegExp(r'\b(\d{8})\b').firstMatch(localSeller);
    final localSellerTaxId = sellerTaxIdMatch?.group(1) ?? '';
    final localMerchant = localSeller.startsWith('賣方統編') ? '' : localSeller;
    final rows = <_ComparisonRowData>[
      _ComparisonRowData(
        label: '發票號碼',
        localValue: _localField(InvoiceReviewFieldKey.invoiceNumber),
        aiValue: aiCandidate.invoiceNumber,
      ),
      _ComparisonRowData(
        label: '發票日期',
        localValue: _localField(InvoiceReviewFieldKey.invoiceDate),
        aiValue: aiCandidate.invoiceDate,
      ),
      _ComparisonRowData(
        label: '商家',
        localValue: localMerchant,
        aiValue: aiCandidate.merchantName,
      ),
      _ComparisonRowData(
        label: '賣方統編',
        localValue: localSellerTaxId,
        aiValue: aiCandidate.sellerTaxId,
      ),
      _ComparisonRowData(
        label: '總金額',
        localValue: _localField(InvoiceReviewFieldKey.totalAmount),
        aiValue: _formatAmount(aiCandidate.totalAmount),
        numeric: true,
      ),
      _ComparisonRowData(
        label: '發票期別',
        localValue: '',
        aiValue: aiCandidate.invoicePeriod,
      ),
      _ComparisonRowData(
        label: '交易時間',
        localValue: '',
        aiValue: aiCandidate.invoiceTime,
      ),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '本機 ↔ Gemini 欄位比較',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            const Text('此表只比較兩份候選，不會自動融合或回填任何欄位。'),
            const SizedBox(height: 12),
            for (final row in rows) ...[
              _ComparisonRow(data: row),
              const Divider(height: 18),
            ],
            if (aiCandidate.warnings.isNotEmpty) ...[
              Text(
                'Gemini 警告',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              for (final warning in aiCandidate.warnings) Text('• $warning'),
            ],
          ],
        ),
      ),
    );
  }

  String _localField(InvoiceReviewFieldKey key) =>
      localModel.fieldFor(key)?.value.trim() ?? '';

  String _formatAmount(double? value) {
    if (value == null) return '';
    return value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toString();
  }
}

class _ComparisonRowData {
  const _ComparisonRowData({
    required this.label,
    required this.localValue,
    required this.aiValue,
    this.numeric = false,
  });

  final String label;
  final String localValue;
  final String aiValue;
  final bool numeric;

  _ComparisonStatus get status {
    final local = localValue.trim();
    final ai = aiValue.trim();
    if (local.isEmpty && ai.isEmpty) return _ComparisonStatus.bothMissing;
    if (local.isEmpty) return _ComparisonStatus.missingLocal;
    if (ai.isEmpty) return _ComparisonStatus.missingAi;
    if (numeric) {
      final localNumber = double.tryParse(local.replaceAll(',', ''));
      final aiNumber = double.tryParse(ai.replaceAll(',', ''));
      if (localNumber != null && aiNumber != null && localNumber == aiNumber) {
        return _ComparisonStatus.agree;
      }
    } else if (local == ai) {
      return _ComparisonStatus.agree;
    }
    return _ComparisonStatus.conflict;
  }
}

enum _ComparisonStatus {
  agree,
  conflict,
  missingLocal,
  missingAi,
  bothMissing,
}

extension on _ComparisonStatus {
  String get label {
    switch (this) {
      case _ComparisonStatus.agree:
        return 'AGREE';
      case _ComparisonStatus.conflict:
        return 'CONFLICT';
      case _ComparisonStatus.missingLocal:
        return 'MISSING_LOCAL';
      case _ComparisonStatus.missingAi:
        return 'MISSING_AI';
      case _ComparisonStatus.bothMissing:
        return 'BOTH_MISSING';
    }
  }
}

class _ComparisonRow extends StatelessWidget {
  const _ComparisonRow({required this.data});

  final _ComparisonRowData data;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                data.label,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            Chip(label: Text(data.status.label)),
          ],
        ),
        const SizedBox(height: 4),
        Text('本機：${data.localValue.trim().isEmpty ? '—' : data.localValue}'),
        Text('Gemini：${data.aiValue.trim().isEmpty ? '—' : data.aiValue}'),
      ],
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({
    super.key,
    required this.mode,
    required this.selected,
    required this.onSelected,
  });

  final InvoiceRecognitionMode mode;
  final bool selected;
  final ValueChanged<InvoiceRecognitionMode> onSelected;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      avatar: Icon(mode.icon, size: 18),
      label: Text(mode.label),
      selected: selected,
      onSelected: (_) => onSelected(mode),
    );
  }
}
