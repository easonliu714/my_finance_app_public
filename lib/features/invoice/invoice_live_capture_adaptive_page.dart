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
import 'invoice_live_adaptive_overlay.dart';
import 'invoice_live_capture_page.dart';
import 'invoice_live_capture_stabilized_page.dart'
    show
        InvoiceLiveCameraTelemetryEvidence,
        isFrozenInvoiceIdentityConsistent;
import 'invoice_live_field_readiness.dart';
import 'invoice_qr_parser.dart';
import 'invoice_total_evidence.dart';

class AdaptiveInvoiceLiveCapturePage extends StatefulWidget {
  const AdaptiveInvoiceLiveCapturePage({super.key});

  @override
  State<AdaptiveInvoiceLiveCapturePage> createState() =>
      _AdaptiveInvoiceLiveCapturePageState();
}

class _LiveFrameInput {
  const _LiveFrameInput({
    required this.inputImage,
    required this.imageSize,
    required this.rotation,
  });

  final mlkit.InputImage inputImage;
  final Size imageSize;
  final mlkit.InputImageRotation rotation;
}

class _FrozenIdentityProbe {
  const _FrozenIdentityProbe({
    required this.invoiceNumber,
    required this.sellerTaxId,
    required this.rawLineCount,
    required this.hasValidQr,
  });

  final String invoiceNumber;
  final String sellerTaxId;
  final int rawLineCount;
  final bool hasValidQr;
}

