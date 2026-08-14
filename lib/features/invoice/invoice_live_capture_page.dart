import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart'
    as barcode;
import 'package:google_mlkit_commons/google_mlkit_commons.dart' as mlkit;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart'
    as text;
import 'package:path/path.dart' as path;

import 'google_mlkit_traditional_invoice_recognizer.dart';
import 'invoice_qr_parser.dart';
import 'traditional_invoice_ocr_review.dart';

enum InvoiceCaptureOrigin { liveCamera, gallery }

class InvoiceLiveFrameEvidence {
  const InvoiceLiveFrameEvidence({
    required this.timestamp,
    required this.snapshot,
    required this.rawLines,
    required this.sellerTaxIdCandidate,
    required this.sellerTaxIdSource,
    required this.sellerTaxIdChecksumValid,
  });

  final DateTime timestamp;
  final InvoiceLiveSnapshot snapshot;
  final List<String> rawLines;
  final String sellerTaxIdCandidate;
  final String sellerTaxIdSource;
  final bool? sellerTaxIdChecksumValid;

  Map<String, Object?> toJson() => <String, Object?>{
        'timestamp': timestamp.toUtc().toIso8601String(),
        ...snapshot.toJson(),
        'sellerTaxIdCandidate': sellerTaxIdCandidate,
        'sellerTaxIdSource': sellerTaxIdSource,
        'sellerTaxIdChecksumValid': sellerTaxIdChecksumValid,
        'rawLines': rawLines,
      };
}

class InvoiceLiveCaptureResult {
  const InvoiceLiveCaptureResult({
    required this.localReference,
    required this.fileName,
    required this.classification,
    required this.autoFrozen,
    required this.liveSnapshot,
    this.origin = InvoiceCaptureOrigin.liveCamera,
    this.liveHistory = const <InvoiceLiveFrameEvidence>[],
  });

  final String localReference;
  final String fileName;
  final InvoiceLiveClassification classification;
  final bool autoFrozen;
  final InvoiceLiveSnapshot liveSnapshot;
  final InvoiceCaptureOrigin origin;
  final List<InvoiceLiveFrameEvidence> liveHistory;
}

enum InvoiceLiveClassification { searching, traditional, electronic }

extension InvoiceLiveClassificationLabel on InvoiceLiveClassification {
  String get label => switch (this) {
        InvoiceLiveClassification.searching => '判讀中',
        InvoiceLiveClassification.traditional => '傳統發票',
        InvoiceLiveClassification.electronic => '電子發票',
      };
}

double invoiceLivePreviewAspectRatio({
  required double cameraAspectRatio,
  required Orientation orientation,
}) {
  if (!cameraAspectRatio.isFinite || cameraAspectRatio <= 0) return 1;
  return orientation == Orientation.portrait
      ? 1 / cameraAspectRatio
      : cameraAspectRatio;
}

class InvoiceLiveSnapshot {
  const InvoiceLiveSnapshot({
    this.classification = InvoiceLiveClassification.searching,
    this.invoiceNumber = '',
    this.invoiceDate = '',
    this.sellerTaxId = '',
    this.hasSellerIdentityContext = false,
    this.totalAmount,
    this.qrCount = 0,
    this.hasValidLeftQr = false,
    this.score = 0,
    this.stableObservations = 0,
    this.canFreeze = false,
    this.message = '請將完整發票放入框線內。',
  });

  final InvoiceLiveClassification classification;
  final String invoiceNumber;
  final String invoiceDate;
  final String sellerTaxId;
  final bool hasSellerIdentityContext;
  final double? totalAmount;
  final int qrCount;
  final bool hasValidLeftQr;
  final double score;
  final int stableObservations;
  final bool canFreeze;
  final String message;

