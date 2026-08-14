import 'dart:async';
import 'dart:io';

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
import 'invoice_live_capture_page.dart';
import 'invoice_live_field_readiness.dart';
import 'invoice_qr_parser.dart';
import 'invoice_total_evidence.dart';
import 'traditional_invoice_ocr_review.dart';

bool isFrozenInvoiceIdentityConsistent({
  required String liveInvoiceNumber,
  required String frozenInvoiceNumber,
}) {
  String normalize(String value) =>
      value.replaceAll(RegExp(r'[^A-Z0-9]'), '').toUpperCase();
  final live = normalize(liveInvoiceNumber);
  final frozen = normalize(frozenInvoiceNumber);
  return live.isNotEmpty && live == frozen;
}

InvoiceLiveClassification resolveLiveInvoiceClassification({
  required bool hasValidQr,
  required int qrPayloadCount,
  required bool hasStrongElectronicSemanticEvidence,
  required bool hasTextEvidence,
}) {
  if (hasValidQr ||
      qrPayloadCount >= 2 ||
      hasStrongElectronicSemanticEvidence) {
    return InvoiceLiveClassification.electronic;
  }
  if (hasTextEvidence) return InvoiceLiveClassification.traditional;
  return InvoiceLiveClassification.searching;
}

class InvoiceLiveCameraTelemetryEvidence extends InvoiceLiveFrameEvidence {
  const InvoiceLiveCameraTelemetryEvidence({
    required super.timestamp,
    required super.snapshot,
    required this.event,
    this.details = const <String, Object?>{},
  }) : super(
          rawLines: const <String>[],
          sellerTaxIdCandidate: '',
          sellerTaxIdSource: 'camera_telemetry',
          sellerTaxIdChecksumValid: null,
        );

  final String event;
  final Map<String, Object?> details;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
        ...super.toJson(),
        'sampleType': 'cameraTelemetry',
        'cameraEvent': event,
        'cameraDetails': details,
      };
}

class StabilizedInvoiceLiveCapturePage extends StatefulWidget {
  const StabilizedInvoiceLiveCapturePage({super.key});

  @override
  State<StabilizedInvoiceLiveCapturePage> createState() =>
      _StabilizedInvoiceLiveCapturePageState();
}

class _FrozenIdentityProbe {
  const _FrozenIdentityProbe({
    required this.invoiceNumber,
    required this.rawLineCount,
    required this.hasValidQr,
  });

  final String invoiceNumber;
  final int rawLineCount;
  final bool hasValidQr;
}

