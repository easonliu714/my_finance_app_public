import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';

enum InvoiceReceiptFrameMode { wide, narrowTall }

enum InvoiceReceiptGeometrySignal { wide, narrowTall, uncertain }

enum InvoiceLiveVisualEvidenceKind { invoiceNumber, sellerTaxId, qr, barcode }

class InvoiceOcrVisualLine {
  const InvoiceOcrVisualLine({required this.text, required this.imageRect});

  final String text;
  final Rect imageRect;
}

class InvoiceLiveVisualEvidence {
  const InvoiceLiveVisualEvidence({
    required this.kind,
    required this.imageRect,
    required this.label,
    required this.accepted,
  });

  final InvoiceLiveVisualEvidenceKind kind;
  final Rect imageRect;
  final String label;
  final bool accepted;
}

/// Strong layout evidence that the current receipt should keep the wide guide.
///
/// P4.17.2 deliberately derives this from concrete evidence around an observed
/// invoice number instead of the advisory electronic/traditional classifier.
class InvoiceElectronicWideEvidence {
  const InvoiceElectronicWideEvidence({
    required this.invoiceNumberInsideGuide,
    required this.qrCountInsideGuide,
    required this.hasElectronicInvoiceHeaderAbove,
    required this.hasRandomCodeBelow,
    required this.hasOneDimensionalBarcodeInsideGuide,
  });

  final bool invoiceNumberInsideGuide;
  final int qrCountInsideGuide;
  final bool hasElectronicInvoiceHeaderAbove;
  final bool hasRandomCodeBelow;
  final bool hasOneDimensionalBarcodeInsideGuide;

  bool get keepWide =>
      invoiceNumberInsideGuide &&
      (qrCountInsideGuide >= 2 ||
          hasElectronicInvoiceHeaderAbove ||
          hasRandomCodeBelow ||
          hasOneDimensionalBarcodeInsideGuide);

  List<String> get reasons => <String>[
        if (invoiceNumberInsideGuide && qrCountInsideGuide >= 2)
          'invoice_plus_two_qr',
        if (invoiceNumberInsideGuide && hasElectronicInvoiceHeaderAbove)
          'electronic_invoice_header_above',
        if (invoiceNumberInsideGuide && hasRandomCodeBelow)
          'random_code_below',
        if (invoiceNumberInsideGuide && hasOneDimensionalBarcodeInsideGuide)
          'invoice_plus_barcode',
      ];
}

/// Visual-only candidate used to show where OCR is looking for a seller tax ID.
///
/// This type intentionally carries no accepted/authoritative seller-tax value.
/// It must never participate in readiness, consensus, Frozen acceptance or a
/// formal write. It only supplies a bounding box for the amber overlay.
class InvoiceSellerTaxVisualCandidate {
  const InvoiceSellerTaxVisualCandidate({
    required this.rawText,
    required this.imageRect,
  });

  final String rawText;
  final Rect imageRect;
}


/// Non-authoritative seller-tax structure evidence used only to decide
/// whether a high-resolution still image is worth capturing.
///
/// This evidence never authorizes a seller-tax value. Checksum-valid
/// seller tax admission remains exclusively in TraditionalSellerTaxIdEvidence.
class InvoiceSellerTaxStructuralEvidence {
  const InvoiceSellerTaxStructuralEvidence({
    required this.rawText,
    required this.imageRect,
    required this.source,
  });

  final String rawText;
  final Rect imageRect;
  final String source;
}

class InvoiceReceiptGeometryObservation {
  const InvoiceReceiptGeometryObservation({
    required this.signal,
    required this.evidenceCount,
    required this.sourceEvidenceCount,
    required this.heightToWidthRatio,
    required this.medianEvidenceWidth,
    required this.normalizedEnvelope,
    required this.anchorApplied,
  });

  final InvoiceReceiptGeometrySignal signal;
  final int evidenceCount;
  final int sourceEvidenceCount;
  final double? heightToWidthRatio;
  final double? medianEvidenceWidth;
  final Rect? normalizedEnvelope;
  final bool anchorApplied;
}