  Map<String, Object?> toJson() => <String, Object?>{
        'classification': classification.name,
        'invoiceNumber': invoiceNumber,
        'invoiceDate': invoiceDate,
        'sellerTaxId': sellerTaxId,
        'hasSellerIdentityContext': hasSellerIdentityContext,
        'totalAmount': totalAmount,
        'qrCount': qrCount,
        'hasValidLeftQr': hasValidLeftQr,
        'score': score,
        'stableObservations': stableObservations,
        'canFreeze': canFreeze,
        'message': message,
      };
}

class TraditionalLiveIdentityConsensus {
  const TraditionalLiveIdentityConsensus({
    required this.invoiceNumber,
    required this.invoiceObservations,
    required this.identityContextObservations,
    required this.currentFrameRelevant,
  });

  final String invoiceNumber;
  final int invoiceObservations;
  final int identityContextObservations;
  final bool currentFrameRelevant;

  bool get canFreeze =>
      invoiceNumber.isNotEmpty &&
      invoiceObservations >= 2 &&
      identityContextObservations >= 2 &&
      currentFrameRelevant;

  int get stableObservations =>
      math.min(2, math.min(invoiceObservations, identityContextObservations));
}

bool hasStrongTraditionalSellerIdentityContext(List<String> rawLines) {
  final strongMerchantSignal = RegExp(
    r'(?:店|商行|公司|有限公司|股份有限公司|門市|餐廳|茶|咖啡|超商|便利商店|市場|館|坊|社|中心)$',
  );
  final genericHeader = RegExp(
    r'^(?:交易明細|商品明細|消費明細|銷售明細|發票明細|交易內容|商品|品項|項目|明細)$',
  );
  final nonMerchantSignal = RegExp(
    r'(?:電子發票|發票證明聯|統一發票|收銀機|電話|地址|總計|合計|應付|實付|總額|小計|收現|現金|找零|統計)',
    caseSensitive: false,
  );
  final invoiceIdentity = RegExp(
    r'^\s*[A-Z]{2}[\s-]?\d{8}\s*$',
    caseSensitive: false,
  );

  for (final rawLine in rawLines.take(10)) {
    final line = rawLine.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (line.isEmpty ||
        invoiceIdentity.hasMatch(line) ||
        genericHeader.hasMatch(line) ||
        nonMerchantSignal.hasMatch(line)) {
      continue;
    }
    final cjkCount = RegExp(r'[\u3400-\u9FFF]').allMatches(line).length;
    if (cjkCount >= 2 && strongMerchantSignal.hasMatch(line)) {
      return true;
    }
  }
  return false;
}

TraditionalLiveIdentityConsensus resolveTraditionalLiveIdentityConsensus({
  required List<InvoiceLiveFrameEvidence> history,
  required String currentInvoiceNumber,
  required String currentSellerTaxId,
  required List<String> currentRawLines,
  int windowSize = 4,
}) {
  final frames = <({String invoiceNumber, bool identityContext})>[
    for (final item in history)
      (
        invoiceNumber: item.snapshot.invoiceNumber.trim(),
        identityContext: item.snapshot.sellerTaxId.isNotEmpty ||
            item.snapshot.hasSellerIdentityContext ||
            hasStrongTraditionalSellerIdentityContext(item.rawLines),
      ),
    (
      invoiceNumber: currentInvoiceNumber.trim(),
      identityContext: currentSellerTaxId.trim().isNotEmpty ||
          hasStrongTraditionalSellerIdentityContext(currentRawLines),
    ),
  ];
  final recent = frames.length <= windowSize
      ? frames
      : frames.sublist(frames.length - windowSize);

  final counts = <String, int>{};
  for (final frame in recent) {
    final value = frame.invoiceNumber;
    if (value.isNotEmpty) counts[value] = (counts[value] ?? 0) + 1;
  }
  String consensusInvoice = '';
  var invoiceObservations = 0;
  for (final entry in counts.entries) {
    if (entry.value > invoiceObservations ||
        (entry.value == invoiceObservations &&
            entry.key == currentInvoiceNumber.trim())) {
      consensusInvoice = entry.key;
      invoiceObservations = entry.value;
    }
  }

  final identityContextObservations =
      recent.where((frame) => frame.identityContext).length;
  final currentIdentityContext = currentSellerTaxId.trim().isNotEmpty ||
      hasStrongTraditionalSellerIdentityContext(currentRawLines);
  final currentFrameRelevant =
      currentInvoiceNumber.trim() == consensusInvoice || currentIdentityContext;

  return TraditionalLiveIdentityConsensus(
    invoiceNumber: consensusInvoice,
    invoiceObservations: invoiceObservations,
    identityContextObservations: identityContextObservations,
    currentFrameRelevant: currentFrameRelevant,
  );
}

