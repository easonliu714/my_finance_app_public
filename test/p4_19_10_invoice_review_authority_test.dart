import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/invoice_review_authority_contract.dart';
import 'package:my_finance_app/features/invoice/invoice_review_authority_runtime_adapter.dart';
import 'package:my_finance_app/features/invoice/invoice_review_form_view_model.dart';

void main() {
  test('explicit AI selection is formal authority for transaction core fields', () {
    const adapter = InvoiceReviewAuthorityRuntimeAdapter();
    const field = InvoiceReviewFieldViewModel(
      key: InvoiceReviewFieldKey.totalAmount,
      label: '總金額',
      value: '120',
      editable: true,
      requiredForReview: true,
      confidenceLabel: 'AI',
    );

    final authority = adapter.authorityForField(
      field,
      explicitlyAiSelected: true,
    );

    expect(authority?.state, InvoiceReviewAuthorityState.authoritative);
    expect(authority?.source, InvoiceReviewAuthoritySource.explicitAiSelection);
    expect(authority?.isFormalHandoffAuthority, isTrue);
  });

  test('AI merchant selection stays candidate until explicit master binding', () {
    const adapter = InvoiceReviewAuthorityRuntimeAdapter();
    const field = InvoiceReviewFieldViewModel(
      key: InvoiceReviewFieldKey.sellerName,
      label: '商家名稱',
      value: 'AI 商家',
      editable: true,
      requiredForReview: false,
      confidenceLabel: 'AI',
    );

    final authority = adapter.authorityForField(
      field,
      explicitlyAiSelected: true,
    );

    expect(authority?.state, InvoiceReviewAuthorityState.supplemental);
    expect(authority?.source, InvoiceReviewAuthoritySource.explicitAiSelection);
    expect(authority?.isFormalHandoffAuthority, isFalse);
  });
}
