import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../account/account_repository.dart';
import '../capture/capture_help_button.dart';
import '../category/expense_category_repository.dart';
import '../category/expense_category_schema.dart';
import '../invoice/daily_capture_entry_shell.dart';
import '../invoice/flutter_image_picker_sources.dart';
import '../invoice/gemini/gemini_invoice_settings.dart';
import '../invoice/gemini/gemini_invoice_settings_repository.dart';
import '../invoice/image_capture_staging.dart';
import '../invoice/production_image_capture.dart';
import '../merchant/canonical_merchant_repository.dart';
import '../merchant/merchant_record.dart';
import '../recognition_ai/recognition_ai_status_indicator.dart';
import '../transaction/transaction_entry_page.dart';
import '../transaction/transaction_type.dart';
import 'gemini_product_recognition_client.dart';
import 'gemini_product_recognition_coordinator.dart';
import 'product_manual_review_card.dart';
import 'product_recognition_candidate.dart';
import 'product_transaction_handoff.dart';

class ProductCapturePage extends StatefulWidget {
  const ProductCapturePage({
    super.key,
    this.coordinator,
    this.recognitionCoordinator,
    this.categoryOptionsOverride,
    this.merchantOptionsOverride,
    this.accountOptionsOverride,
  });

  static const String routeName = 'product-capture';
  static const String routePath = '/product-capture';

  static const Key helpKey = Key('product_capture_help');
  static const Key cameraActionKey = Key('product_capture_camera_action');
  static const Key galleryActionKey = Key('product_capture_gallery_action');
  static const Key stagedItemKey = Key('product_capture_staged_item');
  static const Key discardActionKey = Key('product_capture_discard_action');
  static const Key aiRecognitionActionKey = Key('product_capture_ai_recognition_action');
  static const Key aiRunningStatusKey = Key('product_capture_ai_running_status');
  static const Key aiStatusKey = Key('product_capture_ai_status');
  static const Key candidateReviewKey = Key('product_capture_candidate_review');
  static const Key reviewedStatusKey = Key('product_capture_reviewed_status');
  static const Key transactionHandoffKey = Key('product_capture_transaction_handoff');

  final ProductionImageCaptureCoordinator? coordinator;
  final ProductRecognitionCoordinator? recognitionCoordinator;
  final List<String>? categoryOptionsOverride;
  final List<String>? merchantOptionsOverride;
  final List<String>? accountOptionsOverride;

  @override
  State<ProductCapturePage> createState() => _ProductCapturePageState();
}

class _ProductCapturePageState extends State<ProductCapturePage> {
  static const _defaultMerchants = <String>[
    '不使用商家',
    'OK便利商店',
    '7-ELEVEN',
    '全家便利商店',
    '麥當勞',
    '八方雲集',
  ];

