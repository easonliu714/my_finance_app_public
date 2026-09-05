import 'invoice_automatic_recognition_coordinator.dart';
import 'invoice_review_form_view_model.dart';
import 'taiwan_tax_id.dart';
import 'traditional_tax_id_temporal_repair.dart';

enum InvoiceRegistryCorroborationAuthoritySource {
  none,
  qrPayload,
  traditionalExplicitLabel,
  governedLocalEvidence,
  explicitUserCorrection,
  explicitAiSelection,
}

class InvoiceRegistryCorroborationAuthorityDecision {
  const InvoiceRegistryCorroborationAuthorityDecision({
    required this.sellerIdentifier,
    required this.authoritative,
    required this.source,
    this.reason = '',
  });

  final String sellerIdentifier;
  final bool authoritative;
  final InvoiceRegistryCorroborationAuthoritySource source;
  final String reason;
}

/// Fail-closed bridge between invoice-recognition evidence and the official
/// business registry.
///
/// Registry data is corroboration only. It may be queried only after the
/// seller identifier already has authority from the invoice-recognition
/// contract; a registry hit can never promote weak OCR evidence.
class InvoiceRegistryCorroborationAuthorityPolicy {
  const InvoiceRegistryCorroborationAuthorityPolicy();

  static const String qrPayloadSource = 'qr_payload';
  static const String traditionalExplicitLabelSource = 'explicit_label';

  InvoiceRegistryCorroborationAuthorityDecision evaluate({
    required InvoiceAutomaticRecognitionResult recognition,
    required InvoiceReviewFormViewModel review,
  }) {
    final seller = _digits(
      review.fieldFor(InvoiceReviewFieldKey.sellerTaxId)?.value ?? '',
    );
    if (seller.length != 8) {
      return _notAuthoritative(
        seller,
        'seller_identifier_not_exact_8_digits',
      );
    }

    if (recognition.status ==
            InvoiceAutomaticRecognitionStatus.qrReviewCandidate &&
        _qrSellerIdentifier(recognition) == seller) {
      return InvoiceRegistryCorroborationAuthorityDecision(
        sellerIdentifier: seller,
        authoritative: true,
        source: InvoiceRegistryCorroborationAuthoritySource.qrPayload,
        reason: 'authoritative_qr_payload',
      );
    }

    final ocr = recognition.ocrResult?.candidate;
    if (recognition.status ==
            InvoiceAutomaticRecognitionStatus.ocrReviewCandidate &&
        ocr != null &&
        _digits(ocr.sellerTaxId) == seller &&
        hasValidTaiwanTaxIdChecksum(seller)) {
      if (ocr.sellerTaxIdSource == traditionalExplicitLabelSource) {
        return InvoiceRegistryCorroborationAuthorityDecision(
          sellerIdentifier: seller,
          authoritative: true,
          source: InvoiceRegistryCorroborationAuthoritySource
              .traditionalExplicitLabel,
          reason: 'authoritative_traditional_explicit_label',
        );
      }
      if (ocr.sellerTaxIdSource == positionalTaxIdTemporalRepairSource) {
        return InvoiceRegistryCorroborationAuthorityDecision(
          sellerIdentifier: seller,
          authoritative: true,
          source: InvoiceRegistryCorroborationAuthoritySource
              .governedLocalEvidence,
          reason: 'authoritative_temporal_seller_identifier_repair',
        );
      }
    }

    return _notAuthoritative(
      seller,
      'invoice_evidence_not_authoritative_for_registry',
    );
  }

  /// Re-evaluates authority after the user edits or switches the seller-ID
  /// source inside the invoice review card.
  ///
  /// The initial Local seller identifier must carry its machine-readable
  /// provenance from the recognition result. Merely being present or passing
  /// checksum is not enough to authorize a Registry lookup.
  InvoiceRegistryCorroborationAuthorityDecision evaluateReviewSelection({
    required String sellerIdentifier,
    required bool localQrAuthority,
    required bool explicitlyCorrected,
    required bool explicitlyAiSelected,
    required bool aiComparisonAcknowledged,
    required String initialLocalSellerIdentifierSource,
  }) {
    final seller = _digits(sellerIdentifier);
    if (seller.length != 8) {
      return _notAuthoritative(
        seller,
        'seller_identifier_not_exact_8_digits',
      );
    }

    if (explicitlyAiSelected) {
      if (!aiComparisonAcknowledged) {
        return _notAuthoritative(
          seller,
          'ai_selection_not_globally_acknowledged',
        );
      }
      if (!hasValidTaiwanTaxIdChecksum(seller)) {
        return _notAuthoritative(
          seller,
          'ai_selection_failed_strict_checksum',
        );
      }
      return InvoiceRegistryCorroborationAuthorityDecision(
        sellerIdentifier: seller,
        authoritative: true,
        source: InvoiceRegistryCorroborationAuthoritySource.explicitAiSelection,
        reason: 'authoritative_explicit_ai_selection',
      );
    }

    if (explicitlyCorrected) {
      if (!hasValidTaiwanTaxIdChecksum(seller)) {
        return _notAuthoritative(
          seller,
          'manual_correction_failed_strict_checksum',
        );
      }
      return InvoiceRegistryCorroborationAuthorityDecision(
        sellerIdentifier: seller,
        authoritative: true,
        source:
            InvoiceRegistryCorroborationAuthoritySource.explicitUserCorrection,
        reason: 'authoritative_explicit_user_correction',
      );
    }

    if (localQrAuthority) {
      return InvoiceRegistryCorroborationAuthorityDecision(
        sellerIdentifier: seller,
        authoritative: true,
        source: InvoiceRegistryCorroborationAuthoritySource.qrPayload,
        reason: 'authoritative_qr_payload',
      );
    }

    final localSource = initialLocalSellerIdentifierSource.trim();
    if (hasValidTaiwanTaxIdChecksum(seller) &&
        localSource == traditionalExplicitLabelSource) {
      return InvoiceRegistryCorroborationAuthorityDecision(
        sellerIdentifier: seller,
        authoritative: true,
        source:
            InvoiceRegistryCorroborationAuthoritySource.traditionalExplicitLabel,
        reason: 'authoritative_traditional_explicit_label',
      );
    }
    if (hasValidTaiwanTaxIdChecksum(seller) &&
        localSource == positionalTaxIdTemporalRepairSource) {
      return InvoiceRegistryCorroborationAuthorityDecision(
        sellerIdentifier: seller,
        authoritative: true,
        source:
            InvoiceRegistryCorroborationAuthoritySource.governedLocalEvidence,
        reason: 'authoritative_temporal_seller_identifier_repair',
      );
    }

    return _notAuthoritative(seller, 'review_selection_not_authoritative');
  }

  String _qrSellerIdentifier(InvoiceAutomaticRecognitionResult recognition) {
    final pairs = recognition.qrResult?.routingResult?.pairs;
    if (pairs == null || pairs.isEmpty) return '';
    return _digits(
      pairs.first.left.leftParseResult?.sellerIdentifier ?? '',
    );
  }

  InvoiceRegistryCorroborationAuthorityDecision _notAuthoritative(
    String seller,
    String reason,
  ) {
    return InvoiceRegistryCorroborationAuthorityDecision(
      sellerIdentifier: seller,
      authoritative: false,
      source: InvoiceRegistryCorroborationAuthoritySource.none,
      reason: reason,
    );
  }

  static String _digits(String value) =>
      value.replaceAll(RegExp(r'[^0-9]'), '');
}