class InvoiceAdaptiveFrameState {
  const InvoiceAdaptiveFrameState({
    required this.mode,
    required this.narrowTallStreak,
    required this.wideStreak,
  });

  const InvoiceAdaptiveFrameState.initial()
      : mode = InvoiceReceiptFrameMode.wide,
        narrowTallStreak = 0,
        wideStreak = 0;

  final InvoiceReceiptFrameMode mode;
  final int narrowTallStreak;
  final int wideStreak;

  InvoiceAdaptiveFrameState advance(
    InvoiceReceiptGeometrySignal signal, {
    int switchThreshold = 2,
  }) {
    switch (signal) {
      case InvoiceReceiptGeometrySignal.narrowTall:
        final nextNarrow = narrowTallStreak + 1;
        return InvoiceAdaptiveFrameState(
          mode: nextNarrow >= switchThreshold
              ? InvoiceReceiptFrameMode.narrowTall
              : mode,
          narrowTallStreak: nextNarrow,
          wideStreak: 0,
        );
      case InvoiceReceiptGeometrySignal.wide:
        final nextWide = wideStreak + 1;
        return InvoiceAdaptiveFrameState(
          mode: nextWide >= switchThreshold ? InvoiceReceiptFrameMode.wide : mode,
          narrowTallStreak: 0,
          wideStreak: nextWide,
        );
      case InvoiceReceiptGeometrySignal.uncertain:
        return InvoiceAdaptiveFrameState(
          mode: mode,
          narrowTallStreak: 0,
          wideStreak: 0,
        );
    }
  }

  InvoiceAdaptiveFrameState advanceForReceiptIntent({
    required bool invoiceNumberObserved,
    required bool electronicWideEvidence,
  }) {
    if (electronicWideEvidence) {
      return const InvoiceAdaptiveFrameState(
        mode: InvoiceReceiptFrameMode.wide,
        narrowTallStreak: 0,
        wideStreak: 0,
      );
    }
    if (!invoiceNumberObserved) {
      return InvoiceAdaptiveFrameState(
        mode: mode,
        narrowTallStreak: 0,
        wideStreak: 0,
      );
    }
    return advance(InvoiceReceiptGeometrySignal.narrowTall);
  }
}

class InvoiceLiveVisualOverlaySnapshot {
  const InvoiceLiveVisualOverlaySnapshot({
    required this.imageSize,
    required this.rotation,
    required this.lensDirection,
    required this.evidence,
    required this.geometry,
  });

  final Size imageSize;
  final InputImageRotation rotation;
  final CameraLensDirection lensDirection;
  final List<InvoiceLiveVisualEvidence> evidence;
  final InvoiceReceiptGeometryObservation geometry;
}

