import 'dart:async';

import 'package:flutter/material.dart';

import '../capture/capture_help_button.dart';
import '../invoice/daily_capture_entry_shell.dart';
import '../invoice/flutter_image_picker_sources.dart';
import '../invoice/gemini/gemini_invoice_settings.dart';
import '../invoice/gemini/gemini_invoice_settings_repository.dart';
import '../invoice/image_capture_staging.dart';
import '../invoice/production_image_capture.dart';
import '../recognition_ai/recognition_ai_status_indicator.dart';
import 'gemini_product_recognition_client.dart';
import 'gemini_product_recognition_coordinator.dart';
import 'product_recognition_candidate.dart';

class ProductCapturePage extends StatefulWidget {
  const ProductCapturePage({
    super.key,
    this.coordinator,
    this.recognitionCoordinator,
  });

  static const String routeName = 'product-capture';
  static const String routePath = '/product-capture';

  static const Key helpKey = Key('product_capture_help');
  static const Key cameraActionKey = Key('product_capture_camera_action');
  static const Key galleryActionKey = Key('product_capture_gallery_action');
  static const Key stagedItemKey = Key('product_capture_staged_item');
  static const Key discardActionKey = Key('product_capture_discard_action');
  static const Key aiRecognitionActionKey =
      Key('product_capture_ai_recognition_action');
  static const Key aiRunningStatusKey =
      Key('product_capture_ai_running_status');
  static const Key aiStatusKey = Key('product_capture_ai_status');
  static const Key candidateReviewKey = Key('product_capture_candidate_review');

  final ProductionImageCaptureCoordinator? coordinator;
  final ProductRecognitionCoordinator? recognitionCoordinator;

  @override
  State<ProductCapturePage> createState() => _ProductCapturePageState();
}

class _ProductCapturePageState extends State<ProductCapturePage> {
  late final ProductionImageCaptureCoordinator _coordinator;
  late final ProductRecognitionCoordinator _recognitionCoordinator;
  ProductionImageCaptureResult? _result;
  ProductRecognitionExecution? _recognitionExecution;
  String? _recognitionError;
  bool _busy = false;
  bool _recognitionBusy = false;
  Timer? _recognitionElapsedTimer;
  DateTime? _recognitionStartedAt;
  Duration _recognitionElapsed = Duration.zero;
  String _recognitionActiveModel = GeminiInvoiceSettings.defaultModel;
  String _recognitionProgressMessage = '正在確認可用 API Key 與模型…';
  int _recognitionPhysicalAttemptOrdinal = 0;

  bool get _interactionBusy => _busy || _recognitionBusy;

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

