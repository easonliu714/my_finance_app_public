import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/daily_capture_entry_shell.dart';
import 'package:my_finance_app/features/invoice/invoice_automatic_recognition_coordinator.dart';
import 'package:my_finance_app/features/invoice/invoice_recognition_disclaimer.dart';
import 'package:my_finance_app/features/invoice/invoice_recognition_route_review_card.dart';

void main() {
  testWidgets('capture entry keeps invoice disclaimer visible', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: DailyCaptureEntryCard(),
          ),
        ),
      ),
    );

    expect(find.byKey(DailyCaptureEntryCard.disclaimerKey), findsOneWidget);
    expect(find.text(InvoiceRecognitionDisclaimer.text), findsOneWidget);
  });

  testWidgets('route card shows selected route reason and disclaimer',
      (tester) async {
    const result = InvoiceAutomaticRecognitionResult(
      status: InvoiceAutomaticRecognitionStatus.ocrReviewCandidate,
      message: 'OCR candidate',
      selectedRouteReason: '未找到有效 QR，改用本機傳統發票 OCR。',
      requestedRoute: InvoiceRecognitionRequestedRoute.automatic,
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: InvoiceRecognitionRouteReviewCard(result: result),
        ),
      ),
    );

    expect(
      find.byKey(InvoiceRecognitionRouteReviewCard.cardKey),
      findsOneWidget,
    );
    expect(find.text('目前路徑：傳統發票 OCR 覆核'), findsOneWidget);
    expect(
      find.byKey(InvoiceRecognitionRouteReviewCard.reasonKey),
      findsOneWidget,
    );
    expect(
      find.byKey(InvoiceRecognitionRouteReviewCard.disclaimerKey),
      findsOneWidget,
    );
    expect(find.text(InvoiceRecognitionDisclaimer.text), findsOneWidget);
  });

  testWidgets('route card invokes explicit QR and OCR overrides',
      (tester) async {
    var qrTapCount = 0;
    var ocrTapCount = 0;
    const result = InvoiceAutomaticRecognitionResult(
      status: InvoiceAutomaticRecognitionStatus.qrReviewCandidate,
      message: 'QR candidate',
      selectedRouteReason: '找到有效電子發票 QR。',
      requestedRoute: InvoiceRecognitionRequestedRoute.automatic,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InvoiceRecognitionRouteReviewCard(
            result: result,
            onUseQr: () => qrTapCount += 1,
            onUseOcr: () => ocrTapCount += 1,
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(InvoiceRecognitionRouteReviewCard.qrKey));
    await tester.pump();
    await tester.tap(find.byKey(InvoiceRecognitionRouteReviewCard.ocrKey));
    await tester.pump();

    expect(qrTapCount, 1);
    expect(ocrTapCount, 1);
  });

  testWidgets('selected override chip reflects requested route',
      (tester) async {
    const result = InvoiceAutomaticRecognitionResult(
      status: InvoiceAutomaticRecognitionStatus.ocrReviewCandidate,
      message: 'OCR candidate',
      selectedRouteReason: '使用者改用 OCR。',
      requestedRoute:
          InvoiceRecognitionRequestedRoute.traditionalInvoiceOcr,
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: InvoiceRecognitionRouteReviewCard(result: result),
        ),
      ),
    );

    final automaticChip = tester.widget<ChoiceChip>(
      find.byKey(InvoiceRecognitionRouteReviewCard.automaticKey),
    );
    final ocrChip = tester.widget<ChoiceChip>(
      find.byKey(InvoiceRecognitionRouteReviewCard.ocrKey),
    );

    expect(automaticChip.selected, isFalse);
    expect(ocrChip.selected, isTrue);
  });
}