InvoiceElectronicWideEvidence resolveInvoiceElectronicWideEvidence({
  required List<InvoiceOcrVisualLine> lines,
  required Rect? invoiceNumberRect,
  required List<Rect> qrRects,
  required List<Rect> barcodeRects,
  required Size imageSize,
  required InputImageRotation rotation,
  required CameraLensDirection lensDirection,
  bool? isIos,
}) {
  if (invoiceNumberRect == null || imageSize.width <= 0 || imageSize.height <= 0) {
    return const InvoiceElectronicWideEvidence(
      invoiceNumberInsideGuide: false,
      qrCountInsideGuide: 0,
      hasElectronicInvoiceHeaderAbove: false,
      hasRandomCodeBelow: false,
      hasOneDimensionalBarcodeInsideGuide: false,
    );
  }

  const normalizedCanvas = Size(1, 1);
  const wideGuide = Rect.fromLTRB(0.03, 0.17, 0.97, 0.83);
  Rect normalized(Rect source) => _clipNormalizedRect(
        translateInvoiceEvidenceRect(
          source,
          canvasSize: normalizedCanvas,
          imageSize: imageSize,
          rotation: rotation,
          lensDirection: lensDirection,
          isIos: isIos,
        ),
      );

  final invoice = normalized(invoiceNumberRect);
  final invoiceInside =
      invoice.width > 0 && invoice.height > 0 && wideGuide.contains(invoice.center);
  if (!invoiceInside) {
    return const InvoiceElectronicWideEvidence(
      invoiceNumberInsideGuide: false,
      qrCountInsideGuide: 0,
      hasElectronicInvoiceHeaderAbove: false,
      hasRandomCodeBelow: false,
      hasOneDimensionalBarcodeInsideGuide: false,
    );
  }

  final qrCount = qrRects
      .map(normalized)
      .where((rect) => rect.width > 0 && wideGuide.contains(rect.center))
      .length;
  final barcodeInside = barcodeRects
      .map(normalized)
      .any((rect) => rect.width > 0 && wideGuide.contains(rect.center));

  final electronicHeader = RegExp(r'電子\s*發票\s*證明聯');
  final randomCode = RegExp(r'隨機\s*碼');
  var headerAbove = false;
  var randomBelow = false;
  for (final line in lines) {
    final rect = normalized(line.imageRect);
    if (rect.width <= 0 || rect.height <= 0 || !wideGuide.contains(rect.center)) {
      continue;
    }
    final horizontalDistance = (rect.center.dx - invoice.center.dx).abs();
    if (horizontalDistance > 0.34) continue;
    if (electronicHeader.hasMatch(line.text) &&
        rect.center.dy < invoice.center.dy &&
        invoice.top - rect.bottom <= 0.28) {
      headerAbove = true;
    }
    if (randomCode.hasMatch(line.text) &&
        rect.center.dy > invoice.center.dy &&
        rect.top - invoice.bottom <= 0.34) {
      randomBelow = true;
    }
  }

  return InvoiceElectronicWideEvidence(
    invoiceNumberInsideGuide: true,
    qrCountInsideGuide: qrCount,
    hasElectronicInvoiceHeaderAbove: headerAbove,
    hasRandomCodeBelow: randomBelow,
    hasOneDimensionalBarcodeInsideGuide: barcodeInside,
  );
}

InvoiceReceiptGeometryObservation observeInvoiceReceiptGeometry({
  required Size imageSize,
  required InputImageRotation rotation,
  required CameraLensDirection lensDirection,
  required List<Rect> evidenceRects,
  Rect? anchorRect,
  bool? isIos,
}) {
  if (imageSize.width <= 0 || imageSize.height <= 0 || evidenceRects.length < 3) {
    return const InvoiceReceiptGeometryObservation(
      signal: InvoiceReceiptGeometrySignal.uncertain,
      evidenceCount: 0,
      sourceEvidenceCount: 0,
      heightToWidthRatio: null,
      medianEvidenceWidth: null,
      normalizedEnvelope: null,
      anchorApplied: false,
    );
  }

  const canvas = Size(1, 1);
  final translated = <Rect>[
    for (final rect in evidenceRects)
      _clipNormalizedRect(
        translateInvoiceEvidenceRect(
          rect,
          canvasSize: canvas,
          imageSize: imageSize,
          rotation: rotation,
          lensDirection: lensDirection,
          isIos: isIos,
        ),
      ),
  ].where((rect) => rect.width > 0 && rect.height > 0).toList(growable: false);

  if (translated.length < 3) {
    return InvoiceReceiptGeometryObservation(
      signal: InvoiceReceiptGeometrySignal.uncertain,
      evidenceCount: translated.length,
      sourceEvidenceCount: translated.length,
      heightToWidthRatio: null,
      medianEvidenceWidth: null,
      normalizedEnvelope: null,
      anchorApplied: false,
    );
  }

  var retained = translated;
  var anchorApplied = false;
  if (anchorRect != null) {
    final anchor = _clipNormalizedRect(
      translateInvoiceEvidenceRect(
        anchorRect,
        canvasSize: canvas,
        imageSize: imageSize,
        rotation: rotation,
        lensDirection: lensDirection,
        isIos: isIos,
      ),
    );
    if (anchor.width > 0 && anchor.height > 0) {
      final horizontalTolerance =
          (0.22 + anchor.width * 0.35).clamp(0.30, 0.38).toDouble();
      final anchored = translated.where((rect) {
        final centerXDistance = (rect.center.dx - anchor.center.dx).abs();
        final centerY = rect.center.dy;
        return centerXDistance <= horizontalTolerance &&
            centerY >= anchor.top - 0.32 &&
            centerY <= anchor.bottom + 0.72;
      }).toList(growable: false);
      if (anchored.length >= 3) {
        retained = anchored;
        anchorApplied = true;
      }
    }
  }

  var envelope = retained.first;
  for (final rect in retained.skip(1)) {
    envelope = envelope.expandToInclude(rect);
  }
  final width = envelope.width.abs();
  final height = envelope.height.abs();
  final medianWidth = _median(
    retained.map((rect) => rect.width.abs()).toList(growable: false),
  );
  if (width < 0.18 || height < 0.18) {
    return InvoiceReceiptGeometryObservation(
      signal: InvoiceReceiptGeometrySignal.uncertain,
      evidenceCount: retained.length,
      sourceEvidenceCount: translated.length,
      heightToWidthRatio: null,
      medianEvidenceWidth: medianWidth,
      normalizedEnvelope: envelope,
      anchorApplied: anchorApplied,
    );
  }

  final ratio = height / width;
  final narrowByAspect = ratio >= 1.55;
  final narrowByFootprint = width <= 0.58 &&
      height >= 0.32 &&
      medianWidth <= 0.34 &&
      ratio >= 0.80;
  final signal = narrowByAspect || narrowByFootprint
      ? InvoiceReceiptGeometrySignal.narrowTall
      : ratio <= 1.25 || width >= 0.66 || medianWidth >= 0.42
          ? InvoiceReceiptGeometrySignal.wide
          : InvoiceReceiptGeometrySignal.uncertain;

  return InvoiceReceiptGeometryObservation(
    signal: signal,
    evidenceCount: retained.length,
    sourceEvidenceCount: translated.length,
    heightToWidthRatio: ratio,
    medianEvidenceWidth: medianWidth,
    normalizedEnvelope: envelope,
    anchorApplied: anchorApplied,
  );
}