    if (widget.recognitionCoordinator != null) {
      _recognitionCoordinator = widget.recognitionCoordinator!;
    } else {
      const settingsRepository = GeminiInvoiceSettingsRepository();
      _recognitionCoordinator = ProductRecognitionCoordinator(
        settingsStore: settingsRepository,
        client: _ProgressReportingGeminiProductRecognitionClient(
          delegate: GeminiProductRecognitionClient(),
          onAttempt: _onRecognitionPhysicalAttempt,
        ),
      );
      settingsRepository.load().then((settings) {
        if (!mounted) return;
        setState(() => _recognitionActiveModel = settings.model);
      });
    }
  }

  @override
  void dispose() {
    _recognitionElapsedTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = _coordinator.currentItem;
    final execution = _recognitionExecution;
    return Scaffold(
      appBar: AppBar(
        title: const Text('拍商品'),
        actions: const [
          CaptureHelpButton(
            key: ProductCapturePage.helpKey,
            dialogTitle: '拍商品使用說明',
            sections: [
              CaptureHelpSection(
                title: '影像來源',
                body: '可直接開啟相機，或從相簿選擇既有照片。',
              ),
              CaptureHelpSection(
                title: 'AI 辨識',
                body: '照片只會先暫存在本機；必須由你明確按下 AI 辨識後，才會送往 Gemini。',
              ),
              CaptureHelpSection(
                title: '人工覆核',
                body: 'AI 只提供商品候選與分類、商家建議；所有欄位都必須由你覆核後才能進入正式記帳流程。',
              ),
              CaptureHelpSection(
                title: '照片管理',
                body: '選取後可查看檔名與來源；不使用時可立即丟棄照片。',
              ),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  key: ProductCapturePage.cameraActionKey,
                  onPressed: _interactionBusy
                      ? null
                      : () => _capture(ImageCaptureStagingSource.camera),
                  icon: const Icon(Icons.camera_alt_outlined),
                  label: const Text('開啟相機'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  key: ProductCapturePage.galleryActionKey,
                  onPressed: _interactionBusy
                      ? null
                      : () => _capture(ImageCaptureStagingSource.gallery),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('從相簿選擇'),
                ),
              ),
            ],
          ),
          if (_busy) ...[
            const SizedBox(height: 16),
            const LinearProgressIndicator(),
          ],
          if (_result != null && !_result!.hasStagedItem) ...[
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: Text(_result!.message),
            ),
          ],
          if (item != null) ...[
            const SizedBox(height: 16),
            Card(
              key: ProductCapturePage.stagedItemKey,
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
                    Text(
                      item.source == ImageCaptureStagingSource.camera
                          ? '來源：相機'
                          : '來源：相簿',
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            key: ProductCapturePage.aiRecognitionActionKey,
                            onPressed:
                                _interactionBusy ? null : _runRecognition,
                            icon: const Icon(Icons.auto_awesome_outlined),
                            label: Text(
                              execution?.candidate == null
                                  ? 'AI 辨識商品'
                                  : '重新 AI 辨識',
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        OutlinedButton.icon(
                          key: ProductCapturePage.discardActionKey,
                          onPressed: _interactionBusy ? null : _discard,
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('丟棄'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'AI 辨識是明確的使用者操作；選取照片本身不會自動送出影像。',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (_recognitionBusy) ...[
            const SizedBox(height: 16),
            Card(
              key: ProductCapturePage.aiRunningStatusKey,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: RecognitionAiRunningStatusIndicator(
                  provider: 'Gemini',
                  activeModel: _recognitionActiveModel,
                  elapsed: _recognitionElapsed,
                  message: _recognitionProgressMessage,
                ),
              ),
            ),
          ],
          if (!_recognitionBusy && execution != null) ...[
            const SizedBox(height: 16),
            Card(
              key: ProductCapturePage.aiStatusKey,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (execution.sessionContext != null)
                      RecognitionAiStatusIndicator(
                        context: execution.sessionContext!,
                      )
                    else
                      Text(
                        'Gemini · ${execution.model}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    const SizedBox(height: 8),
                    Text(execution.message),
                  ],
                ),
              ),
            ),
          ],
          if (!_recognitionBusy && _recognitionError != null) ...[
            const SizedBox(height: 16),
            Card(
              child: ListTile(
                leading: const Icon(Icons.error_outline),
                title: const Text('AI 辨識未完成'),
                subtitle: Text(_recognitionError!),
              ),
            ),
          ],
          if (!_recognitionBusy && execution?.candidate != null) ...[
            const SizedBox(height: 16),
            _ProductRecognitionCandidateCard(
              key: ProductCapturePage.candidateReviewKey,
              candidate: execution!.candidate!,
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _capture(ImageCaptureStagingSource source) async {
    _stopRecognitionProgress();
    setState(() {
      _busy = true;
      _result = null;
      _recognitionExecution = null;
      _recognitionError = null;
    });
    final result = source == ImageCaptureStagingSource.camera
        ? await _coordinator.captureFromCamera(intent: DailyCaptureIntent.product)
        : await _coordinator.captureFromGallery(intent: DailyCaptureIntent.product);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _result = result;
    });
  }

  Future<void> _runRecognition() async {
    final item = _coordinator.currentItem;
    if (item == null || _recognitionBusy) return;
    _startRecognitionProgress();
    setState(() {
      _recognitionBusy = true;
      _recognitionExecution = null;
      _recognitionError = null;
    });
    try {
      final execution = await _recognitionCoordinator.recognize(
        localReference: item.localReference,
      );
      if (!mounted) return;
      setState(() {
        _recognitionExecution = execution;
        _recognitionActiveModel = execution.model;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _recognitionError = 'Gemini 商品辨識發生未分類錯誤；照片仍保留於本機。';
      });
    } finally {
      _stopRecognitionProgress();
      if (mounted) setState(() => _recognitionBusy = false);
    }
  }

  Future<void> _discard() async {
    _stopRecognitionProgress();
    setState(() => _busy = true);
    final result = await _coordinator.discardCurrent();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _result = result;
      _recognitionExecution = null;
      _recognitionError = null;
    });
  }

  void _startRecognitionProgress() {
    _recognitionElapsedTimer?.cancel();
    _recognitionStartedAt = DateTime.now();
    _recognitionElapsed = Duration.zero;
    _recognitionPhysicalAttemptOrdinal = 0;
    _recognitionProgressMessage = '正在確認可用 API Key 與模型…';
    _recognitionElapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final started = _recognitionStartedAt;
      if (!mounted || started == null) return;
      setState(() {
        _recognitionElapsed = DateTime.now().difference(started);
      });
    });
  }

  void _stopRecognitionProgress() {
    _recognitionElapsedTimer?.cancel();
    _recognitionElapsedTimer = null;
    final started = _recognitionStartedAt;
    if (started != null) {
      _recognitionElapsed = DateTime.now().difference(started);
    }
    _recognitionStartedAt = null;
  }

  void _onRecognitionPhysicalAttempt(String model) {
    if (!mounted) return;
    setState(() {
      _recognitionPhysicalAttemptOrdinal += 1;
      _recognitionActiveModel = model;
      _recognitionProgressMessage = _recognitionPhysicalAttemptOrdinal == 1
          ? '正在辨識…'
          : '正在切換可用 Key／模型並重試…';
    });
  }
}

