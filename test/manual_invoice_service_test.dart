import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/manual_invoice_draft.dart';
import 'package:my_finance_app/features/invoice/manual_invoice_service.dart';
import 'package:my_finance_app/features/transaction/transaction_type.dart';

void main() {
  const service = ManualInvoiceService();

  test('createDraft marks valid manual invoice ready for review', () {
    final draft = service.createDraft(
      invoiceNumber: 'AB12345678',
      invoiceDate: DateTime(2026, 6, 9),
      sellerName: '測試便利商店',
      totalAmount: 120,
      taxAmount: 6,
      note: '咖啡與早餐',
      now: DateTime.utc(2026, 6, 9, 1, 2, 3),
    );

    expect(draft.status, ManualInvoiceDraftStatus.readyToReview);
    expect(draft.invoiceNumber, 'AB12345678');
    expect(draft.duplicateKey, 'AB12345678|2026-06-09|120|測試便利商店');
    expect(draft.createdAt, DateTime.utc(2026, 6, 9, 1, 2, 3));
  });

  test('validate blocks missing required values but keeps invoice format as draft warning', () {
    final draft = ManualInvoiceDraft(
      id: 'draft-1',
      invoiceNumber: 'bad-format',
      invoiceDate: DateTime(2026, 6, 9),
      sellerName: '',
      totalAmount: 0,
    );

    final result = service.validate(draft);

    expect(result.isValid, isFalse);
    expect(result.errors, contains('請輸入店家名稱'));
    expect(result.errors, contains('發票總額必須大於 0'));
    expect(result.errors, isNot(contains(manualInvoiceNumberFormatError)));
    expect(result.warnings, contains(manualInvoiceNumberFormatWarning));
  });

  test('validate allows saving invalid invoice format as local draft warning', () {
    final draft = ManualInvoiceDraft(
      id: 'draft-1',
      invoiceNumber: 'bad-format',
      invoiceDate: DateTime(2026, 6, 9),
      sellerName: '測試便利商店',
      totalAmount: 120,
    );

    final result = service.validate(draft);

    expect(result.isValid, isTrue);
    expect(result.errors, isEmpty);
    expect(result.warnings, contains(manualInvoiceNumberFormatWarning));
  });

  test('validateForFormalTransaction blocks invalid invoice number format', () {
    final draft = ManualInvoiceDraft(
      id: 'draft-1',
      invoiceNumber: 'bad-format',
      invoiceDate: DateTime(2026, 6, 9),
      sellerName: '測試便利商店',
      totalAmount: 120,
    );

    final result = service.validateForFormalTransaction(draft);

    expect(result.isValid, isFalse);
    expect(result.errors, contains(manualInvoiceNumberFormatError));
    expect(result.warnings, isEmpty);
  });

  test('buildTransactionDraft rejects invalid invoice number format', () {
    final draft = ManualInvoiceDraft(
      id: 'draft-1',
      invoiceNumber: 'bad-format',
      invoiceDate: DateTime(2026, 6, 9),
      sellerName: '測試便利商店',
      totalAmount: 120,
    );

    expect(
      () => service.buildTransactionDraft(draft),
      throwsA(isA<StateError>()),
    );
  });

  test('confirmAsExpenseTransaction rejects invalid invoice number format', () {
    final draft = ManualInvoiceDraft(
      id: 'draft-1',
      invoiceNumber: 'bad-format',
      invoiceDate: DateTime(2026, 6, 9),
      sellerName: '測試便利商店',
      totalAmount: 120,
    );

    expect(
      () => service.confirmAsExpenseTransaction(invoice: draft, accountName: '現金'),
      throwsA(isA<StateError>()),
    );
  });

  test('buildTransactionDraft keeps invoice trace in note', () {
    final draft = ManualInvoiceDraft(
      id: 'draft-1',
      invoiceNumber: 'ab12345678',
      invoiceDate: DateTime(2026, 6, 9),
      sellerName: 'TEST-CONVENIENCE',
      totalAmount: 99,
      note: '飲料',
    );

    final transactionDraft = service.buildTransactionDraft(draft);

    expect(transactionDraft.invoiceDraftId, 'draft-1');
    expect(transactionDraft.amount, 99);
    expect(transactionDraft.merchantName, 'TEST-CONVENIENCE');
    expect(transactionDraft.note, '發票：AB12345678｜飲料');
  });

  test('buildTransactionDraft preserves invoice date and time', () {
    final draft = ManualInvoiceDraft(
      id: 'draft-1',
      invoiceNumber: 'AB12345678',
      invoiceDate: DateTime(2026, 6, 9, 14, 35),
      sellerName: '測試便利商店',
      totalAmount: 120,
    );

    final transactionDraft = service.buildTransactionDraft(draft);

    expect(transactionDraft.occurredAt, DateTime(2026, 6, 9, 14, 35));
  });

  test('confirmAsExpenseTransaction requires account and returns explicit transaction candidate', () {
    final draft = ManualInvoiceDraft(
      id: 'draft-1',
      invoiceNumber: 'AB12345678',
      invoiceDate: DateTime(2026, 6, 9),
      sellerName: '測試餐飲商店',
      totalAmount: 155,
    );

    final record = service.confirmAsExpenseTransaction(
      invoice: draft,
      accountName: '現金',
      category: '午餐',
      transactionId: 'tx-1',
    );

    expect(record.id, 'tx-1');
    expect(record.type, TransactionType.expense);
    expect(record.amount, 155);
    expect(record.category, '午餐');
    expect(record.accountName, '現金');
    expect(record.merchantName, '測試餐飲商店');
    expect(record.note, '發票：AB12345678');
  });

  test('confirmAsExpenseTransaction preserves invoice date and time', () {
    final draft = ManualInvoiceDraft(
      id: 'draft-1',
      invoiceNumber: 'AB12345678',
      invoiceDate: DateTime(2026, 6, 9, 14, 35),
      sellerName: '測試餐飲商店',
      totalAmount: 155,
    );

    final record = service.confirmAsExpenseTransaction(
      invoice: draft,
      accountName: '現金',
      transactionId: 'tx-time-1',
    );

    expect(record.occurredAt, DateTime(2026, 6, 9, 14, 35));
  });

  test('confirmAsExpenseTransaction rejects empty account', () {
    final draft = ManualInvoiceDraft(
      id: 'draft-1',
      invoiceNumber: 'AB12345678',
      invoiceDate: DateTime(2026, 6, 9),
      sellerName: '店家',
      totalAmount: 100,
    );

    expect(
      () => service.confirmAsExpenseTransaction(invoice: draft, accountName: ' '),
      throwsA(isA<StateError>()),
    );
  });
}
