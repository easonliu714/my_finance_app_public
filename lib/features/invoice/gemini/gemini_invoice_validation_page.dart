import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../invoice_automatic_recognition_coordinator.dart';
import 'gemini_invoice_review_client.dart';
import 'gemini_invoice_review_coordinator.dart';
import 'gemini_invoice_settings_repository.dart';

class GeminiInvoiceValidationPage extends StatefulWidget {
  const GeminiInvoiceValidationPage({
    super.key,
    this.imagePicker,
    this.coordinator,
  });

  static const String routeName = 'gemini-invoice-validation';
  static const String routePath = '/my/gemini-invoice-validation';
  static const Key pickImageKey = Key('gemini_validation_pick_image');
  static const Key runReviewKey = Key('gemini_validation_run_review');

  final ImagePicker? imagePicker;
  final GeminiInvoiceReviewCoordinator? coordinator;

  @override
  State<GeminiInvoiceValidationPage> createState() =>
      _GeminiInvoiceValidationPageState();
}

class _GeminiInvoiceValidationPageState
    extends State<GeminiInvoiceValidationPage> {
  late final ImagePicker _picker;
  late final GeminiInvoiceReviewCoordinator _coordinator;
  XFile? _image;
  GeminiInvoiceReviewExecution? _execution;
  var _busy = false;

  @override
  void initState() {
    super.initState();
    _picker = widget.imagePicker ?? ImagePicker();
    _coordinator = widget.coordinator ??
        GeminiInvoiceReviewCoordinator(
          settingsStore: const GeminiInvoiceSettingsRepository(),
          client: GeminiInvoiceReviewClient(),
        );
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    final execution = _execution;
    return Scaffold(
      appBar: AppBar(title: const Text('Gemini 發票獨立驗證')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    '獨立 AI 驗證',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '此頁只測試 Gemini 影像覆核，不會覆寫本機 OCR、建立發票草稿或寫入正式交易。影像會傳送至 Google Gemini API。',
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'P4.16.5 起不再對選取影像做隱性 resize 或 JPEG quality 重編碼；Gemini 直接讀取目前選取檔案的 bytes，便於與 Evidence SHA-256 做等價比較。',
                  ),
                  const SizedBox(height: 16),
                  if (image == null)
                    const AspectRatio(
                      aspectRatio: 4 / 3,
                      child: DecoratedBox(
                        decoration: BoxDecoration(color: Color(0x11000000)),
                        child: Center(child: Text('尚未選擇發票影像')),
                      ),
                    )
                  else
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.file(
                        File(image.path),
                        height: 280,
                        fit: BoxFit.contain,
                      ),
                    ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    key: GeminiInvoiceValidationPage.pickImageKey,
                    onPressed: _busy ? null : _pickImage,
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('選擇發票照片'),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    key: GeminiInvoiceValidationPage.runReviewKey,
                    onPressed: _busy || image == null ? null : _runReview,
                    icon: _busy
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.auto_awesome_outlined),
                    label: Text(_busy ? 'Gemini 覆核中…' : '執行獨立 Gemini 覆核'),
                  ),
                ],
              ),
            ),
          ),
          if (execution != null) ...<Widget>[
            const SizedBox(height: 12),
            _ExecutionCard(execution: execution),
          ],
        ],
      ),
    );
  }

  Future<void> _pickImage() async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      requestFullMetadata: false,
    );
    if (!mounted || picked == null) return;
    setState(() {
      _image = picked;
      _execution = null;
    });
  }

  Future<void> _runReview() async {
    final image = _image;
    if (image == null) return;
    setState(() {
      _busy = true;
      _execution = null;
    });
    try {
      final execution = await _coordinator.review(
        localResult: const InvoiceAutomaticRecognitionResult(
          status: InvoiceAutomaticRecognitionStatus.recognitionFailed,
          message: '獨立驗證頁未執行本機辨識。',
          selectedRouteReason: '使用者要求獨立 Gemini 覆核。',
          requestedRoute: InvoiceRecognitionRequestedRoute.automatic,
        ),
        localReference: image.path,
        forceReview: true,
      );
      if (!mounted) return;
      setState(() => _execution = execution);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _ExecutionCard extends StatelessWidget {
  const _ExecutionCard({required this.execution});

  final GeminiInvoiceReviewExecution execution;

  @override
  Widget build(BuildContext context) {
    final candidate = execution.candidate;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              execution.status == GeminiInvoiceReviewExecutionStatus.success
                  ? 'Gemini 覆核結果'
                  : 'Gemini 覆核狀態',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(execution.message),
            Text('模型：${execution.model}'),
            Text('Key 嘗試次數：${execution.attempts.length}'),
            if (execution.attempts.isNotEmpty) ...<Widget>[
              const Divider(height: 24),
              Text(
                'Key 覆核嘗試',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 6),
              for (final attempt in execution.attempts)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    'Key #${attempt.ordinal} ${attempt.maskedKey}：'
                    '${attempt.success ? '成功' : attempt.message}',
                  ),
                ),
              const Text(
                '診斷只顯示遮罩 Key 與安全錯誤分類，不顯示完整 API Key 或發票原始內容。',
              ),
            ],
            if (candidate != null) ...<Widget>[
              const Divider(height: 24),
              _field('發票號碼', candidate.invoiceNumber),
              _field('期別', candidate.invoicePeriod),
              _field('賣方統編', candidate.sellerTaxId),
              _field('日期', candidate.invoiceDate),
              _field('時間', candidate.invoiceTime),
              _field('商家', candidate.merchantName),
              _field(
                '總金額',
                candidate.totalAmount?.toStringAsFixed(0) ?? '',
              ),
              _field('品項數', candidate.lineItems.length.toString()),
              if (candidate.warnings.isNotEmpty) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  '警告',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                for (final warning in candidate.warnings)
                  Text('• $warning'),
              ],
              const SizedBox(height: 12),
              const Text(
                '此結果僅供比較與驗證，尚未載入本機候選，也不能建立正式交易。',
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _field(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(width: 88, child: Text(label)),
          Expanded(child: Text(value.isEmpty ? '—' : value)),
        ],
      ),
    );
  }
}
