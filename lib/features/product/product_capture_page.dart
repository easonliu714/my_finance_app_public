import 'package:flutter/material.dart';

import '../capture/capture_help_button.dart';
import '../invoice/daily_capture_entry_shell.dart';
import '../invoice/flutter_image_picker_sources.dart';
import '../invoice/image_capture_staging.dart';
import '../invoice/production_image_capture.dart';

class ProductCapturePage extends StatefulWidget {
  const ProductCapturePage({
    super.key,
    this.coordinator,
  });

  static const String routeName = 'product-capture';
  static const String routePath = '/product-capture';

  static const Key helpKey = Key('product_capture_help');
  static const Key cameraActionKey = Key('product_capture_camera_action');
  static const Key galleryActionKey = Key('product_capture_gallery_action');
  static const Key stagedItemKey = Key('product_capture_staged_item');
  static const Key discardActionKey = Key('product_capture_discard_action');

  final ProductionImageCaptureCoordinator? coordinator;

  @override
  State<ProductCapturePage> createState() => _ProductCapturePageState();
}

class _ProductCapturePageState extends State<ProductCapturePage> {
  late final ProductionImageCaptureCoordinator _coordinator;
  ProductionImageCaptureResult? _result;
  bool _busy = false;

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
  }

  @override
  Widget build(BuildContext context) {
    final item = _coordinator.currentItem;
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
                  onPressed: _busy
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
                  onPressed: _busy
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
                    OutlinedButton.icon(
                      key: ProductCapturePage.discardActionKey,
                      onPressed: _busy ? null : _discard,
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('丟棄照片'),
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

  Future<void> _capture(ImageCaptureStagingSource source) async {
    setState(() {
      _busy = true;
      _result = null;
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

  Future<void> _discard() async {
    setState(() => _busy = true);
    final result = await _coordinator.discardCurrent();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _result = result;
    });
  }
}
