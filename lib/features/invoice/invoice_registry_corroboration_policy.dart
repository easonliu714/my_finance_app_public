import 'invoice_automatic_recognition_coordinator.dart';
import 'invoice_review_form_view_model.dart';
import 'taiwan_tax_id.dart';

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

  InvoiceRegistryCorroborationAuthorityDecision evaluate({
    required InvoiceAutomaticRecognitionResult recognition,
    required InvoiceReviewFormViewModel review,
  }) {
    final seller = _digits(
      review.fieldFor(InvoiceReviewFieldKey.sellerTaxId)?.value ?? '',
    );
    if (seller.length != 8) return _notAuthoritative(seller, 'seller_identifier_not_exact_8_digits');

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
        ocr.sellerTaxIdSource == 'explicit_label' &&
        hasValidTaiwanTaxIdChecksum(seller)) {
      return InvoiceRegistryCorroborationAuthorityDecision(
        sellerIdentifier: seller,
        authoritative: true,
        source:
            InvoiceRegistryCorroborationAuthoritySource.traditionalExplicitLabel,
        reason: 'authoritative_traditional_explicit_label',
      );
    }

    return _notAuthoritative(
      seller,
      'invoice_evidence_not_authoritative_for_registry',
    );
  }

  /// Re-evaluates authority after the user edits or switches the seller-ID
  /// source inside the invoice review card.
  ///
  /// Current Local review forms only carry a non-empty non-QR seller ID after
  /// the governed Traditional Frozen explicit-label parser or a governed Live
  /// temporal-repair path has already accepted it. Weak single-frame
  /// positional/header candidates remain blank upstream and cannot reach this
  /// path. Manual/AI selections receive their own stricter checks below.
  InvoiceRegistryCorroborationAuthorityDecision evaluateReviewSelection({
    required String sellerIdentifier,
    required bool localQrAuthority,
    required bool explicitlyCorrected,
    required bool explicitlyAiSelected,
    required bool aiComparisonAcknowledged,
    required bool initialLocalSellerIdentifierWasPresent,
  }) {
    final seller = _digits(sellerIdentifier);
    if (seller.length != 8) return _notAuthoritative(seller, 'seller_identifier_not_exact_8_digits');

    if (explicitlyAiSelected) {
      if (!aiComparisonAcknowledged) {
        return _notAuthoritative(seller, 'ai_selection_not_globally_acknowledged');
      }
      if (!hasValidTaiwanTaxIdChecksum(seller)) {
        return _notAuthoritative(seller, 'ai_selection_failed_strict_checksum');
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
        return _notAuthoritative(seller, 'manual_correction_failed_strict_checksum');
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

    if (initialLocalSellerIdentifierWasPresent &&
        hasValidTaiwanTaxIdChecksum(seller)) {
      return InvoiceRegistryCorroborationAuthorityDecision(
        sellerIdentifier: seller,
        authoritative: true,
        source:
            InvoiceRegistryCorroborationAuthoritySource.governedLocalEvidence,
        reason: 'authoritative_governed_local_seller_identifier',
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