Rect translateInvoiceEvidenceRect(
  Rect imageRect, {
  required Size canvasSize,
  required Size imageSize,
  required InputImageRotation rotation,
  required CameraLensDirection lensDirection,
  bool? isIos,
}) {
  final left = _translateX(
    imageRect.left,
    canvasSize,
    imageSize,
    rotation,
    lensDirection,
    isIos: isIos,
  );
  final right = _translateX(
    imageRect.right,
    canvasSize,
    imageSize,
    rotation,
    lensDirection,
    isIos: isIos,
  );
  final top = _translateY(
    imageRect.top,
    canvasSize,
    imageSize,
    rotation,
    isIos: isIos,
  );
  final bottom = _translateY(
    imageRect.bottom,
    canvasSize,
    imageSize,
    rotation,
    isIos: isIos,
  );
  return Rect.fromLTRB(
    left < right ? left : right,
    top < bottom ? top : bottom,
    left < right ? right : left,
    top < bottom ? bottom : top,
  );
}

Rect? findInvoiceTextEvidenceRect(
  List<InvoiceOcrVisualLine> lines,
  String invoiceNumber,
) {
  final target = _compactAlphaNumeric(invoiceNumber);
  if (target.isEmpty) return null;
  for (final line in lines) {
    if (_compactAlphaNumeric(line.text).contains(target)) return line.imageRect;
  }
  return null;
}

Rect? findSellerTaxTextEvidenceRect(
  List<InvoiceOcrVisualLine> lines,
  String sellerTaxIdCandidate,
) {
  final target = _normalizedOcrDigits(sellerTaxIdCandidate);
  if (target.length != 8) return null;
  final explicitLabel = RegExp(
    r'(?:賣方(?:統編|統一編號)?|統編|統一編號)',
    caseSensitive: false,
  );
  final exactEight = RegExp(r'^[0-9０-９]{8}$');
  final noEight = RegExp(
    r'^(?:NO|N0|HO)\.?\s*[:：.]?\s*[0-9０-９OIl|BDSZGTE]{8}$',
    caseSensitive: false,
  );
  for (final line in lines) {
    final raw = line.text.trim();
    if (_normalizedOcrDigits(raw).contains(target) &&
        (explicitLabel.hasMatch(raw) || exactEight.hasMatch(raw) || noEight.hasMatch(raw))) {
      return line.imageRect;
    }
  }
  return null;
}


