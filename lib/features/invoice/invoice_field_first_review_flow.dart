import 'image_capture_staging.dart';
import 'invoice_automatic_recognition_coordinator.dart';
import 'invoice_capture_review_flow.dart';
import 'invoice_field_first_review_form_presenter.dart';
import 'invoice_live_capture_page.dart';
import 'invoice_local_recognition_coordinator.dart';
import 'invoice_total_evidence.dart';
import 'mobile_scanner_invoice_qr_decoder.dart';
import 'traditional_invoice_multi_variant_recognizer.dart';
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
          recognizer: GoogleMlKitMultiVariantTraditionalInvoiceRecognizer(),
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

    recognition = _applyLiveFrozenEvidenceContinuity(recognition, image);
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

  InvoiceAutomaticRecognitionResult _applyLiveFrozenEvidenceContinuity(
    InvoiceAutomaticRecognitionResult recognition,
    ImageCaptureStagingItem image,
  ) {
    if (recognition.status !=
            InvoiceAutomaticRecognitionStatus.recognitionFailed ||
        recognition.hasReviewCandidate ||
        liveResult.origin != InvoiceCaptureOrigin.liveCamera ||
        !liveResult.liveSnapshot.canFreeze) {
      return recognition;
    }

    final invoiceNumber = _resolveLiveInvoiceNumberConsensus();
    if (invoiceNumber.isEmpty) return recognition;

    final rawRecognition = recognition.ocrResult?.rawRecognition;
    final frozenRawText = rawRecognition?.rawText.trim() ?? '';
    final frozenRawLines = rawRecognition?.rawLines ?? const <String>[];
    final invoiceDate = _resolveLiveExactDateConsensus(invoiceNumber);
    final invoiceTime = _resolveLiveExactTimeConsensus(invoiceNumber);
    final continuityMarker =
        invoiceTime.isEmpty ? '' : 'LIVE_EXACT_TIME=$invoiceTime';
    final candidateRawText = <String>[
      if (frozenRawText.isNotEmpty) frozenRawText,
      if (continuityMarker.isNotEmpty) continuityMarker,
    ].join('\n');
    final candidateRawLines = <String>[
      ...frozenRawLines,
      if (continuityMarker.isNotEmpty) continuityMarker,
    ];

    final confidence = <TraditionalInvoiceOcrField,
        TraditionalInvoiceOcrConfidence>{
      TraditionalInvoiceOcrField.invoiceNumber:
          TraditionalInvoiceOcrConfidence.medium,
      if (invoiceDate != null)
        TraditionalInvoiceOcrField.invoiceDate:
            TraditionalInvoiceOcrConfidence.medium,
    };
    final fieldWarnings = <TraditionalInvoiceOcrField, List<String>>{
      TraditionalInvoiceOcrField.invoiceNumber: const <String>[
        'P4.18.4 LIVE_CONSENSUS_FALLBACK：Frozen OCR 未建立候選；僅保留已通過 Live Green identity consensus 的發票號碼供人工覆核。',
      ],
      if (invoiceDate != null)
        TraditionalInvoiceOcrField.invoiceDate: const <String>[
          'P4.18.4 LIVE_EXACT_CONSENSUS_FALLBACK：同一發票的 Green observations 日期完全一致後才保留供人工覆核。',
        ],
    };
    final candidate = TraditionalInvoiceOcrReviewCandidate(
      sourceImageReference: image.localReference.trim(),
      invoiceNumber: invoiceNumber,
      sellerTaxId: '',
      sellerTaxIdSource: '',
      invoiceDate: invoiceDate,
      sellerName: '',
      totalAmount: null,
      visibleLineItems: const <TraditionalInvoiceOcrLineItem>[],
      confidence: Map<TraditionalInvoiceOcrField,
          TraditionalInvoiceOcrConfidence>.unmodifiable(confidence),
      fieldWarnings: Map<TraditionalInvoiceOcrField, List<String>>.unmodifiable(
        fieldWarnings,
      ),
      rawText: candidateRawText,
      rawLines: List<String>.unmodifiable(candidateRawLines),
    );
    final fallbackOcr = TraditionalInvoiceOcrResult(
      status: TraditionalInvoiceOcrStatus.partial,
      message: invoiceTime.isEmpty
          ? 'Frozen OCR 未建立候選；已保留 Live Green consensus 的安全欄位供人工覆核。'
          : 'Frozen OCR 未建立候選；已保留 Live Green identity 與 exact time consensus 的安全欄位供人工覆核。',
      candidate: candidate,
      rawRecognition: rawRecognition,
    );

    return InvoiceAutomaticRecognitionResult(
      status: InvoiceAutomaticRecognitionStatus.ocrReviewCandidate,
      message: fallbackOcr.message,
      selectedRouteReason:
          'P4.18.4 Live→Frozen evidence continuity：Frozen OCR fail-closed 時只保留已通過 Live consensus 的安全欄位；賣方統編與總金額不由 Live fallback 升格。',
      requestedRoute: InvoiceRecognitionRequestedRoute.automatic,
      qrResult: recognition.qrResult,
      ocrResult: fallbackOcr,
    );
  }

  String _resolveLiveInvoiceNumberConsensus() {
    final finalInvoice = liveResult.liveSnapshot.invoiceNumber.trim();
    if (finalInvoice.isEmpty || !liveResult.liveSnapshot.canFreeze) return '';
    final consensus = resolveTraditionalLiveIdentityConsensus(
      history: liveResult.liveHistory,
      currentInvoiceNumber: finalInvoice,
      currentSellerTaxId: liveResult.liveSnapshot.sellerTaxId,
      currentRawLines: const <String>[],
    );
    if (!consensus.canFreeze || consensus.invoiceNumber != finalInvoice) {
      return '';
    }
    return finalInvoice;
  }

  DateTime? _resolveLiveExactDateConsensus(String invoiceNumber) {
    final values = <String>[];
    for (final sample in liveResult.liveHistory) {
      final snapshot = sample.snapshot;
      if (!snapshot.canFreeze ||
          snapshot.invoiceNumber.trim() != invoiceNumber) {
        continue;
      }
      final value = snapshot.invoiceDate.trim();
      if (value.isNotEmpty) values.add(value);
    }
    if (values.length < 2 || values.toSet().length != 1) return null;
    final value = values.first;
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
    if (match == null) return null;
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    final parsed = DateTime.utc(year, month, day);
    if (parsed.year != year || parsed.month != month || parsed.day != day) {
      return null;
    }
    return parsed;
  }

  String _resolveLiveExactTimeConsensus(String invoiceNumber) {
    final values = <String>[];
    for (final sample in liveResult.liveHistory) {
      if (!sample.snapshot.canFreeze ||
          sample.snapshot.invoiceNumber.trim() != invoiceNumber) {
        continue;
      }
      final value = _extractStrictLiveTime(sample.rawLines.join('\n'));
      if (value.isNotEmpty) values.add(value);
    }
    if (values.length < 2 || values.toSet().length != 1) return '';
    return values.first;
  }

  String _extractStrictLiveTime(String rawText) {
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