class _ProductRecognitionCandidateCard extends StatelessWidget {
  const _ProductRecognitionCandidateCard({
    super.key,
    required this.candidate,
  });

  final ProductRecognitionCandidate candidate;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.fact_check_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'AI 商品候選 · 請人工覆核',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _CandidateField(label: '商品', value: candidate.productName),
            _CandidateField(
              label: '數量',
              value: _displayNumber(candidate.quantity),
            ),
            _CandidateField(
              label: '單價',
              value: _displayNumber(candidate.unitPrice),
            ),
            _CandidateField(
              label: '總金額',
              value: _displayNumber(candidate.resolvedTotalAmount),
            ),
            _CandidateField(
              label: '分類建議',
              value: candidate.categorySuggestion,
            ),
            _CandidateField(
              label: '商家建議',
              value: candidate.merchantName,
            ),
            if (candidate.resolvedAmountSource ==
                ProductRecognitionAmountSource.derivedQuantityTimesUnitPrice)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '總金額為數量 × 單價推導值，需由你確認。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            if (candidate.warnings.isNotEmpty) ...[
              const Divider(height: 24),
              Text(
                '需注意：${candidate.warnings.join('、')}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const Divider(height: 24),
            Text(
              '目前只建立覆核候選，不會自動新增分類、商家或正式交易。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  static String _displayNumber(double? value) {
    if (value == null) return '—';
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value
        .toStringAsFixed(4)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }
}

class _CandidateField extends StatelessWidget {
  const _CandidateField({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 86,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(child: Text(value.trim().isEmpty ? '—' : value.trim())),
        ],
      ),
    );
  }
}

class _ProgressReportingGeminiProductRecognitionClient
    implements GeminiProductRecognitionPort {
  const _ProgressReportingGeminiProductRecognitionClient({
    required this.delegate,
    required this.onAttempt,
  });

  final GeminiProductRecognitionPort delegate;
  final ValueChanged<String> onAttempt;

  @override
  Future<ProductRecognitionCandidate> recognize({
    required String apiKey,
    required String model,
    required dynamic imageBytes,
    required String mimeType,
  }) {
    onAttempt(model);
    return delegate.recognize(
      apiKey: apiKey,
      model: model,
      imageBytes: imageBytes,
      mimeType: mimeType,
    );
  }
}