class _StabilizedInvoiceLiveCapturePageState
    extends State<StabilizedInvoiceLiveCapturePage>
    with WidgetsBindingObserver {
  static const Duration _frameInterval = Duration(milliseconds: 1200);
  static const Duration _threeASettleDelay = Duration(milliseconds: 250);
  static const int _maxHistory = 10;
  static const int _maxCameraEvents = 48;

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
  final List<InvoiceLiveFrameEvidence> _cameraEvents =
      <InvoiceLiveFrameEvidence>[];
  DateTime _lastFrameAt = DateTime.fromMillisecondsSinceEpoch(0);
  String _lastSignature = '';
  int _stableObservations = 0;
  bool _processingFrame = false;
  bool _freezing = false;
  bool _flashEnabled = false;
  bool _autoFreeze = true;
  bool _cameraInitializing = false;
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
    final plane = image.planes.first;
    return mlkit.InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: mlkit.InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: Platform.isIOS
            ? mlkit.InputImageFormat.bgra8888
            : mlkit.InputImageFormat.nv21,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  Future<void> _analyzeFrame(mlkit.InputImage image) async {
    try {
      final recognized = await _textRecognizer.processImage(image);
      final codes = await _barcodeScanner.processImage(image);
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
      final lines = positionedLines.map((line) => line.text).toList(growable: false);
      final parsedText = _textParser.parse(
        LocalOcrTextDocument(
          fullText: recognized.text.trim(),
          lines: List<String>.unmodifiable(lines),
          positionedLines: List<LocalOcrTextLine>.unmodifiable(positionedLines),
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

      final taxEvidence = extractTraditionalSellerTaxIdEvidence(
        lines,
        invoiceNumber: parsedText.invoiceNumber,
        positionedLines: positionedLines,
      );
      final semanticElectronic =
          hasStrongElectronicInvoiceSemanticEvidence(lines);
      final invoiceNumber =
          validQr?.invoiceNumber ?? parsedText.invoiceNumber ?? '';
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
      final classification = resolveLiveInvoiceClassification(
        hasValidQr: validQr != null,
        qrPayloadCount: qrPayloads.length,
        hasStrongElectronicSemanticEvidence: semanticElectronic,
        hasTextEvidence: _hasTextEvidence(parsedText),
      );
      if (semanticElectronic &&
          validQr == null &&
          _snapshot.classification != InvoiceLiveClassification.electronic) {
        _recordCameraEvent(
          'CLASSIFICATION_ELECTRONIC_SEMANTIC_FALLBACK',
          details: <String, Object?>{
            'qrPayloadCount': qrPayloads.length,
            'invoiceNumber': invoiceNumber,
            'sellerTaxIdSource': taxEvidence?.source ?? '',
          },
        );
      }
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
      final readiness = resolveInvoiceLiveFieldReadiness(
        consensus: traditionalConsensus,
        invoiceNumber: effectiveInvoiceNumber,
        sellerTaxId: sellerTaxId,
        hasSellerIdentityContext: effectiveIdentityContext,
        previousSignature: _lastSignature,
        previousConsecutiveObservations: _stableObservations,
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
          semanticElectronic: semanticElectronic,
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
          sellerTaxIdSource: validQr != null ? 'qr' : taxEvidence?.source ?? '',
          sellerTaxIdChecksumValid:
              validQr != null ? true : taxEvidence?.checksumValid,
        ),
      );
      setState(() => _snapshot = next);
      if (_autoFreeze && canFreeze && effectiveStableObservations >= 2) {
        unawaited(_freeze(auto: true));
      }
    } catch (_) {
      if (mounted && !_freezing) {
        setState(() => _error = 'Live frame 暫時無法解析，請保持發票平整並重新對焦。');
      }
    }
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
    for (final code in codes) {
      final payload = code.rawValue?.trim() ?? '';
      if (payload.isEmpty) continue;
      final parsed = _qrParser.parse(payload);
      final qrInvoiceNumber = parsed.invoiceNumber ?? '';
      if (parsed.canStageCandidate && qrInvoiceNumber.isNotEmpty) {
        return _FrozenIdentityProbe(
          invoiceNumber: qrInvoiceNumber,
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
    return _FrozenIdentityProbe(
      invoiceNumber: parsed.invoiceNumber ?? '',
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
      'liveClassification': _snapshot.classification.name,
      'stableObservations': _snapshot.stableObservations,
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
      final accepted = !auto || identityMatches;
      _recordCameraEvent('FROZEN_IDENTITY_CHECK', details: <String, Object?>{
        'auto': auto,
        'liveInvoiceNumber': _snapshot.invoiceNumber,
        'frozenInvoiceNumber': frozenProbe.invoiceNumber,
        'identityMatches': identityMatches,
        'frozenRawLineCount': frozenProbe.rawLineCount,
        'frozenHasValidQr': frozenProbe.hasValidQr,
        'classificationAdvisoryOnly': true,
        'accepted': accepted,
      });

      if (!accepted) {
        try {
          await File(file.path).delete();
        } catch (_) {}
        await _unlockThreeA(controller);
        _freezing = false;
        await _restartStream();
        if (mounted) {
          setState(() {
            _error = '凍結影像與剛才穩定的 Live identity 不一致，已自動取消本次凍結。請保持手機與發票不動後再試一次。';
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

  bool _hasTextEvidence(TraditionalInvoiceOcrRecognition recognition) {
    return (recognition.invoiceNumber?.isNotEmpty == true) ||
        (recognition.sellerTaxId?.isNotEmpty == true) ||
        recognition.invoiceDate != null ||
        recognition.sellerName?.isNotEmpty == true ||
        recognition.totalAmount != null;
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
    required bool semanticElectronic,
    required bool canFreeze,
    required int stableObservations,
  }) {
    if (canFreeze && stableObservations >= 2) {
      return '欄位 identity 已跨 frame 穩定；凍結前會鎖定對焦與曝光，再驗證 Frozen 發票號碼 identity。';
    }
    if (invoiceNumber.isEmpty) return '請讓發票號碼完整、水平且清晰地落在上方框內。';
    if (!hasSellerIdentityContext) {
      return '尚未取得賣方 identity 脈絡；請讓商家標頭、發票號碼下方統編區與 NO./統編行清晰入鏡。';
    }
    if (classification == InvoiceLiveClassification.electronic &&
        !hasValidLeftQr) {
      return semanticElectronic
          ? '已取得電子發票版面語意；QR 尚未成功解碼，但不會阻擋可見欄位辨識。請保持不動等待欄位 identity 穩定。'
          : 'QR 尚未成功解碼；系統仍以可見欄位進行辨識與凍結判定。';
    }
    if (classification == InvoiceLiveClassification.electronic && qrCount < 2) {
      return '必要欄位 identity 已取得；QR 可一併入鏡作為額外高可信證據，但不再是凍結必要條件。';
    }
    if (sellerTaxId.isEmpty) {
      return '賣方統編尚未取得可靠值；若商家 identity 脈絡已穩定，仍可先凍結後進入 Field-First 覆核。';
    }
    return stableObservations > 0
        ? '欄位 identity 已接近門檻，請保持不動等待第二次穩定取樣。'
        : '請將發票攤平並保持完整落在白色框內。';
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
                    '賣方統編／商家 identity（必要）',
                    snapshot.sellerTaxId.isNotEmpty ||
                        snapshot.hasSellerIdentityContext,
                    scheme,
                  ),
                  if (snapshot.classification ==
                      InvoiceLiveClassification.electronic) ...<Widget>[
                    _anchor(
                      size,
                      const Rect.fromLTWH(0.07, 0.66, 0.38, 0.27),
                      '左 QR（選填加強）',
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
            title: const Text('欄位 identity 穩定後自動凍結'),
            subtitle: const Text(
              '達到欄位證據門檻後先鎖定目前對焦／曝光，再拍攝 Frozen JPEG；自動凍結仍會重新驗證 Frozen 發票號碼 identity。',
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
