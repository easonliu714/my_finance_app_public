import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/invoice_automatic_recognition_coordinator.dart';
import 'package:my_finance_app/features/invoice/invoice_local_recognition_coordinator.dart';
import 'package:my_finance_app/features/invoice/invoice_qr_parser.dart';
import 'package:my_finance_app/features/invoice/invoice_recognition_router.dart';
import 'package:my_finance_app/features/invoice/invoice_review_form_view_model.dart';
import 'package:my_finance_app/features/invoice/invoice_review_handoff_contract.dart';
import 'package:my_finance_app/features/invoice/traditional_invoice_ocr_review.dart';

void main() {
  const presenter = InvoiceReviewFormPresenter();
  const handoffPresenter = InvoiceReviewHandoffPresenter();
  const leftPayload =
      'AB123456781150609123400000064000000780000000024531234abcdefghijklmnopqrstuvwx';

  test('QR handoff maps editable fields without raw payload disclosure', () {
    final parsed = const InvoiceQrParser().parse(leftPayload);
    final routing = InvoiceRecognitionRoutingResult(
      route: InvoiceRecognitionRoute.electronicInvoiceQr,
      message: 'QR candidate',
      pairs: <InvoiceQrPairCandidate>[
        InvoiceQrPairCandidate(
          left: InvoiceQrPayloadEvidence(
            imageReference: '/tmp/qr.jpg',
            fileName: 'qr.jpg',
            rawPayload: leftPayload,
            role: InvoiceQrPayloadRole.left,
            leftParseResult: parsed,
          ),
          warnings: const <String>['右碼缺漏，請人工確認。'],
        ),
      ],
    );
    final state = handoffPresenter.fromAutomaticResult(
      InvoiceAutomaticRecognitionResult(
        status: InvoiceAutomaticRecognitionStatus.qrReviewCandidate,
        message: 'QR ready',
        selectedRouteReason: '找到有效電子發票 QR，優先使用 QR 覆核路徑。',
        requestedRoute: InvoiceRecognitionRequestedRoute.automatic,
        qrResult: InvoiceLocalRecognitionResult(
          status: InvoiceLocalRecognitionStatus.qrCandidate,
          message: 'QR ready',
          failedImageReferences: const <String>[],
          routingResult: routing,
        ),
      ),
    );

    final model = presenter.fromHandoff(state);

    expect(model.canOpenReview, isTrue);
    expect(model.canSubmitForReview, isFalse);
    expect(model.canCreateFormalRecord, isFalse);
    expect(model.usedNetwork, isFalse);
    expect(
      model.fieldFor(InvoiceReviewFieldKey.invoiceNumber)?.value,
      'AB12345678',
    );
    expect(
      model.fieldFor(InvoiceReviewFieldKey.invoiceDate)?.value,
      '2026-06-09',
    );
    expect(
      model.fieldFor(InvoiceReviewFieldKey.totalAmount)?.value,
      '120',
    );
    expect(model.warnings, contains('右碼缺漏，請人工確認。'));
    expect(model.toSafeSummary().toString(), isNot(contains(leftPayload)));
  });

  test('partial OCR preserves blanks, confidence, warnings and line items', () {
    final state = handoffPresenter.fromAutomaticResult(
      const InvoiceAutomaticRecognitionResult(
        status: InvoiceAutomaticRecognitionStatus.ocrReviewCandidate,
        message: 'OCR partial',
        selectedRouteReason: '未找到有效電子發票 QR，改用本機傳統發票 OCR。',
        requestedRoute: InvoiceRecognitionRequestedRoute.automatic,
        ocrResult: TraditionalInvoiceOcrResult(
          status: TraditionalInvoiceOcrStatus.partial,
          message: 'OCR partial',
          candidate: TraditionalInvoiceOcrReviewCandidate(
            sourceImageReference: '/tmp/ocr.jpg',
            invoiceNumber: '',
            invoiceDate: null,
            sellerName: '測試商家',
            totalAmount: 168,
            visibleLineItems: <TraditionalInvoiceOcrLineItem>[
              TraditionalInvoiceOcrLineItem(
                name: '咖啡',
                amount: 68,
                confidence: TraditionalInvoiceOcrConfidence.medium,
              ),
            ],
            confidence: <TraditionalInvoiceOcrField,
                TraditionalInvoiceOcrConfidence>{
              TraditionalInvoiceOcrField.invoiceNumber:
                  TraditionalInvoiceOcrConfidence.low,
              TraditionalInvoiceOcrField.sellerName:
                  TraditionalInvoiceOcrConfidence.high,
              TraditionalInvoiceOcrField.totalAmount:
                  TraditionalInvoiceOcrConfidence.medium,
            },
            fieldWarnings: <TraditionalInvoiceOcrField, List<String>>{
              TraditionalInvoiceOcrField.invoiceNumber: <String>[
                '號碼模糊，請人工輸入。',
              ],
            },
          ),
        ),
      ),
    );

    final model = presenter.fromHandoff(state);

    expect(model.fieldFor(InvoiceReviewFieldKey.invoiceNumber)?.value, isEmpty);
    expect(
      model.fieldFor(InvoiceReviewFieldKey.invoiceNumber)?.confidenceLabel,
      '低',
    );
    expect(
      model.fieldFor(InvoiceReviewFieldKey.invoiceNumber)?.warnings,
      contains('號碼模糊，請人工輸入。'),
    );
    expect(
      model.fieldFor(InvoiceReviewFieldKey.sellerName)?.value,
      '測試商家',
    );
    expect(model.lineItems, hasLength(1));
    expect(model.lineItems.single.name, '咖啡');
    expect(model.lineItems.single.amountText, '68.0');
    expect(model.lineItems.single.confidenceLabel, '中');
    expect(model.canCreateFormalRecord, isFalse);
  });
}