InvoiceSellerTaxStructuralEvidence? findSellerTaxStructuralEvidence(
  List<InvoiceOcrVisualLine> lines, {
  required String invoiceNumber,
}) {
  if (lines.isEmpty) return null;
  final invoiceTarget = _compactAlphaNumeric(invoiceNumber);
  if (invoiceTarget.isEmpty) return null;

  var invoiceIndex = -1;
  for (var index = 0; index < lines.length; index += 1) {
    if (_compactAlphaNumeric(lines[index].text).contains(invoiceTarget)) {
      invoiceIndex = index;
      break;
    }
  }
  if (invoiceIndex < 0) return null;

  final invoiceLine = lines[invoiceIndex];
  final invoiceDigits = invoiceTarget.length >= 8
      ? invoiceTarget.substring(invoiceTarget.length - 8)
      : invoiceTarget;
  final explicitToken = RegExp(
    r'(?:賣方(?:統編|統一編號)?|統編|統一編號)\s*[:：.]?\s*([0-9０-９OIl|BDSZGTE]{7,9})(?![0-9０-９OIl|BDSZGTE])',
    caseSensitive: false,
  );
  final weakLabelToken = RegExp(
    r'^(?:NO|N0|HO|H0)\.?\s*[:：.]?\s*([0-9０-９OIl|BDSZGTE]{7,9})$',
    caseSensitive: false,
  );
  final unlabeledEightDigits = RegExp(r'^[0-9０-９]{8}$');
  final hardBoundary = RegExp(
    r'(?:電話|TEL|PHONE|地址|日期|時間|交易明細|商品明細|消費明細|銷售明細|發票明細|交易內容|品項|項目|總計|合計|小計|現金|收現|找零|隨機碼|訂單|交易編號)',
    caseSensitive: false,
  );

  final end = (invoiceIndex + 8).clamp(0, lines.length);
  for (var index = invoiceIndex + 1; index < end; index += 1) {
    final line = lines[index];
    final raw = line.text.trim();
    if (raw.isEmpty) continue;
    if (hardBoundary.hasMatch(raw)) break;

    String? token;
    String source = '';
    final explicit = explicitToken.firstMatch(raw);
    final weak = weakLabelToken.firstMatch(raw);
    if (explicit != null) {
      token = explicit.group(1);
      source = 'explicit_label_structure';
    } else if (weak != null) {
      token = weak.group(1);
      source = 'weak_label_structure';
    } else if (unlabeledEightDigits.hasMatch(raw)) {
      token = raw;
      source = 'positional_8digit_structure';
    }
    if (token == null || !_isMostlyDigitLikeSellerTaxToken(token)) {
      continue;
    }

    final normalizedCandidate = _normalizedOcrDigits(token);
    if (normalizedCandidate == invoiceDigits) continue;

    final invoiceHeight = invoiceLine.imageRect.height <= 0
        ? 1.0
        : invoiceLine.imageRect.height;
    final verticalGap = line.imageRect.top - invoiceLine.imageRect.bottom;
    if (verticalGap < -invoiceHeight * 0.4 ||
        verticalGap > invoiceHeight * 14) {
      continue;
    }
    final horizontalTolerance =
        (invoiceLine.imageRect.width + line.imageRect.width)
  .clamp(1.0, double.infinity);
    if ((line.imageRect.center.dx - invoiceLine.imageRect.center.dx).abs() >
        horizontalTolerance) {
      continue;
    }

    return InvoiceSellerTaxStructuralEvidence(
      rawText: raw,
      imageRect: line.imageRect,
      source: source,
    );
  }
  return null;
}

