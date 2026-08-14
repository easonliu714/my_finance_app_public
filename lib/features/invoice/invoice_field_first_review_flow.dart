import 'google_mlkit_traditional_invoice_recognizer.dart';
import 'image_capture_staging.dart';
import 'invoice_automatic_recognition_coordinator.dart';
import 'invoice_capture_review_flow.dart';
import 'invoice_field_first_review_form_presenter.dart';
import 'invoice_live_capture_page.dart';
import 'invoice_local_recognition_coordinator.dart';
import 'invoice_total_evidence.dart';
import 'mobile_scanner_invoice_qr_decoder.dart';
import 'traditional_invoice_ocr_review.dart';
import 'traditional_tax_id_temporal_repair.dart';

class FieldFirstInvoiceCaptureReviewFlowCoordinator
    extends InvoiceCaptureReviewFlowCoordinator {
  FieldFirstInvoiceCaptureReviewFlowCoordinator({
    required this.liveResult,
    required super.recognitionCoordinator,
    super.handoffPresenter,
    super.formPresenter = const FieldFirstInvoiceReviewFormPresenter(),
  });

  factory FieldFirstInvoiceCaptureReviewFlowCoordinator.production({
    required InvoiceLiveCaptureResult liveResult,
  }) {
    return FieldFirstInvoiceCaptureReviewFlowCoordinator(
      liveResult: liveResult,
      recognitionCoordinator: InvoiceAutomaticRecognitionCoordinator(
        qrRunner: InvoiceLocalRecognitionCoordinator(
          decoder: NativeInvoiceQrDecoder(),
        ).recognize,
        ocrRunner: const TraditionalInvoiceOcrCoordinator(
          recognizer: GoogleMlKitTraditionalInvoiceRecognizer(),
        ).recognize,
      ),
    );
  }

  final InvoiceLiveCaptureResult liveResult;

  @override
  Future<InvoiceCaptureReviewFlowResult> recognize({
    required ImageCaptureStagingItem image,
    required InvoiceRecognitionRequestedRoute requestedRoute,
  }) async {
    // Classification is advisory. Frozen review always starts QR-first and may
    // fall back to OCR so damaged QR never blocks visible field extraction.
    final primary = await super.recognize(
      image: image,
      requestedRoute: InvoiceRecognitionRequestedRoute.automatic,
    );
    var recognition = primary.recognitionResult;

    if (recognition.status != InvoiceAutomaticRecognitionStatus.invalidInput &&
        recognition.ocrResult == null) {
      final supplementalOcr =
          await recognitionCoordinator.ocrRunner(image.localReference.trim());
      if (recognition.status ==
          InvoiceAutomaticRecognitionStatus.qrReviewCandidate) {
        recognition = _copyRecognition(
          recognition,
          ocrResult: supplementalOcr,
        );
      } else if (supplementalOcr.hasReviewCandidate) {
        recognition = InvoiceAutomaticRecognitionResult(
          status: InvoiceAutomaticRecognitionStatus.ocrReviewCandidate,
          message: supplementalOcr.message,
          selectedRouteReason:
              '欄位優先覆核：QR 不可用、損壞或不足時改用本機 OCR；發票類型不阻擋可見欄位辨識。',
          requestedRoute: InvoiceRecognitionRequestedRoute.automatic,
          qrResult: recognition.qrResult,
          ocrResult: supplementalOcr,
        );
      }
    }

    recognition = _applyEffectiveTotalEvidence(recognition);
    recognition = _applyEffectiveTemporalSellerTaxId(recognition);
    final handoff = handoffPresenter.fromAutomaticResult(recognition);
    final form = formPresenter.fromHandoff(handoff);
    return InvoiceCaptureReviewFlowResult(
      recognitionResult: recognition,
      handoffState: handoff,
      formModel: form,
    );
  }

  InvoiceAutomaticRecognitionResult _applyEffectiveTotalEvidence(
    InvoiceAutomaticRecognitionResult recognition,
  ) {
    final ocrResult = recognition.ocrResult;
    final candidate = ocrResult?.candidate;
    if (ocrResult == null || candidate == null || candidate.rawLines.isEmpty) {
      return recognition;
    }
    final totalEvidence = resolveInvoiceTotalEvidence(candidate.rawLines);
    if (totalEvidence == null || candidate.totalAmount == totalEvidence.value) {
      return recognition;
    }

    final confidence = <TraditionalInvoiceOcrField,
        TraditionalInvoiceOcrConfidence>{
      ...candidate.confidence,
      TraditionalInvoiceOcrField.totalAmount:
          TraditionalInvoiceOcrConfidence.medium,
    };
    final warnings = <TraditionalInvoiceOcrField, List<String>>{
      ...candidate.fieldWarnings,
      TraditionalInvoiceOcrField.totalAmount: <String>[
        ...(candidate.fieldWarnings[TraditionalInvoiceOcrField.totalAmount] ??
            const <String>[]),
        'Field-First 總額採用 ${totalEvidence.source} 的高優先語意證據 ${_amount(totalEvidence.value)}；原始 Frozen OCR 保持不變。',
      ],
    };
    final effectiveCandidate = TraditionalInvoiceOcrReviewCandidate(
      sourceImageReference: candidate.sourceImageReference,
      invoiceNumber: candidate.invoiceNumber,
      sellerTaxId: candidate.sellerTaxId,
      sellerTaxIdSource: candidate.sellerTaxIdSource,
      invoiceDate: candidate.invoiceDate,
      sellerName: candidate.sellerName,
      totalAmount: totalEvidence.value,
      visibleLineItems: candidate.visibleLineItems,
      confidence: Map<TraditionalInvoiceOcrField,
          TraditionalInvoiceOcrConfidence>.unmodifiable(confidence),
      fieldWarnings: Map<TraditionalInvoiceOcrField, List<String>>.unmodifiable(
        warnings.map(
          (key, value) => MapEntry(key, List<String>.unmodifiable(value)),
        ),
      ),
      rawText: candidate.rawText,
      rawLines: candidate.rawLines,
    );
    return _copyRecognition(
      recognition,
      ocrResult: _effectiveOcrResult(ocrResult, effectiveCandidate),
    );
  }

  InvoiceAutomaticRecognitionResult _applyEffectiveTemporalSellerTaxId(
    InvoiceAutomaticRecognitionResult recognition,
  ) {
    final ocrResult = recognition.ocrResult;
    final candidate = ocrResult?.candidate;
    if (ocrResult == null ||
        candidate == null ||
        candidate.sellerTaxId.trim().isNotEmpty) {
      return recognition;
    }
    final repair = _resolveLiveFrozenTemporalTaxRepair(candidate);
    if (!repair.accepted) return recognition;

    final confidence = <TraditionalInvoiceOcrField,
        TraditionalInvoiceOcrConfidence>{
      ...candidate.confidence,
      TraditionalInvoiceOcrField.sellerTaxId:
          TraditionalInvoiceOcrConfidence.medium,
    };
    final warnings = <TraditionalInvoiceOcrField, List<String>>{
      ...candidate.fieldWarnings,
      TraditionalInvoiceOcrField.sellerTaxId: <String>[
        '由 ${repair.observations} 個同發票 Live/Frozen observation 的受限 checksum repair 提供有效覆核值；原始 Frozen OCR 保持不變。',
      ],
    };
    final effectiveCandidate = TraditionalInvoiceOcrReviewCandidate(
      sourceImageReference: candidate.sourceImageReference,
      invoiceNumber: candidate.invoiceNumber,
      sellerTaxId: repair.repairedValue,
      sellerTaxIdSource: positionalTaxIdTemporalRepairSource,
      invoiceDate: candidate.invoiceDate,
      sellerName: candidate.sellerName,
      totalAmount: candidate.totalAmount,
      visibleLineItems: candidate.visibleLineItems,
      confidence: Map<TraditionalInvoiceOcrField,
          TraditionalInvoiceOcrConfidence>.unmodifiable(confidence),
      fieldWarnings: Map<TraditionalInvoiceOcrField, List<String>>.unmodifiable(
        warnings.map(
          (key, value) => MapEntry(key, List<String>.unmodifiable(value)),
        ),
      ),
      rawText: candidate.rawText,
      rawLines: candidate.rawLines,
    );
    return _copyRecognition(
      recognition,
      ocrResult: _effectiveOcrResult(ocrResult, effectiveCandidate),
    );
  }

  PositionalTaxIdTemporalRepairResult _resolveLiveFrozenTemporalTaxRepair(
    TraditionalInvoiceOcrReviewCandidate frozenCandidate,
  ) {
    if (liveResult.origin != InvoiceCaptureOrigin.liveCamera) {
      return const PositionalTaxIdTemporalRepairResult.none();
    }

    final observations = <PositionalTaxIdFrameObservation>[];
    for (final sample in liveResult.liveHistory) {
      final invoiceNumber = sample.snapshot.invoiceNumber.trim();
      if (invoiceNumber.isEmpty || sample.rawLines.isEmpty) continue;
      final rawCandidate = extractUnverifiedPositionalHeaderTaxIdFromLines(
        rawLines: sample.rawLines,
        invoiceNumber: invoiceNumber,
      );
      if (rawCandidate == null) continue;
      observations.add(
        PositionalTaxIdFrameObservation(
          invoiceNumber: invoiceNumber,
          rawCandidate: rawCandidate,
        ),
      );
    }

    final frozenInvoiceNumber = frozenCandidate.invoiceNumber.trim();
    final frozenRawCandidate = frozenInvoiceNumber.isEmpty ||
            frozenCandidate.rawLines.isEmpty
        ? null
        : extractUnverifiedPositionalHeaderTaxIdFromLines(
            rawLines: frozenCandidate.rawLines,
            invoiceNumber: frozenInvoiceNumber,
          );
    if (frozenRawCandidate != null) {
      return resolvePositionalTaxIdTemporalRepair(
        history: observations,
        currentInvoiceNumber: frozenInvoiceNumber,
        currentRawCandidate: frozenRawCandidate,
      );
    }

    // Preserve the v4.16.15 live-only repair path when Frozen OCR does not
    // expose a positional 8-digit candidate.
    if (observations.length < 2) {
      return const PositionalTaxIdTemporalRepairResult.none();
    }
    final current = observations.last;
    return resolvePositionalTaxIdTemporalRepair(
      history: observations.sublist(0, observations.length - 1),
      currentInvoiceNumber: current.invoiceNumber,
      currentRawCandidate: current.rawCandidate,
    );
  }

  TraditionalInvoiceOcrResult _effectiveOcrResult(
    TraditionalInvoiceOcrResult source,
    TraditionalInvoiceOcrReviewCandidate effectiveCandidate,
  ) {
    return TraditionalInvoiceOcrResult(
      status: effectiveCandidate.hasAllCoreFields
          ? TraditionalInvoiceOcrStatus.success
          : TraditionalInvoiceOcrStatus.partial,
      message: source.message,
      candidate: effectiveCandidate,
      rawRecognition: source.rawRecognition,
    );
  }

  InvoiceAutomaticRecognitionResult _copyRecognition(
    InvoiceAutomaticRecognitionResult source, {
    TraditionalInvoiceOcrResult? ocrResult,
  }) {
    return InvoiceAutomaticRecognitionResult(
      status: source.status,
      message: source.message,
      selectedRouteReason: source.selectedRouteReason,
      requestedRoute: InvoiceRecognitionRequestedRoute.automatic,
      qrResult: source.qrResult,
      ocrResult: ocrResult ?? source.ocrResult,
    );
  }

  String _amount(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toString();
}
