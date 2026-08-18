import 'dart:math' as math;
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'google_mlkit_traditional_invoice_recognizer.dart';
import 'invoice_field_first_evidence.dart';
import 'traditional_invoice_ocr_review.dart';

class TraditionalInvoiceImageVariant {
  const TraditionalInvoiceImageVariant({
    required this.label,
    required this.localReference,
  });

  final String label;
  final String localReference;
}

abstract class TraditionalInvoiceImageVariantProvider {
  Future<List<TraditionalInvoiceImageVariant>> createEnhancedVariants(
    String originalReference,
  );

  Future<void> cleanupVariants(
    List<TraditionalInvoiceImageVariant> variants,
  );
}

class FlutterTraditionalInvoiceContrastVariantProvider
    implements TraditionalInvoiceImageVariantProvider {
  const FlutterTraditionalInvoiceContrastVariantProvider();

  static const int _tileSize = 32;

  @override
  Future<List<TraditionalInvoiceImageVariant>> createEnhancedVariants(
    String originalReference,
  ) async {
    final sourceFile = File(originalReference);
    if (!await sourceFile.exists()) {
      return const <TraditionalInvoiceImageVariant>[];
    }

    ui.Codec? codec;
    ui.Image? sourceImage;
    Directory? tempDirectory;
    try {
      codec = await ui.instantiateImageCodec(await sourceFile.readAsBytes());
      final frame = await codec.getNextFrame();
      sourceImage = frame.image;
      tempDirectory = await Directory.systemTemp.createTemp(
        'my_finance_invoice_ocr_',
      );

      final rawData = await sourceImage.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      if (rawData == null) {
        throw StateError('Unable to decode OCR preprocessing pixels.');
      }
      final raw = Uint8List.fromList(
        rawData.buffer.asUint8List(
          rawData.offsetInBytes,
          rawData.lengthInBytes,
        ),
      );
      final grid = _TileLuminanceGrid.fromRgba(
        raw,
        width: sourceImage.width,
        height: sourceImage.height,
        tileSize: _tileSize,
      );

      final variants = <TraditionalInvoiceImageVariant>[];
      await _writeVariant(
        directory: tempDirectory,
        label: 'contrast_moderate',
        bytes: await _renderMatrixVariant(
          sourceImage,
          const _VariantSpec(
            contrast: 1.30,
            grayscale: false,
          ),
        ),
        variants: variants,
      );
      await _writeVariant(
        directory: tempDirectory,
        label: 'gamma_dark',
        bytes: await _encodeRgba(
          _gammaDarkGrayscale(raw, gamma: 1.28),
          width: sourceImage.width,
          height: sourceImage.height,
        ),
        variants: variants,
      );
      await _writeVariant(
        directory: tempDirectory,
        label: 'local_contrast',
        bytes: await _encodeRgba(
          _localContrast(
            raw,
            width: sourceImage.width,
            height: sourceImage.height,
            grid: grid,
          ),
          width: sourceImage.width,
          height: sourceImage.height,
        ),
        variants: variants,
      );
      await _writeVariant(
        directory: tempDirectory,
        label: 'adaptive_threshold',
        bytes: await _encodeRgba(
          _adaptiveThreshold(
            raw,
            width: sourceImage.width,
            height: sourceImage.height,
            grid: grid,
          ),
          width: sourceImage.width,
          height: sourceImage.height,
        ),
        variants: variants,
      );
      return List<TraditionalInvoiceImageVariant>.unmodifiable(variants);
    } catch (_) {
      if (tempDirectory != null) {
        try {
          await tempDirectory.delete(recursive: true);
        } catch (_) {}
      }
      return const <TraditionalInvoiceImageVariant>[];
    } finally {
      sourceImage?.dispose();
      codec?.dispose();
    }
  }

  Future<void> _writeVariant({
    required Directory directory,
    required String label,
    required Uint8List bytes,
    required List<TraditionalInvoiceImageVariant> variants,
  }) async {
    final file = File('${directory.path}/$label.png');
    await file.writeAsBytes(bytes, flush: true);
    variants.add(
      TraditionalInvoiceImageVariant(
        label: label,
        localReference: file.path,
      ),
    );
  }

  @override
  Future<void> cleanupVariants(
    List<TraditionalInvoiceImageVariant> variants,
  ) async {
    final parents = variants
        .map((variant) => File(variant.localReference).parent.path)
        .toSet();
    for (final path in parents) {
      final directory = Directory(path);
      if (!directory.path.contains('my_finance_invoice_ocr_')) continue;
      try {
        if (await directory.exists()) {
          await directory.delete(recursive: true);
        }
      } catch (_) {}
    }
  }

  Future<Uint8List> _renderMatrixVariant(
    ui.Image source,
    _VariantSpec spec,
  ) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, source.width.toDouble(), source.height.toDouble()),
      ui.Paint()..color = const ui.Color(0xFFFFFFFF),
    );
    canvas.drawImage(
      source,
      ui.Offset.zero,
      ui.Paint()..colorFilter = ui.ColorFilter.matrix(spec.colorMatrix),
    );
    final picture = recorder.endRecording();
    final output = await picture.toImage(source.width, source.height);
    try {
      final byteData = await output.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        throw StateError('Unable to encode OCR preprocessing variant.');
      }
      return byteData.buffer.asUint8List(
        byteData.offsetInBytes,
        byteData.lengthInBytes,
      );
    } finally {
      output.dispose();
    }
  }

  Uint8List _gammaDarkGrayscale(
    Uint8List raw, {
    required double gamma,
  }) {
    final lut = Uint8List(256);
    for (var value = 0; value < 256; value += 1) {
      lut[value] = _byte(
        math.pow(value / 255.0, gamma).toDouble() * 255.0,
      );
    }
    final output = Uint8List(raw.length);
    for (var index = 0; index < raw.length; index += 4) {
      final lum = _luminance(raw[index], raw[index + 1], raw[index + 2]);
      final adjusted = lut[lum];
      output[index] = adjusted;
      output[index + 1] = adjusted;
      output[index + 2] = adjusted;
      output[index + 3] = raw[index + 3];
    }
    return output;
  }

  Uint8List _localContrast(
    Uint8List raw, {
    required int width,
    required int height,
    required _TileLuminanceGrid grid,
  }) {
    final output = Uint8List(raw.length);
    for (var y = 0; y < height; y += 1) {
      for (var x = 0; x < width; x += 1) {
        final index = (y * width + x) * 4;
        final lum = _luminance(raw[index], raw[index + 1], raw[index + 2]);
        final mean = grid.meanAt(x, y);
        final adjusted = _byte(230.0 + (lum - mean) * 1.85);
        output[index] = adjusted;
        output[index + 1] = adjusted;
        output[index + 2] = adjusted;
        output[index + 3] = raw[index + 3];
      }
    }
    return output;
  }

  Uint8List _adaptiveThreshold(
    Uint8List raw, {
    required int width,
    required int height,
    required _TileLuminanceGrid grid,
  }) {
    final output = Uint8List(raw.length);
    for (var y = 0; y < height; y += 1) {
      for (var x = 0; x < width; x += 1) {
        final index = (y * width + x) * 4;
        final lum = _luminance(raw[index], raw[index + 1], raw[index + 2]);
        final threshold = grid.meanAt(x, y) - 14.0;
        final adjusted = lum < threshold ? 0 : 255;
        output[index] = adjusted;
        output[index + 1] = adjusted;
        output[index + 2] = adjusted;
        output[index + 3] = raw[index + 3];
      }
    }
    return output;
  }

  Future<Uint8List> _encodeRgba(
    Uint8List rgba, {
    required int width,
    required int height,
  }) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(rgba);
    final descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: width,
      height: height,
      rowBytes: width * 4,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    final codec = await descriptor.instantiateCodec();
    ui.Image? image;
    try {
      final frame = await codec.getNextFrame();
      image = frame.image;
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        throw StateError('Unable to encode adaptive OCR variant.');
      }
      return Uint8List.fromList(
        byteData.buffer.asUint8List(
          byteData.offsetInBytes,
          byteData.lengthInBytes,
        ),
      );
    } finally {
      image?.dispose();
      codec.dispose();
      descriptor.dispose();
      buffer.dispose();
    }
  }

  int _luminance(int red, int green, int blue) =>
      (77 * red + 150 * green + 29 * blue) >> 8;

  int _byte(double value) {
    if (value <= 0) return 0;
    if (value >= 255) return 255;
    return value.round();
  }
}