class _AdaptiveInvoiceLiveCapturePageState
    extends State<AdaptiveInvoiceLiveCapturePage>
    with WidgetsBindingObserver {
  static const Duration _frameInterval = Duration(milliseconds: 1200);
  static const Duration _threeASettleDelay = Duration(milliseconds: 250);
  static const int _maxHistory = 10;
  static const int _maxCameraEvents = 64;

  final text.TextRecognizer _textRecognizer =
      text.TextRecognizer(script: text.TextRecognitionScript.chinese);
  final barcode.BarcodeScanner _barcodeScanner = barcode.BarcodeScanner(
    formats: const <barcode.BarcodeFormat>[barcode.BarcodeFormat.all],
  );
  final TraditionalInvoiceTextParser _textParser =
      const TraditionalInvoiceTextParser();
  final InvoiceQrParser _qrParser = const InvoiceQrParser();

  CameraController? _camera;
  CameraDescription? _cameraDescription;
  InvoiceLiveSnapshot _snapshot = const InvoiceLiveSnapshot();
  final List<InvoiceLiveFrameEvidence> _history = <InvoiceLiveFrameEvidence>[];
  final List<InvoiceLiveFrameEvidence> _cameraEvents =
      <InvoiceLiveFrameEvidence>[];
  DateTime _lastFrameAt = DateTime.fromMillisecondsSinceEpoch(0);
  String _lastSignature = '';
  int _stableObservations = 0;
  InvoiceAdaptiveFrameState _frameState =
      const InvoiceAdaptiveFrameState.initial();
  InvoiceLiveVisualOverlaySnapshot? _visualOverlay;
  bool _processingFrame = false;
  bool _freezing = false;
  bool _flashEnabled = false;
  bool _autoFreeze = true;
  bool _cameraInitializing = false;
  bool _traditionalExplicitTaxRequired = false;
  bool _electronicWideEvidenceActive = false;
  int _cameraGeneration = 0;
  int _captureSequence = 0;
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
    _cameraGeneration += 1;
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
      unawaited(_disposeCamera(reason: 'lifecycle_${state.name}'));
    } else if (state == AppLifecycleState.resumed && !_freezing) {
      unawaited(_initializeCamera());
    }
  }

  void _recordCameraEvent(
    String event, {
    Map<String, Object?> details = const <String, Object?>{},
  }) {
    final description = _cameraDescription;
    final controller = _camera;
    final preview = controller?.value.previewSize;
    _cameraEvents.add(
      InvoiceLiveCameraTelemetryEvidence(
        timestamp: DateTime.now(),
        snapshot: _snapshot,
        event: event,
        details: <String, Object?>{
          'cameraName': description?.name,
          'lensDirection': description?.lensDirection.name,
          'sensorOrientation': description?.sensorOrientation,
          'previewWidth': preview?.width,
          'previewHeight': preview?.height,
          'deviceOrientation': controller?.value.deviceOrientation.name,
          'streamingImages': controller?.value.isStreamingImages,
          'captureSequence': _captureSequence,
          ...details,
        },
      ),
    );
    if (_cameraEvents.length > _maxCameraEvents) {
      _cameraEvents.removeRange(0, _cameraEvents.length - _maxCameraEvents);
    }
  }

  Future<void> _initializeCamera() async {
    if (_freezing ||
        _cameraInitializing ||
        _camera?.value.isInitialized == true) {
      return;
    }
    _cameraInitializing = true;
    final generation = ++_cameraGeneration;
    _recordCameraEvent('CAMERA_INITIALIZE_START', details: <String, Object?>{
      'generation': generation,
    });
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
      if (!mounted || _freezing || generation != _cameraGeneration) {
        await controller.dispose();
        return;
      }
      final previous = _camera;
      _camera = controller;
      _cameraDescription = selected;
      _flashEnabled = false;
      await previous?.dispose();
      await controller.startImageStream(_onCameraImage);
      _recordCameraEvent('CAMERA_INITIALIZE_DONE', details: <String, Object?>{
        'generation': generation,
        'availableCameraCount': cameras.length,
      });
      if (mounted) setState(() => _error = null);
    } on CameraException catch (error) {
      _recordCameraEvent('CAMERA_INITIALIZE_FAILED', details: <String, Object?>{
        'generation': generation,
        'errorCode': error.code,
      });
      if (mounted) setState(() => _error = error.description ?? '相機初始化失敗。');
    } catch (error) {
      _recordCameraEvent('CAMERA_INITIALIZE_FAILED', details: <String, Object?>{
        'generation': generation,
        'errorType': error.runtimeType.toString(),
      });
      if (mounted) setState(() => _error = '相機初始化失敗：${error.runtimeType}');
    } finally {
      if (generation == _cameraGeneration) _cameraInitializing = false;
    }
  }

  Future<void> _disposeCamera({required String reason}) async {
    _cameraGeneration += 1;
    _cameraInitializing = false;
    final controller = _camera;
    _recordCameraEvent('CAMERA_DISPOSE', details: <String, Object?>{
      'reason': reason,
    });
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
    final frame = _inputImageFromCameraImage(image);
    if (frame == null) return;
    _processingFrame = true;
    unawaited(_analyzeFrame(frame).whenComplete(() => _processingFrame = false));
  }

  _LiveFrameInput? _inputImageFromCameraImage(CameraImage image) {
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
    final plane = image.planes.first;
    final imageSize = Size(image.width.toDouble(), image.height.toDouble());
    final inputImage = mlkit.InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: mlkit.InputImageMetadata(
        size: imageSize,
        rotation: rotation,
        format: Platform.isIOS
            ? mlkit.InputImageFormat.bgra8888
            : mlkit.InputImageFormat.nv21,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
    return _LiveFrameInput(
      inputImage: inputImage,
      imageSize: imageSize,
      rotation: rotation,
    );
  }

  Future<void> _analyzeFrame(_LiveFrameInput frame) async {
    try {
      final recognized = await _textRecognizer.processImage(frame.inputImage);
      final codes = await _barcodeScanner.processImage(frame.inputImage);
      if (!mounted || _freezing) return;

      final positionedLines = <LocalOcrTextLine>[
        for (final block in recognized.blocks)
          for (final line in block.lines)
            if (line.text.trim().isNotEmpty)
              LocalOcrTextLine(
                text: line.text.trim(),
                left: line.boundingBox.left,
                top: line.boundingBox.top,
                right: line.boundingBox.right,
                bottom: line.boundingBox.bottom,
              ),
      ];
      final visualLines = <InvoiceOcrVisualLine>[
        for (final line in positionedLines)
          InvoiceOcrVisualLine(
            text: line.text,
            imageRect: Rect.fromLTRB(line.left, line.top, line.right, line.bottom),
          ),
      ];
      final lines = positionedLines.map((line) => line.text).toList(growable: false);
      final parsedText = _textParser.parse(
        LocalOcrTextDocument(
          fullText: recognized.text.trim(),
          lines: List<String>.unmodifiable(lines),
          positionedLines: List<LocalOcrTextLine>.unmodifiable(positionedLines),
        ),
      );

      final qrCodes = codes
          .where((item) => item.format == barcode.BarcodeFormat.qrCode)
          .toList(growable: false);
      final oneDimensionalBarcodes = codes
          .where((item) =>
              item.format != barcode.BarcodeFormat.qrCode &&
              _looksLikeOneDimensionalBarcode(item.boundingBox))
          .toList(growable: false);
      final qrPayloads = qrCodes
          .map((item) => item.rawValue?.trim() ?? '')
          .where((value) => value.isNotEmpty)
          .toSet()
          .toList(growable: false);

      InvoiceQrParseResult? validQr;
      final qrVisualEvidence = <InvoiceLiveVisualEvidence>[];
      final receiptQrGeometryRects = <Rect>[];
      for (final code in qrCodes) {
        final payload = code.rawValue?.trim() ?? '';
        final parsed = payload.isEmpty ? null : _qrParser.parse(payload);
        final accepted = parsed?.canStageCandidate == true;
        if (accepted) {
          validQr ??= parsed;
          receiptQrGeometryRects.add(code.boundingBox);
        }
        qrVisualEvidence.add(
          InvoiceLiveVisualEvidence(
            kind: InvoiceLiveVisualEvidenceKind.qr,
            imageRect: code.boundingBox,
            label: accepted ? 'QR ✓' : 'QR 已定位',
            accepted: accepted,
          ),
        );
      }

      final taxEvidence = extractTraditionalSellerTaxIdEvidence(
        lines,
        invoiceNumber: parsedText.invoiceNumber,
        positionedLines: positionedLines,
      );
      final invoiceNumber =
          validQr?.invoiceNumber ?? parsedText.invoiceNumber ?? '';
      final invoiceVisualRect = parsedText.invoiceNumber?.isNotEmpty == true
          ? findInvoiceTextEvidenceRect(visualLines, parsedText.invoiceNumber!)
          : null;
      final electronicWideEvidence = resolveInvoiceElectronicWideEvidence(
        lines: visualLines,
        invoiceNumberRect: invoiceVisualRect,
        qrRects: qrCodes.map((item) => item.boundingBox).toList(growable: false),
        barcodeRects: oneDimensionalBarcodes
            .map((item) => item.boundingBox)
            .toList(growable: false),
        imageSize: frame.imageSize,
        rotation: frame.rotation,
        lensDirection:
            _cameraDescription?.lensDirection ?? CameraLensDirection.back,
      );
      final electronicWide = electronicWideEvidence.keepWide;
      _recordCameraEvent(
        'ELECTRONIC_WIDE_EVIDENCE',
        details: <String, Object?>{
          'invoiceNumber': invoiceNumber,
          'invoiceNumberInsideGuide':
              electronicWideEvidence.invoiceNumberInsideGuide,
          'qrCountInsideGuide': electronicWideEvidence.qrCountInsideGuide,
          'hasElectronicInvoiceHeaderAbove':
              electronicWideEvidence.hasElectronicInvoiceHeaderAbove,
          'hasRandomCodeBelow': electronicWideEvidence.hasRandomCodeBelow,
          'hasOneDimensionalBarcodeInsideGuide':
              electronicWideEvidence.hasOneDimensionalBarcodeInsideGuide,
          'reasons': electronicWideEvidence.reasons,
          'keepWide': electronicWide,
          'affectsReadinessProfile': true,
        },
      );

      final date = validQr?.invoiceDate ?? parsedText.invoiceDate;
      final invoiceDate = date == null ? '' : _formatDate(date);
      final sellerTaxId = validQr?.sellerIdentifier ??
          (taxEvidence?.acceptedForLive == true ? taxEvidence!.value : '');
      final sellerTaxIdCandidate =
          validQr?.sellerIdentifier ?? taxEvidence?.value ?? '';
      final totalEvidence = resolveInvoiceTotalEvidence(lines);
      final total = validQr?.totalAmount?.toDouble() ??
          totalEvidence?.value ??
          parsedText.totalAmount;
      final classification = electronicWide
          ? InvoiceLiveClassification.electronic
          : invoiceNumber.isNotEmpty
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
      final effectiveInvoiceNumber = invoiceNumber.isEmpty &&
              traditionalConsensus.invoiceObservations >= 2
          ? traditionalConsensus.invoiceNumber
          : invoiceNumber;
      final effectiveIdentityContext = hasSellerIdentityContext ||
          traditionalConsensus.identityContextObservations >= 2;
      final readinessProfile = electronicWide
          ? InvoiceLiveReadinessProfile.electronicOrUnresolved
          : InvoiceLiveReadinessProfile.traditionalExplicitSellerTax;
      final readiness = resolveInvoiceLiveFieldReadiness(
        consensus: traditionalConsensus,
        invoiceNumber: effectiveInvoiceNumber,
        sellerTaxId: sellerTaxId,
        hasSellerIdentityContext: effectiveIdentityContext,
        previousSignature: _lastSignature,
        previousConsecutiveObservations: _stableObservations,
        profile: readinessProfile,
      );
      _lastSignature = readiness.signature;
      _stableObservations = readiness.consecutiveObservations;

      final canFreeze = readiness.canFreeze;
      final effectiveStableObservations = readiness.stableObservations;
      final next = InvoiceLiveSnapshot(
        classification: classification,
        invoiceNumber: effectiveInvoiceNumber,
        invoiceDate: invoiceDate,
        sellerTaxId: sellerTaxId,
        hasSellerIdentityContext: effectiveIdentityContext,
        totalAmount: total,
        qrCount: qrPayloads.length,
        hasValidLeftQr: validQr != null,
        score: _score(
          invoiceNumber: effectiveInvoiceNumber,
          invoiceDate: invoiceDate,
          sellerTaxId: sellerTaxId,
          hasSellerIdentityContext: effectiveIdentityContext,
          totalAmount: total,
          hasValidLeftQr: validQr != null,
        ),
        stableObservations: effectiveStableObservations,
        canFreeze: canFreeze,
        message: _guidance(
          classification: classification,
          invoiceNumber: effectiveInvoiceNumber,
          sellerTaxId: sellerTaxId,
          hasSellerIdentityContext: effectiveIdentityContext,
          qrCount: qrPayloads.length,
          hasValidLeftQr: validQr != null,
          electronicWideEvidence: electronicWide,
          canFreeze: canFreeze,
          stableObservations: effectiveStableObservations,
        ),
      );

      final sellerTaxVisualValue =
          validQr?.sellerIdentifier ?? taxEvidence?.value ?? '';
      final sellerTaxEvidenceRect = sellerTaxVisualValue.isNotEmpty
          ? findSellerTaxTextEvidenceRect(visualLines, sellerTaxVisualValue)
          : null;
      final sellerTaxVisualCandidate = sellerTaxEvidenceRect == null
          ? findSellerTaxVisualCandidate(
              visualLines,
              invoiceNumber: parsedText.invoiceNumber ?? '',
            )
          : null;

      final geometry = observeInvoiceReceiptGeometry(
        imageSize: frame.imageSize,
        rotation: frame.rotation,
        lensDirection:
            _cameraDescription?.lensDirection ?? CameraLensDirection.back,
        anchorRect: invoiceVisualRect,
        evidenceRects: <Rect>[
          for (final item in visualLines) item.imageRect,
          ...receiptQrGeometryRects,
        ],
      );
      final previousFrameMode = _frameState.mode;
      final nextFrameState = _frameState.advanceForReceiptIntent(
        invoiceNumberObserved: effectiveInvoiceNumber.isNotEmpty,
        electronicWideEvidence: electronicWide,
      );
      _recordCameraEvent(
        'GUIDANCE_GEOMETRY_OBSERVED',
        details: <String, Object?>{
          'geometrySignal': geometry.signal.name,
          'sourceEvidenceCount': geometry.sourceEvidenceCount,
          'evidenceCount': geometry.evidenceCount,
          'heightToWidthRatio': geometry.heightToWidthRatio,
          'medianEvidenceWidth': geometry.medianEvidenceWidth,
          'envelopeLeft': geometry.normalizedEnvelope?.left,
          'envelopeTop': geometry.normalizedEnvelope?.top,
          'envelopeRight': geometry.normalizedEnvelope?.right,
          'envelopeBottom': geometry.normalizedEnvelope?.bottom,
          'anchorApplied': geometry.anchorApplied,
          'currentMode': previousFrameMode.name,
          'nextMode': nextFrameState.mode.name,
          'narrowTallStreak': nextFrameState.narrowTallStreak,
          'wideStreak': nextFrameState.wideStreak,
          'frameDecisionSource': electronicWide
              ? 'electronic_wide_evidence'
              : effectiveInvoiceNumber.isNotEmpty
                  ? 'traditional_first'
                  : 'initial_wide_hold',
          'affectsRecognitionDecision': false,
        },
      );
      if (nextFrameState.mode != previousFrameMode) {
        _recordCameraEvent(
          'GUIDANCE_FRAME_MODE_CHANGED',
          details: <String, Object?>{
            'from': previousFrameMode.name,
            'to': nextFrameState.mode.name,
            'electronicWideEvidence': electronicWide,
            'electronicWideReasons': electronicWideEvidence.reasons,
            'geometrySignalDiagnosticOnly': geometry.signal.name,
            'affectsRecognitionDecision': false,
          },
        );
      }

      final sellerTaxOverlayAccepted =
          validQr != null || taxEvidence?.acceptedForLive == true;
      final visualEvidence = <InvoiceLiveVisualEvidence>[
        if (invoiceVisualRect != null)
          InvoiceLiveVisualEvidence(
            kind: InvoiceLiveVisualEvidenceKind.invoiceNumber,
            imageRect: invoiceVisualRect,
            label: '發票號碼 ✓',
            accepted: true,
          ),
        if (sellerTaxEvidenceRect != null)
          InvoiceLiveVisualEvidence(
            kind: InvoiceLiveVisualEvidenceKind.sellerTaxId,
            imageRect: sellerTaxEvidenceRect,
            label: sellerTaxOverlayAccepted ? '賣方統編 ✓' : '統編候選',
            accepted: sellerTaxOverlayAccepted,
          )
        else if (sellerTaxVisualCandidate != null)
          InvoiceLiveVisualEvidence(
            kind: InvoiceLiveVisualEvidenceKind.sellerTaxId,
            imageRect: sellerTaxVisualCandidate.imageRect,
            label: '統編候選',
            accepted: false,
          ),
        ...qrVisualEvidence,
      ];
      final visualOverlay = InvoiceLiveVisualOverlaySnapshot(
        imageSize: frame.imageSize,
        rotation: frame.rotation,
        lensDirection:
            _cameraDescription?.lensDirection ?? CameraLensDirection.back,
        evidence: List<InvoiceLiveVisualEvidence>.unmodifiable(visualEvidence),
        geometry: geometry,
      );

      _appendHistory(
        InvoiceLiveFrameEvidence(
          timestamp: DateTime.now(),
          snapshot: next,
          rawLines: List<String>.unmodifiable(lines),
          sellerTaxIdCandidate: sellerTaxIdCandidate,
          sellerTaxIdSource: validQr != null ? 'qr' : taxEvidence?.source ?? '',
          sellerTaxIdChecksumValid:
              validQr != null ? true : taxEvidence?.checksumValid,
        ),
      );
      setState(() {
        _snapshot = next;
        _frameState = nextFrameState;
        _visualOverlay = visualOverlay;
        _electronicWideEvidenceActive = electronicWide;
        _traditionalExplicitTaxRequired = !electronicWide;
      });
      if (_autoFreeze && canFreeze && effectiveStableObservations >= 2) {
        unawaited(_freeze(auto: true));
      }
    } catch (_) {
      if (mounted && !_freezing) {
        setState(() => _error = 'Live frame 暫時無法解析，請保持發票平整並重新對焦。');
      }
    }
  }

  bool _looksLikeOneDimensionalBarcode(Rect rect) {
    final width = rect.width.abs();
    final height = rect.height.abs();
    if (width <= 0 || height <= 0) return false;
    return math.max(width, height) / math.min(width, height) >= 1.8;
  }

  Future<({bool focusLocked, bool exposureLocked})> _lockThreeA(
    CameraController controller,
  ) async {
    var focusLocked = false;
    var exposureLocked = false;
    _recordCameraEvent('THREE_A_LOCK_START');
    try {
      await controller.setFocusMode(FocusMode.locked);
      focusLocked = true;
    } catch (_) {}
    _recordCameraEvent('FOCUS_LOCK_DONE', details: <String, Object?>{
      'success': focusLocked,
    });
    try {
      await controller.setExposureMode(ExposureMode.locked);
      exposureLocked = true;
    } catch (_) {}
    _recordCameraEvent('EXPOSURE_LOCK_DONE', details: <String, Object?>{
      'success': exposureLocked,
    });
    await Future<void>.delayed(_threeASettleDelay);
    _recordCameraEvent('THREE_A_SETTLED', details: <String, Object?>{
      'focusLocked': focusLocked,
      'exposureLocked': exposureLocked,
      'settleMilliseconds': _threeASettleDelay.inMilliseconds,
    });
    return (focusLocked: focusLocked, exposureLocked: exposureLocked);
  }

  Future<void> _unlockThreeA(CameraController controller) async {
    try {
      await controller.setFocusMode(FocusMode.auto);
    } catch (_) {}
    try {
      await controller.setExposureMode(ExposureMode.auto);
    } catch (_) {}
    _recordCameraEvent('THREE_A_UNLOCKED');
  }

  Future<_FrozenIdentityProbe> _probeFrozenIdentity(String filePath) async {
    final input = mlkit.InputImage.fromFilePath(filePath);
    final recognized = await _textRecognizer.processImage(input);
    final codes = await _barcodeScanner.processImage(input);
    final positionedLines = <LocalOcrTextLine>[
      for (final block in recognized.blocks)
        for (final line in block.lines)
          if (line.text.trim().isNotEmpty)
            LocalOcrTextLine(
              text: line.text.trim(),
              left: line.boundingBox.left,
              top: line.boundingBox.top,
              right: line.boundingBox.right,
              bottom: line.boundingBox.bottom,
            ),
    ];
    final lines = positionedLines.map((line) => line.text).toList(growable: false);
    for (final code in codes.where(
      (item) => item.format == barcode.BarcodeFormat.qrCode,
    )) {
      final payload = code.rawValue?.trim() ?? '';
      if (payload.isEmpty) continue;
      final parsed = _qrParser.parse(payload);
      final qrInvoiceNumber = parsed.invoiceNumber ?? '';
      if (parsed.canStageCandidate && qrInvoiceNumber.isNotEmpty) {
        return _FrozenIdentityProbe(
          invoiceNumber: qrInvoiceNumber,
          sellerTaxId: parsed.sellerIdentifier ?? '',
          rawLineCount: lines.length,
          hasValidQr: true,
        );
      }
    }
    final parsed = _textParser.parse(
      LocalOcrTextDocument(
        fullText: recognized.text.trim(),
        lines: List<String>.unmodifiable(lines),
        positionedLines: List<LocalOcrTextLine>.unmodifiable(positionedLines),
      ),
    );
    final taxEvidence = extractTraditionalSellerTaxIdEvidence(
      lines,
      invoiceNumber: parsed.invoiceNumber,
      positionedLines: positionedLines,
    );
    return _FrozenIdentityProbe(
      invoiceNumber: parsed.invoiceNumber ?? '',
      sellerTaxId:
          taxEvidence?.acceptedForLive == true ? taxEvidence!.value : '',
      rawLineCount: lines.length,
      hasValidQr: false,
    );
  }

  Future<void> _freeze({required bool auto}) async {
    final controller = _camera;
    if (_freezing || controller == null || !controller.value.isInitialized) {
      return;
    }
    _freezing = true;
    _captureSequence += 1;
    _recordCameraEvent('FREEZE_ARMED', details: <String, Object?>{
      'auto': auto,
      'liveInvoiceNumber': _snapshot.invoiceNumber,
      'liveSellerTaxId': _snapshot.sellerTaxId,
      'liveClassification': _snapshot.classification.name,
      'stableObservations': _snapshot.stableObservations,
      'guidanceFrameMode': _frameState.mode.name,
      'electronicWideEvidence': _electronicWideEvidenceActive,
      'traditionalExplicitTaxRequired': _traditionalExplicitTaxRequired,
    });
    if (mounted) setState(() {});
    try {
      final lock = await _lockThreeA(controller);
      _recordCameraEvent('IMAGE_STREAM_STOP_START');
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
      _recordCameraEvent('IMAGE_STREAM_STOP_DONE');
      _recordCameraEvent('TAKE_PICTURE_START', details: <String, Object?>{
        'focusLocked': lock.focusLocked,
        'exposureLocked': lock.exposureLocked,
      });
      final file = await controller.takePicture();
      _recordCameraEvent('TAKE_PICTURE_DONE', details: <String, Object?>{
        'fileName': file.name,
      });

      final frozenProbe = await _probeFrozenIdentity(file.path);
      final identityMatches = isFrozenInvoiceIdentityConsistent(
        liveInvoiceNumber: _snapshot.invoiceNumber,
        frozenInvoiceNumber: frozenProbe.invoiceNumber,
      );
      final sellerTaxMatches = !_traditionalExplicitTaxRequired ||
          (_snapshot.sellerTaxId.isNotEmpty &&
              frozenProbe.sellerTaxId == _snapshot.sellerTaxId);
      final accepted = !auto || identityMatches;
      final finalAccepted = accepted && (!auto || sellerTaxMatches);
      _recordCameraEvent('FROZEN_IDENTITY_CHECK', details: <String, Object?>{
        'auto': auto,
        'liveInvoiceNumber': _snapshot.invoiceNumber,
        'frozenInvoiceNumber': frozenProbe.invoiceNumber,
        'identityMatches': identityMatches,
        'liveSellerTaxId': _snapshot.sellerTaxId,
        'frozenSellerTaxId': frozenProbe.sellerTaxId,
        'sellerTaxMatches': sellerTaxMatches,
        'frozenRawLineCount': frozenProbe.rawLineCount,
        'frozenHasValidQr': frozenProbe.hasValidQr,
        'classificationAdvisoryOnly': true,
        'adaptiveGuidanceAffectsAcceptance': false,
        'traditionalExplicitTaxRequired': _traditionalExplicitTaxRequired,
        'accepted': finalAccepted,
      });

      if (!finalAccepted) {
        try {
          await File(file.path).delete();
        } catch (_) {}
        await _unlockThreeA(controller);
        _freezing = false;
        await _restartStream();
        if (mounted) {
          setState(() {
            _error = _traditionalExplicitTaxRequired && !sellerTaxMatches
                ? '凍結影像未重現剛才穩定的 8 碼賣方統編，已取消本次自動凍結。請讓統編區保持清晰後再試一次。'
                : '凍結影像與剛才穩定的 Live identity 不一致，已自動取消本次凍結。請保持手機與發票不動後再試一次。';
          });
        }
        return;
      }

      if (!mounted) return;
      Navigator.of(context).pop(
        InvoiceLiveCaptureResult(
          localReference: file.path,
          fileName: file.name.isNotEmpty ? file.name : path.basename(file.path),
          classification: _snapshot.classification,
          autoFrozen: auto,
          liveSnapshot: _snapshot,
          origin: InvoiceCaptureOrigin.liveCamera,
          liveHistory: List<InvoiceLiveFrameEvidence>.unmodifiable(
            <InvoiceLiveFrameEvidence>[..._history, ..._cameraEvents],
          ),
        ),
      );
    } on CameraException catch (error) {
      _recordCameraEvent('FREEZE_FAILED', details: <String, Object?>{
        'errorCode': error.code,
      });
      if (!mounted) return;
      setState(() {
        _freezing = false;
        _error = error.description ?? '凍結影像失敗。';
      });
      await _unlockThreeA(controller);
      await _restartStream();
    } catch (error) {
      _recordCameraEvent('FREEZE_FAILED', details: <String, Object?>{
        'errorType': error.runtimeType.toString(),
      });
      if (!mounted) return;
      setState(() {
        _freezing = false;
        _error = '凍結影像失敗：${error.runtimeType}';
      });
      await _unlockThreeA(controller);
      await _restartStream();
    }
  }

  Future<void> _restartStream() async {
    final controller = _camera;
    if (controller == null || !controller.value.isInitialized) return;
    if (!controller.value.isStreamingImages) {
      try {
        await controller.startImageStream(_onCameraImage);
        _recordCameraEvent('IMAGE_STREAM_RESTARTED');
      } catch (_) {}
    }
  }

  Future<void> _toggleFlash() async {
    final controller = _camera;
    if (controller == null || !controller.value.isInitialized) return;
    try {
      final next = !_flashEnabled;
      await controller.setFlashMode(next ? FlashMode.torch : FlashMode.off);
      _recordCameraEvent('FLASH_CHANGED', details: <String, Object?>{
        'enabled': next,
      });
      if (mounted) setState(() => _flashEnabled = next);
    } catch (_) {
      if (mounted) setState(() => _error = '此裝置無法切換補光燈。');
    }
  }

  void _appendHistory(InvoiceLiveFrameEvidence evidence) {
    _history.add(evidence);
    if (_history.length > _maxHistory) {
      _history.removeRange(0, _history.length - _maxHistory);
    }
  }

  double _score({
    required String invoiceNumber,
    required String invoiceDate,
    required String sellerTaxId,
    required bool hasSellerIdentityContext,
    required double? totalAmount,
    required bool hasValidLeftQr,
  }) {
    var value = 0.0;
    if (invoiceNumber.isNotEmpty) value += 0.35;
    if (sellerTaxId.isNotEmpty) {
      value += 0.35;
    } else if (hasSellerIdentityContext) {
      value += 0.25;
    }
    if (invoiceDate.isNotEmpty) value += 0.10;
    if (totalAmount != null) value += 0.10;
    if (hasValidLeftQr) value += 0.10;
    return value.clamp(0.0, 1.0);
  }

  String _guidance({
    required InvoiceLiveClassification classification,
    required String invoiceNumber,
    required String sellerTaxId,
    required bool hasSellerIdentityContext,
    required int qrCount,
    required bool hasValidLeftQr,
    required bool electronicWideEvidence,
    required bool canFreeze,
    required int stableObservations,
  }) {
    if (canFreeze && stableObservations >= 2) {
      return electronicWideEvidence
          ? '電子發票 evidence 已成立，維持寬版；欄位 identity 已跨 frame 穩定，凍結前仍會鎖定對焦與曝光並驗證 Frozen identity。'
          : '傳統發票的發票號碼＋8 碼賣方統編已跨 frame 穩定；凍結後會再次驗證兩項 identity。';
    }
    if (invoiceNumber.isEmpty) {
      return '預設以寬版尋找電子發票；請讓發票號碼與主要版面完整入框。';
    }
    if (electronicWideEvidence) {
      if (classification == InvoiceLiveClassification.electronic &&
          !hasValidLeftQr) {
        return '已取得電子發票 wide evidence；QR 可作額外高可信證據，但不要求每個 QR 都成功解碼。';
      }
      if (qrCount < 2) {
        return '已取得電子發票 wide evidence，維持寬版取景。';
      }
      return '電子發票證據完整，請保持不動等待欄位 identity 穩定。';
    }
    if (sellerTaxId.isEmpty) {
      return '未符合電子發票 wide evidence，優先切換細長取景。自動凍結必須取得發票號碼與可靠的 8 碼賣方統編；電話／地址等數字不算統編。';
    }
    if (!hasSellerIdentityContext) {
      return '已取得 8 碼統編，但商家區仍不穩定；請保持統編與發票號碼清晰。';
    }
    return stableObservations > 0
        ? '發票號碼＋賣方統編已接近門檻，請保持不動等待第二次穩定取樣。'
        : '傳統發票候選：細長取景，等待發票號碼與 8 碼賣方統編穩定。';
  }

  String _formatDate(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }

  @override
  Widget build(BuildContext context) {
    final controller = _camera;
    return Scaffold(
      appBar: AppBar(title: const Text('Live 發票辨識')),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            _TopGuidance(
              snapshot: _snapshot,
              error: _error,
              frameMode: _frameState.mode,
            ),
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
                                  _AdaptiveReceiptGuidanceOverlay(
                                    frameMode: _frameState.mode,
                                    visualOverlay: _visualOverlay,
                                  ),
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
  const _TopGuidance({
    required this.snapshot,
    required this.error,
    required this.frameMode,
  });

  final InvoiceLiveSnapshot snapshot;
  final String? error;
  final InvoiceReceiptFrameMode frameMode;

  @override
  Widget build(BuildContext context) {
    final frameLabel = frameMode == InvoiceReceiptFrameMode.wide
        ? '寬版取景'
        : '細長取景';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Chip(label: Text(snapshot.classification.label)),
              const SizedBox(width: 6),
              Chip(label: Text(frameLabel)),
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

class _AdaptiveReceiptGuidanceOverlay extends StatelessWidget {
  const _AdaptiveReceiptGuidanceOverlay({
    required this.frameMode,
    required this.visualOverlay,
  });

  final InvoiceReceiptFrameMode frameMode;
  final InvoiceLiveVisualOverlaySnapshot? visualOverlay;

  @override
  Widget build(BuildContext context) {
    final wide = frameMode == InvoiceReceiptFrameMode.wide;
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final guideWidth = constraints.maxWidth * (wide ? 0.94 : 0.72);
          final guideHeight = constraints.maxHeight * (wide ? 0.66 : 0.92);
          return Stack(
            fit: StackFit.expand,
            children: <Widget>[
              Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 320),
                  curve: Curves.easeOutCubic,
                  width: guideWidth,
                  height: guideHeight,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white70, width: 2),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: Container(
                      margin: const EdgeInsets.all(7),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        wide
                            ? '寬版取景｜電子發票 evidence 優先'
                            : '細長取景｜傳統發票優先',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (visualOverlay != null)
                CustomPaint(
                  painter: InvoiceLiveEvidencePainter(snapshot: visualOverlay!),
                ),
            ],
          );
        },
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
            title: const Text('欄位 identity 穩定後自動凍結'),
            subtitle: const Text(
              '電子發票 evidence 維持寬版；其他發票優先細長取景。傳統發票自動凍結至少需要發票號碼＋8 碼賣方統編，並保留 3A lock 與 Frozen identity Gate。',
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
                  label: Text(freezing ? '鎖定並驗證中…' : '立即凍結'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
