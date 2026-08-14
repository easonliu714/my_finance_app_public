import '../account/account_record.dart';
import 'credit_card_statement_service.dart';

class CreditCardMinimumPaymentRule {
  const CreditCardMinimumPaymentRule({
    required this.name,
    required this.revolvingBalanceRate,
    required this.currentPurchaseRate,
    required this.minimumFloor,
    required this.cashAdvanceMinimum,
    required this.feeMinimum,
    required this.includeEstimatedFees,
    required this.disclaimer,
  });

  factory CreditCardMinimumPaymentRule.defaultEstimate(CurrencyCode currency) {
    return CreditCardMinimumPaymentRule(
      name: '預設估算規則',
      revolvingBalanceRate: 0.10,
      currentPurchaseRate: 0.10,
      minimumFloor: currency == CurrencyCode.twd ? 1000 : 0,
      cashAdvanceMinimum: 0,
      feeMinimum: 0,
      includeEstimatedFees: true,
      disclaimer: '最低應繳為估算值，各銀行會依帳單、前期未繳、費用、利息、超額與預借現金等規則調整，請以銀行帳單為準。',
    );
  }

  final String name;
  final double revolvingBalanceRate;
  final double currentPurchaseRate;
  final double minimumFloor;
  final double cashAdvanceMinimum;
  final double feeMinimum;
  final bool includeEstimatedFees;
  final String disclaimer;
}

class CreditCardMinimumPaymentEstimate {
  const CreditCardMinimumPaymentEstimate({
    required this.card,
    required this.rule,
    required this.statementEstimate,
    required this.revolvingBalanceComponent,
    required this.currentPurchaseComponent,
    required this.cashAdvanceComponent,
    required this.feeComponent,
    required this.floorAdjustment,
    required this.estimatedMinimumDue,
    required this.isZeroBalance,
  });

  final AccountRecord card;
  final CreditCardMinimumPaymentRule rule;
  final CreditCardStatementEstimate statementEstimate;
  final double revolvingBalanceComponent;
  final double currentPurchaseComponent;
  final double cashAdvanceComponent;
  final double feeComponent;
  final double floorAdjustment;
  final double estimatedMinimumDue;
  final bool isZeroBalance;

  double get componentSubtotal => revolvingBalanceComponent + currentPurchaseComponent + cashAdvanceComponent + feeComponent;
}

CreditCardMinimumPaymentEstimate buildCreditCardMinimumPaymentEstimate(
  CreditCardStatementEstimate statementEstimate, {
  CreditCardMinimumPaymentRule? rule,
}) {
  final card = statementEstimate.card;
  final activeRule = rule ?? CreditCardMinimumPaymentRule.defaultEstimate(card.currency);
  final outstandingTotal = statementEstimate.outstandingTotal.clamp(0, double.infinity).toDouble();
  final currentPurchaseTotal = statementEstimate.purchaseTotal.clamp(0, outstandingTotal).toDouble();
  final revolvingBalance = (outstandingTotal - currentPurchaseTotal).clamp(0, double.infinity).toDouble();

  final revolvingBalanceComponent = card.currency.roundAmount(revolvingBalance * activeRule.revolvingBalanceRate);
  final currentPurchaseComponent = card.currency.roundAmount(currentPurchaseTotal * activeRule.currentPurchaseRate);
  final cashAdvanceComponent = card.currency.roundAmount(activeRule.cashAdvanceMinimum);
  final feeBase = activeRule.includeEstimatedFees ? activeRule.feeMinimum : 0.0;
  final feeComponent = card.currency.roundAmount(feeBase);
  final subtotal = card.currency.roundAmount(revolvingBalanceComponent + currentPurchaseComponent + cashAdvanceComponent + feeComponent);
  final isZeroBalance = outstandingTotal <= 0;
  final floorAdjustment = isZeroBalance || subtotal >= activeRule.minimumFloor ? 0.0 : card.currency.roundAmount(activeRule.minimumFloor - subtotal);
  final estimatedMinimumDue = isZeroBalance ? 0.0 : card.currency.roundAmount(subtotal + floorAdjustment);

  return CreditCardMinimumPaymentEstimate(
    card: card,
    rule: activeRule,
    statementEstimate: statementEstimate,
    revolvingBalanceComponent: revolvingBalanceComponent,
    currentPurchaseComponent: currentPurchaseComponent,
    cashAdvanceComponent: cashAdvanceComponent,
    feeComponent: feeComponent,
    floorAdjustment: floorAdjustment,
    estimatedMinimumDue: estimatedMinimumDue,
    isZeroBalance: isZeroBalance,
  );
}