class _TileLuminanceGrid {
  _TileLuminanceGrid({
    required this.tileSize,
    required this.columns,
    required this.means,
  });

  factory _TileLuminanceGrid.fromRgba(
    Uint8List raw, {
    required int width,
    required int height,
    required int tileSize,
  }) {
    final columns = (width + tileSize - 1) ~/ tileSize;
    final rows = (height + tileSize - 1) ~/ tileSize;
    final sums = Uint32List(columns * rows);
    final counts = Uint32List(columns * rows);
    for (var y = 0; y < height; y += 1) {
      for (var x = 0; x < width; x += 1) {
        final pixel = (y * width + x) * 4;
        final lum =
            (77 * raw[pixel] + 150 * raw[pixel + 1] + 29 * raw[pixel + 2]) >>
                8;
        final tile = (y ~/ tileSize) * columns + (x ~/ tileSize);
        sums[tile] += lum;
        counts[tile] += 1;
      }
    }
    final means = Float64List(columns * rows);
    for (var index = 0; index < means.length; index += 1) {
      means[index] = counts[index] == 0 ? 255.0 : sums[index] / counts[index];
    }
    return _TileLuminanceGrid(
      tileSize: tileSize,
      columns: columns,
      means: means,
    );
  }

  final int tileSize;
  final int columns;
  final Float64List means;