bool _isMostlyDigitLikeSellerTaxToken(String token) {
  final compact = token.replaceAll(RegExp(r'[\s:：.]'), '');
  if (compact.length < 7 || compact.length > 9) return false;
  final digitLike = RegExp(r'[0-9０-９OIl|]', caseSensitive: false)
      .allMatches(compact)
      .length;
  return digitLike >= 6 && digitLike * 3 >= compact.length * 2;
}

InvoiceSellerTaxVisualCandidate? findSellerTaxVisualCandidate(
  List<InvoiceOcrVisualLine> lines, {
  required String invoiceNumber,
}) {
  if (lines.isEmpty) return null;

  final structural = findSellerTaxStructuralEvidence(
    lines,
    invoiceNumber: invoiceNumber,
  );
  if (structural != null) {
    return InvoiceSellerTaxVisualCandidate(
      rawText: structural.rawText,
      imageRect: structural.imageRect,
    );
  }

  final explicitLabel = RegExp(
    r'(?:賣方(?:統編|統一編號)?|統編|統一編號)',
    caseSensitive: false,
  );
  final explicitToken = RegExp(
    r'(?:賣方(?:統編|統一編號)?|統編|統一編號)\s*[:：.]?\s*([0-9０-９OIl|BDSZGTE]{8})(?![0-9０-９OIl|BDSZGTE])',
    caseSensitive: false,
  );
  final noToken = RegExp(
    r'^(?:NO|N0|HO)\.?\s*[:：.]?\s*([0-9０-９OIl|BDSZGTE]{8})$',
    caseSensitive: false,
  );
  final unlabeledEightDigits = RegExp(r'^[0-9０-９]{8}$');
  final hardBoundary = RegExp(
    r'(?:電話|TEL|PHONE|地址|日期|時間|交易明細|商品明細|消費明細|銷售明細|發票明細|交易內容|品項|項目|總計|合計|小計|現金|收現|找零|隨機碼|訂單|交易編號)',
    caseSensitive: false,
  );

  for (final line in lines) {
    final raw = line.text.trim();
    if (!explicitLabel.hasMatch(raw) || hardBoundary.hasMatch(raw)) continue;
    if (explicitToken.hasMatch(raw)) {
      return InvoiceSellerTaxVisualCandidate(
        rawText: raw,
        imageRect: line.imageRect,
      );
    }
  }

  final invoiceTarget = _compactAlphaNumeric(invoiceNumber);
  if (invoiceTarget.isEmpty) return null;
  var invoiceIndex = -1;
  for (var index = 0; index < lines.length; index += 1) {
    if (_compactAlphaNumeric(lines[index].text).contains(invoiceTarget)) {
      invoiceIndex = index;
      break;
    }
  }
  if (invoiceIndex < 0) return null;

  final invoiceLine = lines[invoiceIndex];
  final invoiceDigits = invoiceTarget.length >= 8
      ? invoiceTarget.substring(invoiceTarget.length - 8)
      : invoiceTarget;
  final end = (invoiceIndex + 7).clamp(0, lines.length);
  for (var index = invoiceIndex + 1; index < end; index += 1) {
    final line = lines[index];
    final raw = line.text.trim();
    if (raw.isEmpty) continue;
    if (hardBoundary.hasMatch(raw)) break;

    final weakNo = noToken.firstMatch(raw);
    final pureUnlabeled = unlabeledEightDigits.hasMatch(raw);
    if (weakNo == null && !pureUnlabeled) continue;

    final candidateToken = weakNo?.group(1) ?? raw;
    final normalizedCandidate = _normalizedOcrDigits(candidateToken);
    if (normalizedCandidate.length > 8 || normalizedCandidate == invoiceDigits) {
      continue;
    }

    final invoiceHeight = invoiceLine.imageRect.height <= 0
        ? 1.0
        : invoiceLine.imageRect.height;
    final verticalGap = line.imageRect.top - invoiceLine.imageRect.bottom;
    if (verticalGap < -invoiceHeight * 0.4 || verticalGap > invoiceHeight * 14) {
      continue;
    }
    final horizontalTolerance =
        (invoiceLine.imageRect.width + line.imageRect.width)
            .clamp(1.0, double.infinity);
    if ((line.imageRect.center.dx - invoiceLine.imageRect.center.dx).abs() >
        horizontalTolerance) {
      continue;
    }
    return InvoiceSellerTaxVisualCandidate(
      rawText: raw,
      imageRect: line.imageRect,
    );
  }
  return null;
}

