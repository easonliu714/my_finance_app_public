import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;

import 'invoice_frozen_review_page.dart';
import 'invoice_live_capture_page.dart';

class InvoiceImageImportPage extends StatefulWidget {
  const InvoiceImageImportPage({super.key});

  static const String routeName = 'invoice-image-import';
  static const String routePath = '/invoice-capture/image';
  static const Key chooseImageKey = Key('invoice_image_import_choose');

  @override
  State<InvoiceImageImportPage> createState() => _InvoiceImageImportPageState();
}

class _InvoiceImageImportPageState extends State<InvoiceImageImportPage> {
  final ImagePicker _picker = ImagePicker();
  bool _busy = false;
  String? _error;

  Future<void> _chooseImage() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // Preserve the selected source bytes. Do not resize/re-encode here so
      // Local and Gemini receive the same image provenance.
      final image = await _picker.pickImage(source: ImageSource.gallery);
      if (!mounted || image == null) return;
      final result = InvoiceLiveCaptureResult(
        localReference: image.path,
        fileName: image.name.isNotEmpty ? image.name : path.basename(image.path),
        classification: InvoiceLiveClassification.searching,
        autoFrozen: false,
        liveSnapshot: const InvoiceLiveSnapshot(
          message: '從圖片讀取；凍結後先執行 Local QR/OCR，再依完整度與信心度決定是否自動 Gemini 覆核。',
        ),
        origin: InvoiceCaptureOrigin.gallery,
      );
      await context.pushNamed(
        InvoiceFrozenReviewPage.routeName,
        extra: result,
      );
    } catch (error) {
      if (mounted) {
        setState(() => _error = '讀取圖片失敗：${error.runtimeType}');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('從圖片讀取發票')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
        children: <Widget>[
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                '選擇手機已有的發票影像後，系統先在本機執行 QR/OCR。只有缺少必要欄位、有警告或信心度不足時才自動啟動 Gemini；結果頁仍保留「強制 Gemini 二次覆核」。',
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            key: InvoiceImageImportPage.chooseImageKey,
            onPressed: _busy ? null : _chooseImage,
            icon: const Icon(Icons.photo_library_outlined),
            label: Text(_busy ? '讀取中…' : '選擇發票圖片'),
          ),
          if (_busy) ...<Widget>[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
          ],
          if (_error != null) ...<Widget>[
            const SizedBox(height: 12),
            Card(child: ListTile(title: Text(_error!))),
          ],
          const SizedBox(height: 20),
          const Text(
            '圖片只在使用者明確啟用 Gemini 覆核時送往 Google Gemini API；不會自動建立正式交易。',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
