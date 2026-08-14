import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/cloud_invoice_award_governance_card.dart';

void main() {
  testWidgets('CloudInvoiceAwardGovernanceCard renders portal and governance copy', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CloudInvoiceAwardGovernanceCard(),
        ),
      ),
    );

    expect(find.byKey(CloudInvoiceAwardGovernanceCard.cardKey), findsOneWidget);
    expect(find.byKey(CloudInvoiceAwardGovernanceCard.portalLinkKey), findsOneWidget);
    expect(find.byKey(CloudInvoiceAwardGovernanceCard.summaryKey), findsOneWidget);
    expect(find.text('雲端發票與對獎治理'), findsOneWidget);
    expect(find.text('財政部電子發票整合服務平台'), findsOneWidget);
    expect(find.textContaining('不在 App 內保管憑證'), findsOneWidget);
    expect(find.text('https://www.einvoice.nat.gov.tw/'), findsOneWidget);
    expect(find.text('對獎候選：0，待審核：0'), findsOneWidget);
    expect(find.textContaining('不保管官方平台帳密'), findsOneWidget);
    expect(find.textContaining('不會自動建立交易'), findsOneWidget);
  });

  testWidgets('CloudInvoiceAwardGovernanceCard renders candidate summary', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CloudInvoiceAwardGovernanceCard(candidateCount: 3, reviewCount: 2),
        ),
      ),
    );

    expect(find.text('對獎候選：3，待審核：2'), findsOneWidget);
  });
}