class InvoiceLiveEvidencePainter extends CustomPainter {
  const InvoiceLiveEvidencePainter({required this.snapshot});

  final InvoiceLiveVisualOverlaySnapshot snapshot;

  @override
  void paint(Canvas canvas, Size size) {
    for (final item in snapshot.evidence) {
      final rect = translateInvoiceEvidenceRect(
        item.imageRect,
        canvasSize: size,
        imageSize: snapshot.imageSize,
        rotation: snapshot.rotation,
        lensDirection: snapshot.lensDirection,
      );
      if (rect.width < 4 || rect.height < 4) continue;
      final color = item.accepted ? Colors.greenAccent : Colors.amberAccent;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = color;
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect.inflate(2), const Radius.circular(7)),
        paint,
      );

      final textPainter = TextPainter(
        text: TextSpan(
          text: item.label,
          style: TextStyle(
            color: color,
            backgroundColor: Colors.black87,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout(maxWidth: size.width * 0.6);
      final labelY = rect.top - textPainter.height - 3 >= 0
          ? rect.top - textPainter.height - 3
          : rect.bottom + 3;
      final labelX = rect.left
          .clamp(0.0, size.width - textPainter.width)
          .toDouble();
      textPainter.paint(canvas, Offset(labelX, labelY));
    }
  }

  @override
  bool shouldRepaint(covariant InvoiceLiveEvidencePainter oldDelegate) =>
      oldDelegate.snapshot != snapshot;
}

Rect _clipNormalizedRect(Rect rect) {
  const bounds = Rect.fromLTRB(0, 0, 1, 1);
  final clipped = rect.intersect(bounds);
  return clipped.width > 0 && clipped.height > 0 ? clipped : Rect.zero;
}

double _median(List<double> values) {
  if (values.isEmpty) return 0;
  final sorted = values.toList(growable: false)..sort();
  final middle = sorted.length ~/ 2;
  if (sorted.length.isOdd) return sorted[middle];
  return (sorted[middle - 1] + sorted[middle]) / 2;
}

double _translateX(
  double x,
  Size canvasSize,
  Size imageSize,
  InputImageRotation rotation,
  CameraLensDirection lensDirection, {
  bool? isIos,
}) {
  final ios = isIos ?? Platform.isIOS;
  switch (rotation) {
    case InputImageRotation.rotation90deg:
      return x * canvasSize.width / (ios ? imageSize.width : imageSize.height);
    case InputImageRotation.rotation270deg:
      return canvasSize.width -
          x * canvasSize.width / (ios ? imageSize.width : imageSize.height);
    case InputImageRotation.rotation0deg:
    case InputImageRotation.rotation180deg:
      if (lensDirection == CameraLensDirection.back) {
        return x * canvasSize.width / imageSize.width;
      }
      return canvasSize.width - x * canvasSize.width / imageSize.width;
  }
}

double _translateY(
  double y,
  Size canvasSize,
  Size imageSize,
  InputImageRotation rotation, {
  bool? isIos,
}) {
  final ios = isIos ?? Platform.isIOS;
  switch (rotation) {
    case InputImageRotation.rotation90deg:
    case InputImageRotation.rotation270deg:
      return y * canvasSize.height / (ios ? imageSize.height : imageSize.width);
    case InputImageRotation.rotation0deg:
    case InputImageRotation.rotation180deg:
      return y * canvasSize.height / imageSize.height;
  }
}

String _compactAlphaNumeric(String value) => value
    .toUpperCase()
    .replaceAll(RegExp(r'[^A-Z0-9|]'), '');

String _normalizedOcrDigits(String value) => value
    .toUpperCase()
    .replaceAll('O', '0')
    .replaceAll('I', '1')
    .replaceAll('L', '1')
    .replaceAll(RegExp(r'[^0-9]'), '');