  double meanAt(int x, int y) =>
      means[(y ~/ tileSize) * columns + (x ~/ tileSize)];
}

class _VariantSpec {
  const _VariantSpec({
    required this.contrast,
    required this.grayscale,
  });

  final double contrast;
  final bool grayscale;

  List<double> get colorMatrix {
    final offset = 128.0 * (1.0 - contrast);
    if (!grayscale) {
      return <double>[
        contrast, 0, 0, 0, offset,
        0, contrast, 0, 0, offset,
        0, 0, contrast, 0, offset,
        0, 0, 0, 1, 0,
      ];
    }
    final r = 0.2126 * contrast;
    final g = 0.7152 * contrast;
    final b = 0.0722 * contrast;
    return <double>[
      r, g, b, 0, offset,
      r, g, b, 0, offset,
      r, g, b, 0, offset,
      0, 0, 0, 1, 0,
    ];
  }
}

class GoogleMlKitMultiVariantTraditionalInvoiceRecognizer
    implements LocalTraditionalInvoiceRecognizer {
  const GoogleMlKitMultiVariantTraditionalInvoiceRecognizer({
    this.engine = const GoogleMlKitChineseTextEngine(),
    this.parser = const TraditionalInvoiceTextParser(),
    this.variantProvider =
        const FlutterTraditionalInvoiceContrastVariantProvider(),
  });

  final LocalOcrTextEngine engine;
  final TraditionalInvoiceTextParser parser;
  final TraditionalInvoiceImageVariantProvider variantProvider;

  @override
  Future<TraditionalInvoiceOcrRecognition> recognizeLocalImage(
    String localReference,
  ) async {
    final reference = localReference.trim();
    if (reference.isEmpty) {
      throw ArgumentError.value(localReference, 'localReference');
    }

    final baseRecognizer = GoogleMlKitTraditionalInvoiceRecognizer(
      engine: engine,
      parser: parser,
    );
    final original = await baseRecognizer.recognizeLocalImage(reference);
    if (!_shouldTryEnhancedVariants(original)) return original;

    final variants = await variantProvider.createEnhancedVariants(reference);
    if (variants.isEmpty) return original;

    final enhanced = <_VariantRecognition>[];
    try {
      for (final variant in variants) {
        try {
          enhanced.add(
            _VariantRecognition(
              label: variant.label,
              recognition: await baseRecognizer.recognizeLocalImage(
                variant.localReference,
              ),
            ),
          );
        } catch (_) {
          // Enhancement is optional. One bad derivative must never destroy the
          // original Frozen OCR result.
        }
      }
      final diagnostics = <TraditionalInvoiceOcrVariantDiagnostic>[
        _diagnostic('original', original),
        for (final item in enhanced) _diagnostic(item.label, item.recognition),
      ];
      if (enhanced.length < 2) {
        return _withDiagnostics(original, diagnostics);
      }
      return _mergeVariantConsensus(original, enhanced, diagnostics);
    } finally {
      await variantProvider.cleanupVariants(variants);
    }
  }

  bool _shouldTryEnhancedVariants(TraditionalInvoiceOcrRecognition original) {
    if (hasStrongElectronicInvoiceSemanticEvidence(original.rawLines)) {
      return false;
    }
    return (original.invoiceNumber?.trim().isEmpty ?? true) ||
        (original.sellerTaxId?.trim().isEmpty ?? true) ||
        original.invoiceDate == null ||
        (original.sellerName?.trim().isEmpty ?? true) ||
        original.totalAmount == null ||
        _extractStrictTime(original.rawText).isEmpty;
  }

  TraditionalInvoiceOcrRecognition _mergeVariantConsensus(
    TraditionalInvoiceOcrRecognition original,
    List<_VariantRecognition> enhanced,
    List<TraditionalInvoiceOcrVariantDiagnostic> diagnostics,
  ) {
    final confidence = <TraditionalInvoiceOcrField,
        TraditionalInvoiceOcrConfidence>{...original.confidence};
    final warnings = <TraditionalInvoiceOcrField, List<String>>{
      for (final entry in original.fieldWarnings.entries)
        entry.key: List<String>.from(entry.value),
    };

    var invoiceNumber = original.invoiceNumber?.trim() ?? '';
    final invoiceConsensus = _stringConsensus(
      enhanced,
      (item) => item.recognition.invoiceNumber ?? '',
      _normalizeInvoiceNumber,
    );
    if (invoiceConsensus != null) {
      if (invoiceNumber.isEmpty) {
        invoiceNumber = invoiceConsensus;
        confidence[TraditionalInvoiceOcrField.invoiceNumber] =
            TraditionalInvoiceOcrConfidence.medium;
        warnings[TraditionalInvoiceOcrField.invoiceNumber] = const <String>[
          'P4.18.6：原圖未辨識發票號碼；至少 2 個本機影像增強版本 exact consensus 後補入人工覆核候選。',
        ];
      } else if (_normalizeInvoiceNumber(invoiceNumber) !=
          _normalizeInvoiceNumber(invoiceConsensus)) {
        invoiceNumber = '';
        confidence[TraditionalInvoiceOcrField.invoiceNumber] =
            TraditionalInvoiceOcrConfidence.low;
        warnings[TraditionalInvoiceOcrField.invoiceNumber] = const <String>[
          'P4.18.6：原圖與影像增強版本的發票號碼衝突，已 fail-closed 保持空白。',
        ];
      }
    }

    var sellerTaxId = original.sellerTaxId?.trim() ?? '';
    var sellerTaxIdSource = original.sellerTaxIdSource;
    final sellerTaxConsensus = _stringConsensus(
      enhanced.where((item) {
        return item.recognition.sellerTaxIdSource == 'explicit_label';
      }).toList(growable: false),
      (item) => item.recognition.sellerTaxId ?? '',
      (value) => value.replaceAll(RegExp(r'[^0-9]'), ''),
    );
    if (sellerTaxConsensus != null) {
      if (sellerTaxId.isEmpty) {
        sellerTaxId = sellerTaxConsensus;
        sellerTaxIdSource = 'multi_variant_explicit_label_consensus';
        confidence[TraditionalInvoiceOcrField.sellerTaxId] =
            TraditionalInvoiceOcrConfidence.medium;
        warnings[TraditionalInvoiceOcrField.sellerTaxId] = const <String>[
          'P4.18.6：至少 2 個影像增強版本皆從明確統編標籤解析到相同值；仍只建立人工覆核候選。',
        ];
      } else if (sellerTaxId != sellerTaxConsensus) {
        sellerTaxId = '';
        sellerTaxIdSource = '';
        confidence[TraditionalInvoiceOcrField.sellerTaxId] =
            TraditionalInvoiceOcrConfidence.low;
        warnings[TraditionalInvoiceOcrField.sellerTaxId] = const <String>[
          'P4.18.6：原圖與增強版本的賣方統編衝突，已 fail-closed 保持空白。',
        ];
      }
    }

    var invoiceDate = original.invoiceDate;
    final dateConsensus = _dateConsensus(enhanced);
    if (dateConsensus != null) {
      if (invoiceDate == null) {
        invoiceDate = dateConsensus;
        confidence[TraditionalInvoiceOcrField.invoiceDate] =
            TraditionalInvoiceOcrConfidence.medium;
        warnings[TraditionalInvoiceOcrField.invoiceDate] = const <String>[
          'P4.18.6：原圖缺少日期；至少 2 個影像增強版本 exact consensus 後補入人工覆核候選。',
        ];
      } else if (!_sameDate(invoiceDate, dateConsensus)) {
        invoiceDate = null;
        confidence[TraditionalInvoiceOcrField.invoiceDate] =
            TraditionalInvoiceOcrConfidence.low;
        warnings[TraditionalInvoiceOcrField.invoiceDate] = const <String>[
          'P4.18.6：原圖與影像增強版本日期衝突，已 fail-closed 保持空白。',
        ];
      }
    }

    var sellerName = original.sellerName?.trim() ?? '';
    final sellerNameConsensus = _stringConsensus(
      enhanced,
      (item) => item.recognition.sellerName ?? '',
      _normalizeMerchantName,
    );
    if (sellerNameConsensus != null) {
      if (sellerName.isEmpty) {
        sellerName = sellerNameConsensus;
        confidence[TraditionalInvoiceOcrField.sellerName] =
            TraditionalInvoiceOcrConfidence.medium;
        warnings[TraditionalInvoiceOcrField.sellerName] = const <String>[
          'P4.18.6：原圖缺少商家名稱；至少 2 個影像增強版本 exact consensus 後補入人工覆核候選。',
        ];
      } else if (_normalizeMerchantName(sellerName) !=
          _normalizeMerchantName(sellerNameConsensus)) {
        sellerName = sellerNameConsensus;
        confidence[TraditionalInvoiceOcrField.sellerName] =
            TraditionalInvoiceOcrConfidence.medium;
        warnings[TraditionalInvoiceOcrField.sellerName] = const <String>[
          'P4.18.6：至少 2 個影像增強版本對商家名稱形成一致結果，與原圖 OCR 不同；已採增強共識作為 Review-only 候選，仍需人工確認。',
        ];
      }
    }

    var totalAmount = original.totalAmount;
    var totalDecisionLock = '';
    final totalConsensus = _amountConsensus(enhanced);
    if (totalConsensus != null) {
      if (totalAmount == null) {
        totalAmount = totalConsensus;
        totalDecisionLock = 'CONSENSUS';
        confidence[TraditionalInvoiceOcrField.totalAmount] =
            TraditionalInvoiceOcrConfidence.medium;
        warnings[TraditionalInvoiceOcrField.totalAmount] = const <String>[
          'P4.18.6_MULTI_VARIANT_TOTAL_CONSENSUS：原圖缺少總額；至少 2 個影像增強版本 exact consensus 後補入人工覆核候選。',
        ];
      } else if (!_sameAmount(totalAmount, totalConsensus)) {
        totalAmount = null;
        totalDecisionLock = 'CONFLICT';
        confidence[TraditionalInvoiceOcrField.totalAmount] =
            TraditionalInvoiceOcrConfidence.low;
        warnings[TraditionalInvoiceOcrField.totalAmount] = const <String>[
          'P4.18.6_MULTI_VARIANT_TOTAL_CONFLICT：原圖與影像增強版本總額衝突，已 fail-closed 保持空白。',
        ];
      }
    }

    final rawLines = List<String>.from(original.rawLines);
    final markers = <String>[];
    if (totalDecisionLock.isNotEmpty) {
      final marker = 'P4_18_5_TOTAL_DECISION_LOCK=$totalDecisionLock';
      rawLines.add(marker);
      markers.add(marker);
    }
    final originalPeriod = parseInvoiceFieldFirstEvidence(
      original.rawLines,
    ).invoicePeriod;
    final periodConsensus = _periodConsensus(enhanced);
    if (originalPeriod.isEmpty && periodConsensus.isNotEmpty) {
      final marker = 'P4_18_5_INVOICE_PERIOD=$periodConsensus';
      rawLines.add(marker);
      markers.add(marker);
    }
    final originalTime = _extractStrictTime(original.rawText);
    final timeConsensus = _timeConsensus(enhanced);
    if (originalTime.isEmpty && timeConsensus.isNotEmpty) {
      final marker = 'P4_18_5_EXACT_TIME=$timeConsensus';
      rawLines.add(marker);
      markers.add(marker);
    }

    final rawText = <String>[
      if (original.rawText.trim().isNotEmpty) original.rawText.trim(),
      ...markers,
    ].join('\n');

    return TraditionalInvoiceOcrRecognition(
      invoiceNumber: invoiceNumber.isEmpty ? null : invoiceNumber,
      sellerTaxId: sellerTaxId.isEmpty ? null : sellerTaxId,
      sellerTaxIdSource: sellerTaxIdSource,
      invoiceDate: invoiceDate,
      sellerName: sellerName.isEmpty ? null : sellerName,
      totalAmount: totalAmount,
      visibleLineItems: original.visibleLineItems,
      confidence: Map<TraditionalInvoiceOcrField,
          TraditionalInvoiceOcrConfidence>.unmodifiable(confidence),
      fieldWarnings: Map<TraditionalInvoiceOcrField, List<String>>.unmodifiable(
        warnings.map(
          (key, value) => MapEntry(key, List<String>.unmodifiable(value)),
        ),
      ),
      variantDiagnostics:
          List<TraditionalInvoiceOcrVariantDiagnostic>.unmodifiable(diagnostics),
      rawText: rawText,
      rawLines: List<String>.unmodifiable(rawLines),
    );
  }

  TraditionalInvoiceOcrRecognition _withDiagnostics(
    TraditionalInvoiceOcrRecognition source,
    List<TraditionalInvoiceOcrVariantDiagnostic> diagnostics,
  ) {
    return TraditionalInvoiceOcrRecognition(
      invoiceNumber: source.invoiceNumber,
      sellerTaxId: source.sellerTaxId,
      sellerTaxIdSource: source.sellerTaxIdSource,
      invoiceDate: source.invoiceDate,
      sellerName: source.sellerName,
      totalAmount: source.totalAmount,
      visibleLineItems: source.visibleLineItems,
      confidence: source.confidence,
      fieldWarnings: source.fieldWarnings,
      variantDiagnostics:
          List<TraditionalInvoiceOcrVariantDiagnostic>.unmodifiable(diagnostics),
      rawText: source.rawText,
      rawLines: source.rawLines,
    );
  }

  TraditionalInvoiceOcrVariantDiagnostic _diagnostic(
    String label,
    TraditionalInvoiceOcrRecognition recognition,
  ) {
    return TraditionalInvoiceOcrVariantDiagnostic(
      label: label,
      invoiceNumber: recognition.invoiceNumber?.trim() ?? '',
      sellerTaxId: recognition.sellerTaxId?.trim() ?? '',
      sellerTaxIdSource: recognition.sellerTaxIdSource,
      invoiceDate: recognition.invoiceDate,
      sellerName: recognition.sellerName?.trim() ?? '',
      totalAmount: recognition.totalAmount,
      invoicePeriod:
          parseInvoiceFieldFirstEvidence(recognition.rawLines).invoicePeriod,
      invoiceTime: _extractStrictTime(recognition.rawText),
    );
  }

  String? _stringConsensus(
    List<_VariantRecognition> enhanced,
    String Function(_VariantRecognition item) valueOf,
    String Function(String value) normalize,
  ) {
    final votes = <String, List<String>>{};
    for (final item in enhanced) {
      final value = valueOf(item).trim();
      if (value.isEmpty) continue;
      final key = normalize(value);
      if (key.isEmpty) continue;
      votes.putIfAbsent(key, () => <String>[]).add(value);
    }
    final winners = votes.entries
        .where((entry) => entry.value.length >= 2)
        .toList(growable: false);
    if (winners.length != 1) return null;
    return winners.single.value.first;
  }

  DateTime? _dateConsensus(List<_VariantRecognition> enhanced) {
    final votes = <String, List<DateTime>>{};
    for (final item in enhanced) {
      final value = item.recognition.invoiceDate;
      if (value == null) continue;
      final key = _dateKey(value);
      votes.putIfAbsent(key, () => <DateTime>[]).add(value);
    }
    final winners = votes.entries
        .where((entry) => entry.value.length >= 2)
        .toList(growable: false);
    if (winners.length != 1) return null;
    return winners.single.value.first;
  }

  double? _amountConsensus(List<_VariantRecognition> enhanced) {
    final votes = <int, List<double>>{};
    for (final item in enhanced) {
      final value = item.recognition.totalAmount;
      if (value == null || !value.isFinite || value < 0) continue;
      final key = (value * 100).round();
      votes.putIfAbsent(key, () => <double>[]).add(value);
    }
    final winners = votes.entries
        .where((entry) => entry.value.length >= 2)
        .toList(growable: false);
    if (winners.length != 1) return null;
    return winners.single.value.first;
  }

  String _periodConsensus(List<_VariantRecognition> enhanced) {
    return _stringConsensus(
          enhanced,
          (item) => parseInvoiceFieldFirstEvidence(
            item.recognition.rawLines,
          ).invoicePeriod,
          (value) => value.replaceAll(RegExp(r'\s+'), ''),
        ) ??
        '';
  }

  String _timeConsensus(List<_VariantRecognition> enhanced) {
    return _stringConsensus(
          enhanced,
          (item) => _extractStrictTime(item.recognition.rawText),
          (value) => value,
        ) ??
        '';
  }

  String _extractStrictTime(String rawText) {
    final matches = RegExp(
      r'(?:^|[^0-9])((?:[01]\d|2[0-3]):[0-5]\d(?::[0-5]\d)?)(?!\d)',
      multiLine: true,
    ).allMatches(rawText);
    final values = <String>{};
    for (final match in matches) {
      final value = match.group(1);
      if (value != null && value.isNotEmpty) values.add(value);
    }
    return values.length == 1 ? values.single : '';
  }

  String _normalizeInvoiceNumber(String value) => value
      .replaceAll(RegExp(r'[^A-Za-z0-9]'), '')
      .toUpperCase();

  String _normalizeMerchantName(String value) =>
      value.replaceAll(RegExp(r'\s+'), '').trim();

  bool _sameDate(DateTime left, DateTime right) =>
      left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;

  String _dateKey(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  bool _sameAmount(double left, double right) =>
      (left * 100).round() == (right * 100).round();
}

class _VariantRecognition {
  const _VariantRecognition({
    required this.label,
    required this.recognition,
  });

  final String label;
  final TraditionalInvoiceOcrRecognition recognition;
}
