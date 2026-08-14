import 'package:uuid/uuid.dart';

import '../transaction/transaction_record.dart';
import '../transaction/transaction_type.dart';
import 'manual_invoice_draft.dart';

const String manualInvoiceNumberFormatError = '發票號碼格式必須為 2 碼英文字母 + 8 碼數字';
const String manualInvoiceNumberFormatWarning = '發票號碼格式不是常見的 2 碼英文字母 + 8 碼數字，仍可先作為草稿保存';

class ManualInvoiceValidationResult {
  const ManualInvoiceValidationResult({required this.isValid, required this.errors, required this.warnings});

  final bool isValid;
  final List<String> errors;
  final List<String> warnings;
}

class ManualInvoiceService {
  const ManualInvoiceService({Uuid uuid = const Uuid()}) : _uuid = uuid;

  final Uuid _uuid;

  ManualInvoiceDraft createDraft({
    required String invoiceNumber,
    required DateTime invoiceDate,
    required String sellerName,
    required double totalAmount,
    double? taxAmount,
    String note = '',
    DateTime? now,
  }) {
    final timestamp = now ?? DateTime.now().toUtc();
    final draft = ManualInvoiceDraft(
      id: _uuid.v4(),
      invoiceNumber: invoiceNumber,
      invoiceDate: invoiceDate,
      sellerName: sellerName,
      totalAmount: totalAmount,
      taxAmount: taxAmount,
      note: note,
      createdAt: timestamp,
      updatedAt: timestamp,
    );
    final validation = validate(draft);
    return draft.copyWith(status: validation.isValid ? ManualInvoiceDraftStatus.readyToReview : ManualInvoiceDraftStatus.draft);
  }

  ManualInvoiceValidationResult validate(ManualInvoiceDraft draft) {
    return _validate(draft, blockInvalidInvoiceFormat: false);
  }

  ManualInvoiceValidationResult validateForFormalTransaction(ManualInvoiceDraft draft) {
    return _validate(draft, blockInvalidInvoiceFormat: true);
  }

  ManualInvoiceValidationResult _validate(ManualInvoiceDraft draft, {required bool blockInvalidInvoiceFormat}) {
    final errors = <String>[];
    final warnings = <String>[];
    if (draft.invoiceNumber.trim().isEmpty) {
      errors.add('請輸入發票號碼');
    } else if (!_looksLikeTaiwanInvoiceNumber(draft.invoiceNumber)) {
      if (blockInvalidInvoiceFormat) {
        errors.add(manualInvoiceNumberFormatError);
      } else {
        warnings.add(manualInvoiceNumberFormatWarning);
      }
    }
    if (draft.sellerName.trim().isEmpty) errors.add('請輸入店家名稱');
    if (draft.totalAmount <= 0) errors.add('發票總額必須大於 0');
    final taxAmount = draft.taxAmount;
    if (taxAmount != null) {
      if (taxAmount < 0) errors.add('稅額不可小於 0');
      if (taxAmount > draft.totalAmount) warnings.add('稅額大於總額，請確認輸入是否正確');
    }
    return ManualInvoiceValidationResult(isValid: errors.isEmpty, errors: errors, warnings: warnings);
  }

  ManualInvoiceTransactionDraft buildTransactionDraft(ManualInvoiceDraft invoice) {
    final validation = validateForFormalTransaction(invoice);
    if (!validation.isValid) {
      throw StateError('manual invoice is not ready for transaction draft: ${validation.errors.join(', ')}');
    }
    final invoiceNumber = invoice.invoiceNumber.trim().toUpperCase();
    final noteParts = <String>['發票：$invoiceNumber'];
    final note = invoice.note.trim();
    if (note.isNotEmpty) noteParts.add(note);
    return ManualInvoiceTransactionDraft(
      invoiceDraftId: invoice.id,
      occurredAt: invoice.invoiceDate,
      amount: invoice.totalAmount,
      merchantName: invoice.sellerName.trim(),
      note: noteParts.join('｜'),
    );
  }

  TransactionRecord confirmAsExpenseTransaction({
    required ManualInvoiceDraft invoice,
    required String accountName,
    String category = '全部',
    String memberName = '自己',
    String tagName = '日常',
    String? transactionId,
  }) {
    final draft = buildTransactionDraft(invoice);
    final trimmedAccount = accountName.trim();
    if (trimmedAccount.isEmpty) throw StateError('請選擇付款帳戶');
    return TransactionRecord(
      id: transactionId ?? _uuid.v4(),
      type: TransactionType.expense,
      amount: draft.amount,
      category: category,
      occurredAt: draft.occurredAt,
      accountName: trimmedAccount,
      memberName: memberName,
      merchantName: draft.merchantName,
      tagName: tagName,
      note: draft.note,
    );
  }
}

bool _looksLikeTaiwanInvoiceNumber(String value) {
  return RegExp(r'^[A-Za-z]{2}\d{8}$').hasMatch(value.trim());
}
