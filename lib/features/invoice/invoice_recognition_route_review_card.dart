import 'package:flutter/material.dart';

import 'invoice_automatic_recognition_coordinator.dart';
import 'invoice_recognition_disclaimer.dart';

class InvoiceRecognitionRouteReviewCard extends StatelessWidget {
  const InvoiceRecognitionRouteReviewCard({
    super.key,
    required this.result,
    this.onUseAutomatic,
    this.onUseQr,
    this.onUseOcr,
  });

  static const Key cardKey = Key('invoice_recognition_route_review_card');
  static const Key automaticKey = Key('invoice_route_automatic');
  static const Key qrKey = Key('invoice_route_qr');
  static const Key ocrKey = Key('invoice_route_ocr');
  static const Key disclaimerKey = Key('invoice_route_disclaimer');
  static const Key reasonKey = Key('invoice_route_reason');

  final InvoiceAutomaticRecognitionResult result;
  final VoidCallback? onUseAutomatic;
  final VoidCallback? onUseQr;
  final VoidCallback? onUseOcr;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: cardKey,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.alt_route_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '辨識路徑確認',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Tooltip(
                  message: '可在進入覆核前改用 QR 或傳統發票 OCR；所有結果仍需人工確認。',
                  child: Icon(
                    Icons.help_outline,
                    size: 20,
                    color: theme.colorScheme.secondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _statusLabel(result.status),
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(result.selectedRouteReason, key: reasonKey),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  key: automaticKey,
                  label: const Text('自動判定'),
                  selected: result.requestedRoute ==
                      InvoiceRecognitionRequestedRoute.automatic,
                  onSelected: onUseAutomatic == null
                      ? null
                      : (selected) {
                          if (selected) onUseAutomatic!();
                        },
                ),
                ChoiceChip(
                  key: qrKey,
                  label: const Text('指定 QR'),
                  selected: result.requestedRoute ==
                      InvoiceRecognitionRequestedRoute.electronicInvoiceQr,
                  onSelected: onUseQr == null
                      ? null
                      : (selected) {
                          if (selected) onUseQr!();
                        },
                ),
                ChoiceChip(
                  key: ocrKey,
                  label: const Text('指定 OCR'),
                  selected: result.requestedRoute ==
                      InvoiceRecognitionRequestedRoute.traditionalInvoiceOcr,
                  onSelected: onUseOcr == null
                      ? null
                      : (selected) {
                          if (selected) onUseOcr!();
                        },
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              InvoiceRecognitionDisclaimer.text,
              key: disclaimerKey,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _statusLabel(InvoiceAutomaticRecognitionStatus status) {
    switch (status) {
      case InvoiceAutomaticRecognitionStatus.qrReviewCandidate:
        return '目前路徑：電子發票 QR 覆核';
      case InvoiceAutomaticRecognitionStatus.ocrReviewCandidate:
        return '目前路徑：傳統發票 OCR 覆核';
      case InvoiceAutomaticRecognitionStatus.manualQrDesignation:
        return '目前路徑：人工指定 QR';
      case InvoiceAutomaticRecognitionStatus.recognitionFailed:
        return '目前狀態：尚未建立覆核候選';
      case InvoiceAutomaticRecognitionStatus.invalidInput:
        return '目前狀態：影像輸入無效';
    }
  }
}