class InvoiceLiveCapturePage extends StatefulWidget {
  const InvoiceLiveCapturePage({super.key});

  static const String routeName = 'invoice-live-capture';
  static const String routePath = '/invoice-capture/live';
  static const Key autoFreezeKey = Key('invoice_live_auto_freeze');
  static const Key manualFreezeKey = Key('invoice_live_manual_freeze');
  static const Key flashKey = Key('invoice_live_flash');

  @override
  State<InvoiceLiveCapturePage> createState() => _InvoiceLiveCapturePageState();
}

class _InvoiceLiveCapturePageState extends State<InvoiceLiveCapturePage>
    with WidgetsBindingObserver {
  static const Duration _frameInterval = Duration(milliseconds: 1200);
  static const int _maxHistory = 10;

  final text.TextRecognizer _textRecognizer =
      text.TextRecognizer(script: text.TextRecognitionScript.chinese);
  final barcode.BarcodeScanner _barcodeScanner = barcode.BarcodeScanner(
    formats: const <barcode.BarcodeFormat>[barcode.BarcodeFormat.qrCode],
  );
  final TraditionalInvoiceTextParser _textParser =
      const TraditionalInvoiceTextParser();
  final InvoiceQrParser _qrParser = const InvoiceQrParser();

  CameraController? _camera;
  CameraDescription? _cameraDescription;
  InvoiceLiveSnapshot _snapshot = const InvoiceLiveSnapshot();
  final List<InvoiceLiveFrameEvidence> _history = <InvoiceLiveFrameEvidence>[];
  DateTime _lastFrameAt = DateTime.fromMillisecondsSinceEpoch(0);
  String _lastSignature = '';
  int _stableObservations = 0;
  bool _processingFrame = false;
  bool _freezing = false;
  bool _flashEnabled = false;
  bool _autoFreeze = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_initializeCamera());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final controller = _camera;
    _camera = null;
    unawaited(controller?.dispose());
    unawaited(_textRecognizer.close());
    unawaited(_barcodeScanner.close());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_disposeCamera());
      return;
    }
    if (state == AppLifecycleState.resumed && !_freezing) {
      unawaited(_initializeCamera());
    }
  }

  Future<void> _initializeCamera() async {
    if (_freezing || _camera?.value.isInitialized == true) return;
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) setState(() => _error = '找不到可用相機。');
        return;
      }
      final selected = cameras.firstWhere(
        (item) => item.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        selected,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup:
            Platform.isIOS ? ImageFormatGroup.bgra8888 : ImageFormatGroup.nv21,
      );
      await controller.initialize();
      if (!mounted || _freezing) {
        await controller.dispose();
        return;
      }
      final previous = _camera;
      _camera = controller;
      _cameraDescription = selected;
      _flashEnabled = false;
      await previous?.dispose();
      await controller.startImageStream(_onCameraImage);
      if (mounted) setState(() => _error = null);
    } on CameraException catch (error) {
      if (mounted) setState(() => _error = error.description ?? '相機初始化失敗。');
    } catch (error) {
      if (mounted) setState(() => _error = '相機初始化失敗：${error.runtimeType}');
    }
  }

  Future<void> _disposeCamera() async {
    final controller = _camera;
    _camera = null;
    _cameraDescription = null;
    if (mounted) setState(() {});
    try {
      await controller?.dispose();
    } catch (_) {}
  }

  void _onCameraImage(CameraImage image) {
    if (_freezing || _processingFrame) return;
    final now = DateTime.now();
    if (now.difference(_lastFrameAt) < _frameInterval) return;
    _lastFrameAt = now;
    final input = _inputImageFromCameraImage(image);
    if (input == null) return;
    _processingFrame = true;
    unawaited(_analyzeFrame(input).whenComplete(() => _processingFrame = false));
  }

  mlkit.InputImage? _inputImageFromCameraImage(CameraImage image) {
    final controller = _camera;
    final description = _cameraDescription;
    if (controller == null || description == null || image.planes.length != 1) {
      return null;
    }
    const orientations = <DeviceOrientation, int>{
      DeviceOrientation.portraitUp: 0,
      DeviceOrientation.landscapeLeft: 90,
      DeviceOrientation.portraitDown: 180,
      DeviceOrientation.landscapeRight: 270,
    };
    var rotationCompensation = orientations[controller.value.deviceOrientation];
    if (rotationCompensation == null) return null;
    if (Platform.isIOS) {
      rotationCompensation = description.sensorOrientation;
    } else if (description.lensDirection == CameraLensDirection.front) {
      rotationCompensation =
          (description.sensorOrientation + rotationCompensation) % 360;
    } else {
      rotationCompensation =
          (description.sensorOrientation - rotationCompensation + 360) % 360;
    }
    final rotation =
        mlkit.InputImageRotationValue.fromRawValue(rotationCompensation);
    if (rotation == null) return null;
    final format = Platform.isIOS
        ? mlkit.InputImageFormat.bgra8888
        : mlkit.InputImageFormat.nv21;
    final plane = image.planes.first;
    return mlkit.InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: mlkit.InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  Future<void> _analyzeFrame(mlkit.InputImage image) async {
    try {
      final recognized = await _textRecognizer.processImage(image);
      final codes = await _barcodeScanner.processImage(image);
      if (!mounted || _freezing) return;

      final lines = <String>[
        for (final block in recognized.blocks)
          for (final line in block.lines)
            if (line.text.trim().isNotEmpty) line.text.trim(),
      ];
      final parsedText = _textParser.parse(
        LocalOcrTextDocument(
          fullText: recognized.text.trim(),
          lines: List<String>.unmodifiable(lines),
        ),
      );
      final qrPayloads = codes
          .map((item) => item.rawValue?.trim() ?? '')
          .where((value) => value.isNotEmpty)
          .toSet()
          .toList(growable: false);

      InvoiceQrParseResult? validQr;
      for (final payload in qrPayloads) {
        final parsed = _qrParser.parse(payload);
        if (parsed.canStageCandidate) {
          validQr = parsed;
          break;
        }
      }

      final taxEvidence = extractTraditionalSellerTaxIdEvidence(lines);
      final invoiceNumber =
          validQr?.invoiceNumber ?? parsedText.invoiceNumber ?? '';
      final date = validQr?.invoiceDate ?? parsedText.invoiceDate;
      final invoiceDate = date == null ? '' : _formatDate(date);
      final sellerTaxId = validQr?.sellerIdentifier ??
          (taxEvidence?.acceptedForLive == true ? taxEvidence!.value : '');
      final sellerTaxIdCandidate =
          validQr?.sellerIdentifier ?? taxEvidence?.value ?? '';
      final sellerTaxIdSource =
          validQr != null ? 'qr' : taxEvidence?.source ?? '';
      final sellerTaxIdChecksumValid =
          validQr != null ? true : taxEvidence?.checksumValid;
      final total = validQr?.totalAmount?.toDouble() ?? parsedText.totalAmount;
      final classification = validQr != null || qrPayloads.length >= 2
          ? InvoiceLiveClassification.electronic
          : _hasTextEvidence(parsedText)
              ? InvoiceLiveClassification.traditional
              : InvoiceLiveClassification.searching;

      final traditionalConsensus = resolveTraditionalLiveIdentityConsensus(
        history: _history,
        currentInvoiceNumber: invoiceNumber,
        currentSellerTaxId: sellerTaxId,
        currentRawLines: lines,
      );
      final hasSellerIdentityContext = validQr != null ||
          sellerTaxId.isNotEmpty ||
          hasStrongTraditionalSellerIdentityContext(lines);

      final signature = <Object?>[
        classification.name,
        invoiceNumber,
        sellerTaxId,
        validQr != null,
      ].join('|');
      if (signature == _lastSignature &&
          _hasStableEvidence(
            classification,
            invoiceNumber,
            sellerTaxId,
            validQr != null,
          )) {
        _stableObservations += 1;
      } else {
        _lastSignature = signature;
        _stableObservations = 1;
      }

      final canFreeze = switch (classification) {
        InvoiceLiveClassification.electronic =>
          validQr != null && invoiceNumber.isNotEmpty && sellerTaxId.isNotEmpty,
        InvoiceLiveClassification.traditional => traditionalConsensus.canFreeze,
        InvoiceLiveClassification.searching => false,
      };
      final effectiveStableObservations =
          classification == InvoiceLiveClassification.traditional
              ? traditionalConsensus.stableObservations
              : _stableObservations;
      final effectiveInvoiceNumber =
          classification == InvoiceLiveClassification.traditional &&
                  invoiceNumber.isEmpty &&
                  traditionalConsensus.invoiceObservations >= 2
              ? traditionalConsensus.invoiceNumber
              : invoiceNumber;
      final score = _score(
        classification: classification,
        invoiceNumber: effectiveInvoiceNumber,
        invoiceDate: invoiceDate,
        sellerTaxId: sellerTaxId,
        hasSellerIdentityContext: hasSellerIdentityContext ||
            traditionalConsensus.identityContextObservations >= 2,
        totalAmount: total,
        qrCount: qrPayloads.length,
        hasValidLeftQr: validQr != null,
      );

      final next = InvoiceLiveSnapshot(
        classification: classification,
        invoiceNumber: effectiveInvoiceNumber,
        invoiceDate: invoiceDate,
        sellerTaxId: sellerTaxId,
        hasSellerIdentityContext: hasSellerIdentityContext ||
            traditionalConsensus.identityContextObservations >= 2,
        totalAmount: total,
        qrCount: qrPayloads.length,
        hasValidLeftQr: validQr != null,
        score: score,
        stableObservations: effectiveStableObservations,
        canFreeze: canFreeze,
        message: _guidance(
          classification: classification,
          invoiceNumber: effectiveInvoiceNumber,
          sellerTaxId: sellerTaxId,
          hasSellerIdentityContext: hasSellerIdentityContext ||
              traditionalConsensus.identityContextObservations >= 2,
          qrCount: qrPayloads.length,
          hasValidLeftQr: validQr != null,
          canFreeze: canFreeze,
          stableObservations: effectiveStableObservations,
        ),
      );
      _appendHistory(
        InvoiceLiveFrameEvidence(
          timestamp: DateTime.now(),
          snapshot: next,
          rawLines: List<String>.unmodifiable(lines),
          sellerTaxIdCandidate: sellerTaxIdCandidate,
          sellerTaxIdSource: sellerTaxIdSource,
          sellerTaxIdChecksumValid: sellerTaxIdChecksumValid,
        ),
      );
      setState(() => _snapshot = next);
      if (_autoFreeze && canFreeze && effectiveStableObservations >= 2) {
        unawaited(_freeze(auto: true));
      }
    } catch (_) {
      if (mounted && !_freezing) {
        setState(() {
          _snapshot = InvoiceLiveSnapshot(
            classification: _snapshot.classification,
            invoiceNumber: _snapshot.invoiceNumber,
            invoiceDate: _snapshot.invoiceDate,
            sellerTaxId: _snapshot.sellerTaxId,
            hasSellerIdentityContext: _snapshot.hasSellerIdentityContext,
            totalAmount: _snapshot.totalAmount,
            qrCount: _snapshot.qrCount,
            hasValidLeftQr: _snapshot.hasValidLeftQr,
            score: _snapshot.score,
            stableObservations: _snapshot.stableObservations,
            canFreeze: _snapshot.canFreeze,
            message: 'Live frame 暫時無法解析，請保持發票平整並重新對焦。',
          );
        });
      }
    }
  }

  void _appendHistory(InvoiceLiveFrameEvidence evidence) {
    _history.add(evidence);
    if (_history.length > _maxHistory) {
      _history.removeRange(0, _history.length - _maxHistory);
    }
  }

  bool _hasTextEvidence(TraditionalInvoiceOcrRecognition recognition) {
    return (recognition.invoiceNumber?.isNotEmpty == true) ||
        (recognition.sellerTaxId?.isNotEmpty == true) ||
        recognition.invoiceDate != null ||
        recognition.sellerName?.isNotEmpty == true ||
        recognition.totalAmount != null;
  }

  bool _hasStableEvidence(
    InvoiceLiveClassification classification,
    String invoiceNumber,
    String sellerTaxId,
    bool hasValidLeftQr,
  ) {
    if (classification == InvoiceLiveClassification.electronic) {
      return hasValidLeftQr &&
          invoiceNumber.isNotEmpty &&
          sellerTaxId.isNotEmpty;
    }
    if (classification == InvoiceLiveClassification.traditional) {
      return invoiceNumber.isNotEmpty && sellerTaxId.isNotEmpty;
    }
    return false;
  }

  double _score({
    required InvoiceLiveClassification classification,
    required String invoiceNumber,
    required String invoiceDate,
    required String sellerTaxId,
    required bool hasSellerIdentityContext,
    required double? totalAmount,
    required int qrCount,
    required bool hasValidLeftQr,
  }) {
    var value = 0.0;
    if (invoiceNumber.isNotEmpty) value += 0.35;
    if (sellerTaxId.isNotEmpty) {
      value += 0.35;
    } else if (classification == InvoiceLiveClassification.traditional &&
        hasSellerIdentityContext) {
      value += 0.25;
    }
    if (invoiceDate.isNotEmpty) value += 0.10;
    if (totalAmount != null) value += 0.10;
    if (classification == InvoiceLiveClassification.electronic) {
      if (hasValidLeftQr) value += 0.10;
    } else if (classification == InvoiceLiveClassification.traditional) {
      value += 0.10;
    }
    return value.clamp(0.0, 1.0);
  }

  String _guidance({
    required InvoiceLiveClassification classification,
    required String invoiceNumber,
    required String sellerTaxId,
    required bool hasSellerIdentityContext,
    required int qrCount,
    required bool hasValidLeftQr,
    required bool canFreeze,
    required int stableObservations,
  }) {
    if (canFreeze && stableObservations >= 2) {
      return '低誤判 identity 證據已跨 frame 穩定，正在凍結高品質影像供 Local 詳細解析與 Gemini 覆核。';
    }
    if (invoiceNumber.isEmpty) {
      return '請讓發票號碼完整、水平且清晰地落在上方框內。';
    }
    if (classification == InvoiceLiveClassification.electronic &&
        !hasValidLeftQr) {
      return '電子發票需有效左 QR；請避免裁切與反光。';
    }
    if (classification == InvoiceLiveClassification.traditional &&
        !hasSellerIdentityContext) {
      return '尚未取得商家 identity 脈絡；請讓商家標頭與 NO./統編行清晰入鏡。';
    }
    if (classification == InvoiceLiveClassification.electronic &&
        sellerTaxId.isEmpty) {
      return '尚未從 QR 取得賣方統編，請保持左 QR 完整清晰。';
    }
    if (classification == InvoiceLiveClassification.electronic && qrCount < 2) {
      return '必要 identity 已取得；右 QR 可一併入鏡以提升凍結後明細解析，但不影響自動凍結。';
    }
    if (classification == InvoiceLiveClassification.traditional &&
        sellerTaxId.isEmpty) {
      return '商家 identity 已看到，但統編字元仍不穩；請保持不動，系統會以近期 frame 共識決定凍結，不會猜寫統編。';
    }
    return stableObservations > 0
        ? 'identity 已接近門檻，請保持不動等待第二次穩定取樣。'
        : '請將發票攤平並保持完整落在白色框內。';
  }

  String _formatDate(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }

  Future<void> _freeze({required bool auto}) async {
    final controller = _camera;
    if (_freezing || controller == null || !controller.value.isInitialized) {
      return;
    }
    _freezing = true;
    if (mounted) setState(() {});
    try {
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
      final file = await controller.takePicture();
      if (!mounted) return;
      Navigator.of(context).pop(
        InvoiceLiveCaptureResult(
          localReference: file.path,
          fileName: file.name.isNotEmpty ? file.name : path.basename(file.path),
          classification: _snapshot.classification,
          autoFrozen: auto,
          liveSnapshot: _snapshot,
          origin: InvoiceCaptureOrigin.liveCamera,
          liveHistory: List<InvoiceLiveFrameEvidence>.unmodifiable(_history),
        ),
      );
    } on CameraException catch (error) {
      if (!mounted) return;
      setState(() {
        _freezing = false;
        _error = error.description ?? '凍結影像失敗。';
      });
      await _restartStream();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _freezing = false;
        _error = '凍結影像失敗：${error.runtimeType}';
      });
      await _restartStream();
    }
  }

  Future<void> _restartStream() async {
    final controller = _camera;
    if (controller == null || !controller.value.isInitialized) return;
    if (!controller.value.isStreamingImages) {
      try {
        await controller.startImageStream(_onCameraImage);
      } catch (_) {}
    }
  }

  Future<void> _toggleFlash() async {
    final controller = _camera;
    if (controller == null || !controller.value.isInitialized) return;
    try {
      final next = !_flashEnabled;
      await controller.setFlashMode(next ? FlashMode.torch : FlashMode.off);
      if (mounted) setState(() => _flashEnabled = next);
    } catch (_) {
      if (mounted) setState(() => _error = '此裝置無法切換補光燈。');
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _camera;
    return Scaffold(
      appBar: AppBar(title: const Text('Live 發票辨識')),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            _TopGuidance(snapshot: _snapshot, error: _error),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: ColoredBox(
                    color: Colors.black,
                    child: controller == null || !controller.value.isInitialized
                        ? const Center(child: CircularProgressIndicator())
                        : Center(
                            child: AspectRatio(
                              aspectRatio: invoiceLivePreviewAspectRatio(
                                cameraAspectRatio: controller.value.aspectRatio,
                                orientation: MediaQuery.orientationOf(context),
                              ),
                              child: Stack(
                                fit: StackFit.expand,
                                children: <Widget>[
                                  CameraPreview(controller),
                                  _ReceiptGuidanceOverlay(snapshot: _snapshot),
                                ],
                              ),
                            ),
                          ),
                  ),
                ),
              ),
            ),
            _BottomControls(
              autoFreeze: _autoFreeze,
              flashEnabled: _flashEnabled,
              freezing: _freezing,
              onAutoFreezeChanged: _freezing
                  ? null
                  : (value) => setState(() => _autoFreeze = value),
              onFlash: _freezing ? null : _toggleFlash,
              onFreeze: _freezing ? null : () => _freeze(auto: false),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopGuidance extends StatelessWidget {
  const _TopGuidance({required this.snapshot, required this.error});

  final InvoiceLiveSnapshot snapshot;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Chip(label: Text(snapshot.classification.label)),
              const SizedBox(width: 8),
              Text('穩定 ${snapshot.stableObservations}/2'),
              const Spacer(),
              Text('${(snapshot.score * 100).round()}%'),
            ],
          ),
          Text(error ?? snapshot.message),
        ],
      ),
    );
  }
}

