import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/invoice_seller_tax_id_confirmation.dart';
import 'package:my_finance_app/features/invoice/invoice_seller_tax_id_confirmation_card.dart';

void main() {
  testWidgets('weak OCR requires explicit confirmation before authority',
      (tester) async {
    InvoiceSellerTaxIdConfirmationState? confirmed;
    const initial = InvoiceSellerTaxIdConfirmationState(
      currentSellerTaxId: '31655572',
      currentSourceToken: 'ocr',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InvoiceSellerTaxIdConfirmationCard(
            state: initial,
            onConfirm: (value) => confirmed = value,
          ),
        ),
      ),
    );

    expect(find.text('辨識值：31655572'), findsOneWidget);
    expect(find.text('已確認賣方統編：尚未確認'), findsOneWidget);
    expect(find.byKey(InvoiceSellerTaxIdConfirmationCard.confirmKey), findsOneWidget);

    await tester.tap(find.byKey(InvoiceSellerTaxIdConfirmationCard.confirmKey));
    await tester.pump();

    expect(confirmed, isNotNull);
    expect(confirmed!.explicitlyConfirmedForCurrentValue, isTrue);
    expect(confirmed!.normalizedSellerTaxId, '31655572');
  });

  testWidgets('60282181 is confirmable without Registry-derived authority',
      (tester) async {
    InvoiceSellerTaxIdConfirmationState? confirmed;
    const initial = InvoiceSellerTaxIdConfirmationState(
      currentSellerTaxId: '60282181',
      currentSourceToken: 'ai',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InvoiceSellerTaxIdConfirmationCard(
            state: initial,
            onConfirm: (value) => confirmed = value,
          ),
        ),
      ),
    );

    final button = tester.widget<FilledButton>(
      find.byKey(InvoiceSellerTaxIdConfirmationCard.confirmKey),
    );
    expect(button.onPressed, isNotNull);

    await tester.tap(find.byKey(InvoiceSellerTaxIdConfirmationCard.confirmKey));
    await tester.pump();
    expect(confirmed!.explicitlyConfirmedForCurrentValue, isTrue);
  });

  testWidgets('invalid seller tax id keeps explicit confirmation disabled',
      (tester) async {
    const initial = InvoiceSellerTaxIdConfirmationState(
      currentSellerTaxId: '60744699',
      currentSourceToken: 'ocr',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InvoiceSellerTaxIdConfirmationCard(
            state: initial,
            onConfirm: (_) => fail('invalid sellerTaxId must not confirm'),
          ),
        ),
      ),
    );

    final button = tester.widget<FilledButton>(
      find.byKey(InvoiceSellerTaxIdConfirmationCard.confirmKey),
    );
    expect(button.onPressed, isNull);
    expect(
      find.text('目前統編不是可確認的有效 8 碼統編，Registry lookup 保持停用。'),
      findsOneWidget,
    );
  });

  testWidgets('trusted QR is authoritative without duplicating user action',
      (tester) async {
    const initial = InvoiceSellerTaxIdConfirmationState(
      currentSellerTaxId: '31655572',
      currentSourceToken: 'qr_payload',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InvoiceSellerTaxIdConfirmationCard(
            state: initial,
            trustedQrAuthority: true,
            onConfirm: (_) => fail('trusted QR must not need duplicate confirmation'),
          ),
        ),
      ),
    );

    expect(find.text('已確認賣方統編：31655572（QR 權威）'), findsOneWidget);
    expect(find.byKey(InvoiceSellerTaxIdConfirmationCard.confirmKey), findsNothing);
  });
}
