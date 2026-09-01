import 'invoice_automatic_recognition_coordinator.dart';
import 'invoice_review_form_view_model.dart';
import 'taiwan_tax_id.dart';

enum InvoiceRegistryCorroborationAuthoritySource {
  none,
  qrPayload,
  traditionalExplicitLabel,
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
    if (seller.length != 8) {
      return InvoiceRegistryCorroborationAuthorityDecision(
        sellerIdentifier: seller,
        authoritative: false,
        source: InvoiceRegistryCorroborationAuthoritySource.none,
        reason: 'seller_identifier_not_exact_8_digits',
      );
    }

    if (recognition.status == InvoiceAutomaticRecognitionStatus.qrReviewCandidate &&
        _qrSellerIdentifier(recognition) == seller) {
      return InvoiceRegistryCorroborationAuthorityDecision(
        sellerIdentifier: seller,
        authoritative: true,
        source: InvoiceRegistryCorroborationAuthoritySource.qrPayload,
        reason: 'authoritative_qr_payload',
      );
    }

    final ocr = recognition.ocrResult?.candidate;
    if (recognition.status == InvoiceAutomaticRecognitionStatus.ocrReviewCandidate &&
        ocr != null &&
        _digits(ocr.sellerTaxId) == seller &&
        ocr.sellerTaxIdSource == 'explicit_label' &&
        hasValidTaiwanTaxIdChecksum(seller)) {
      return InvoiceRegistryCorroborationAuthorityDecision(
        sellerIdentifier: seller,
        authoritative: true,
        source: InvoiceRegistryCorroborationAuthoritySource.traditionalExplicitLabel,
        reason: 'authoritative_traditional_explicit_label',
      );
    }

    return InvoiceRegistryCorroborationAuthorityDecision(
      sellerIdentifier: seller,
      authoritative: false,
      source: InvoiceRegistryCorroborationAuthoritySource.none,
      reason: 'invoice_evidence_not_authoritative_for_registry',
    );
  }

  String _qrSellerIdentifier(InvoiceAutomaticRecognitionResult recognition) {
    final pairs = recognition.qrResult?.routingResult?.pairs;
    if (pairs == null || pairs.isEmpty) return '';
    return _digits(pairs.first.left.leftParseResult.sellerIdentifier ?? '');
  }

  static String _digits(String value) =>
      value.replaceAll(RegExp(r'[^0-9]'), '');
}