  late final ProductionImageCaptureCoordinator _coordinator;
  late final ProductRecognitionCoordinator _recognitionCoordinator;
  ProductionImageCaptureResult? _result;
  ProductRecognitionExecution? _recognitionExecution;
  ProductTransactionDraftSeed? _reviewedDraft;
  String? _recognitionError;
  bool _busy = false;
  bool _recognitionBusy = false;
  bool _referenceDataBusy = false;
  List<String> _categoryOptions = canonicalDefaultExpenseCategories;
  List<String> _merchantOptions = _defaultMerchants;
  List<String> _accountOptions = const <String>[];
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
    _loadReferenceData();
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
                body: '總額可由數量×單價自動計算並允許人工覆寫；類別、商家與扣款帳戶引用正式資料。',
              ),
              CaptureHelpSection(
                title: '正式記帳',
                body: '確認人工覆核後只會帶入新增記帳頁；仍需由你在新增記帳頁按下儲存，才會建立正式交易。',
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
          if (_busy || _referenceDataBusy) ...[
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
                    Text(item.source == ImageCaptureStagingSource.camera ? '來源：相機' : '來源：相簿'),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            key: ProductCapturePage.aiRecognitionActionKey,
                            onPressed: _interactionBusy ? null : _runRecognition,
                            icon: const Icon(Icons.auto_awesome_outlined),
                            label: Text(execution?.candidate == null ? 'AI 辨識商品' : '重新 AI 辨識'),
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
                      RecognitionAiStatusIndicator(context: execution.sessionContext!)
                    else
                      Text('Gemini · ${execution.model}', style: const TextStyle(fontWeight: FontWeight.w700)),
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
            ProductManualReviewCard(
              key: ProductCapturePage.candidateReviewKey,
              candidate: execution!.candidate!,
              categoryOptions: _categoryOptions,
              merchantOptions: _merchantOptions,
              accountOptions: _accountOptions,
              onAddCategory: _addCategory,
              onAddMerchant: _addMerchant,
              onReviewed: _acceptReviewedDraft,
            ),
          ],
          if (!_recognitionBusy && _reviewedDraft != null) ...[
            const SizedBox(height: 12),
            const Card(
              key: ProductCapturePage.reviewedStatusKey,
              child: ListTile(
                leading: Icon(Icons.verified_outlined),
                title: Text('人工覆核已確認'),
                subtitle: Text('已形成可帶入新增記帳頁的草稿；目前仍未建立正式交易。'),
              ),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              key: ProductCapturePage.transactionHandoffKey,
              onPressed: _reviewedDraft!.isReadyForTransactionEntry
                  ? _openTransactionEntry
                  : null,
              icon: const Icon(Icons.edit_note_outlined),
              label: const Text('帶入新增記帳'),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _loadReferenceData() async {
    if (widget.categoryOptionsOverride != null ||
        widget.merchantOptionsOverride != null ||
        widget.accountOptionsOverride != null) {
      if (!mounted) return;
      setState(() {
        _categoryOptions = widget.categoryOptionsOverride ?? _categoryOptions;
        _merchantOptions = widget.merchantOptionsOverride ?? _merchantOptions;
        _accountOptions = widget.accountOptionsOverride ?? _accountOptions;
      });
      return;
    }
    setState(() => _referenceDataBusy = true);
    try {
      final categories = await ExpenseCategoryRepository.instance.listActive();
      final merchants = await CanonicalMerchantRepository.instance.listMerchants();
      final accounts = await AccountRepository.instance.listAccounts();
      if (!mounted) return;
      setState(() {
        _categoryOptions = _normalize([
          ...canonicalDefaultExpenseCategories,
          ...categories.map((item) => item.name),
        ]);
        _merchantOptions = _normalize([
          ..._defaultMerchants,
          ...merchants.map((item) => item.displayName),
        ]);
        _accountOptions = _normalize(accounts.map((item) => item.displayName));
      });
    } catch (_) {
      // Keep safe built-in category/merchant fallbacks. Account stays empty so
      // review cannot be confirmed against an unverified payment account.
    } finally {
      if (mounted) setState(() => _referenceDataBusy = false);
    }
  }

  Future<String?> _addCategory(String name) async {
    try {
      final record = await ExpenseCategoryRepository.instance.addUserCategory(name);
      final categories = await ExpenseCategoryRepository.instance.listActive();
      if (mounted) {
        setState(() {
          _categoryOptions = _normalize(categories.map((item) => item.name));
          _reviewedDraft = null;
        });
      }
      return record.name;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _addMerchant(String name) async {
    final normalized = name.trim();
    if (normalized.isEmpty) return null;
    try {
      final existing = await CanonicalMerchantRepository.instance.listMerchants();
      final matched = existing.where((item) => item.displayName == normalized).firstOrNull;
      if (matched != null) return matched.displayName;
      final now = DateTime.now();
      final record = MerchantRecord(
        id: const Uuid().v4(),
        name: normalized,
        createdAt: now,
        updatedAt: now,
      );
      await CanonicalMerchantRepository.instance.upsertMerchant(record);
      final merchants = await CanonicalMerchantRepository.instance.listMerchants();
      if (mounted) {
        setState(() {
          _merchantOptions = _normalize([
            ..._defaultMerchants,
            ...merchants.map((item) => item.displayName),
          ]);
          _reviewedDraft = null;
        });
      }
      return record.displayName;
    } catch (_) {
      return null;
    }
  }

  Future<void> _capture(ImageCaptureStagingSource source) async {
    _stopRecognitionProgress();
    setState(() {
      _busy = true;
      _result = null;
      _recognitionExecution = null;
      _reviewedDraft = null;
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
      _reviewedDraft = null;
      _recognitionError = null;
    });
    try {
      final execution = await _recognitionCoordinator.recognize(localReference: item.localReference);
      if (!mounted) return;
      setState(() {
        _recognitionExecution = execution;
        _recognitionActiveModel = execution.model;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _recognitionError = 'Gemini 商品辨識發生未分類錯誤；照片仍保留於本機。');
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
      _reviewedDraft = null;
      _recognitionError = null;
    });
  }

  void _acceptReviewedDraft(ProductTransactionDraftSeed reviewed) {
    setState(() => _reviewedDraft = reviewed);
  }

  void _openTransactionEntry() {
    final draft = _reviewedDraft;
    if (draft == null || !draft.isReadyForTransactionEntry) return;
    context.pushNamed(
      TransactionEntryPage.routeName,
      extra: TransactionEntrySeed(
        initialType: TransactionType.expense,
        accountName: draft.accountName,
        amount: draft.amount,
        category: draft.category,
        merchantName: draft.merchant,
        note: draft.note,
      ),
    );
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
      setState(() => _recognitionElapsed = DateTime.now().difference(started));
    });
  }

  void _stopRecognitionProgress() {
    _recognitionElapsedTimer?.cancel();
    _recognitionElapsedTimer = null;
    final started = _recognitionStartedAt;
    if (started != null) _recognitionElapsed = DateTime.now().difference(started);
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

  static List<String> _normalize(Iterable<String> values) {
    final result = <String>[];
    final seen = <String>{};
    for (final raw in values) {
      final value = raw.trim();
      if (value.isNotEmpty && seen.add(value)) result.add(value);
    }
    return List<String>.unmodifiable(result);
  }
}

class _ProgressReportingGeminiProductRecognitionClient implements GeminiProductRecognitionPort {
  const _ProgressReportingGeminiProductRecognitionClient({required this.delegate, required this.onAttempt});

  final GeminiProductRecognitionPort delegate;
  final ValueChanged<String> onAttempt;

  @override
  Future<ProductRecognitionCandidate> recognize({
    required String apiKey,
    required String model,
    required Uint8List imageBytes,
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