class _ReceiptGuidanceOverlay extends StatelessWidget {
  const _ReceiptGuidanceOverlay({required this.snapshot});

  final InvoiceLiveSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IgnorePointer(
      child: Center(
        child: FractionallySizedBox(
          widthFactor: 0.88,
          heightFactor: 0.90,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final size = Size(constraints.maxWidth, constraints.maxHeight);
              return Stack(
                children: <Widget>[
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white, width: 2),
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                  ),
                  _anchor(
                    size,
                    const Rect.fromLTWH(0.16, 0.16, 0.68, 0.14),
                    '發票號碼（必要）',
                    snapshot.invoiceNumber.isNotEmpty,
                    scheme,
                  ),
                  _anchor(
                    size,
                    const Rect.fromLTWH(0.14, 0.42, 0.72, 0.12),
                    snapshot.classification == InvoiceLiveClassification.electronic
                        ? '賣方統編（必要）'
                        : '商家／統編 identity（必要）',
                    snapshot.sellerTaxId.isNotEmpty ||
                        snapshot.hasSellerIdentityContext,
                    scheme,
                  ),
                  if (snapshot.classification ==
                      InvoiceLiveClassification.electronic) ...<Widget>[
                    _anchor(
                      size,
                      const Rect.fromLTWH(0.07, 0.66, 0.38, 0.27),
                      '左 QR（必要）',
                      snapshot.hasValidLeftQr,
                      scheme,
                    ),
                    _anchor(
                      size,
                      const Rect.fromLTWH(0.55, 0.66, 0.38, 0.27),
                      '右 QR（選填）',
                      snapshot.qrCount >= 2,
                      scheme,
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _anchor(
    Size size,
    Rect normalized,
    String label,
    bool accepted,
    ColorScheme scheme,
  ) {
    final rect = Rect.fromLTWH(
      normalized.left * size.width,
      normalized.top * size.height,
      normalized.width * size.width,
      normalized.height * size.height,
    );
    final color = accepted ? Colors.greenAccent : scheme.error;
    return Positioned.fromRect(
      rect: rect,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: color, width: 2),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Align(
          alignment: Alignment.topLeft,
          child: ColoredBox(
            color: Colors.black54,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              child: Text(label, style: TextStyle(color: color, fontSize: 12)),
            ),
          ),
        ),
      ),
    );
  }
}

class _BottomControls extends StatelessWidget {
  const _BottomControls({
    required this.autoFreeze,
    required this.flashEnabled,
    required this.freezing,
    required this.onAutoFreezeChanged,
    required this.onFlash,
    required this.onFreeze,
  });

  final bool autoFreeze;
  final bool flashEnabled;
  final bool freezing;
  final ValueChanged<bool>? onAutoFreezeChanged;
  final VoidCallback? onFlash;
  final VoidCallback? onFreeze;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      child: Column(
        children: <Widget>[
          SwitchListTile(
            key: InvoiceLiveCapturePage.autoFreezeKey,
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('identity 穩定後自動凍結'),
            subtitle: const Text(
              '傳統：近期 frame 需重複取得發票號碼與商家／統編 identity 脈絡；電子：需發票號碼、賣方統編與有效左 QR。詳細欄位於凍結後解析。',
            ),
            value: autoFreeze,
            onChanged: onAutoFreezeChanged,
          ),
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton.icon(
                  key: InvoiceLiveCapturePage.flashKey,
                  onPressed: onFlash,
                  icon: Icon(flashEnabled ? Icons.flash_on : Icons.flash_off),
                  label: Text(flashEnabled ? '關閉補光' : '開啟補光'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  key: InvoiceLiveCapturePage.manualFreezeKey,
                  onPressed: onFreeze,
                  icon: freezing
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.camera_alt_outlined),
                  label: Text(freezing ? '凍結中…' : '立即凍結'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
