import 'package:my_finance_app/database/production_schema_v13.dart';
import 'package:my_finance_app/features/account/account_record.dart';
import 'package:my_finance_app/features/invoice/cloud_invoice_candidate.dart';
import 'package:my_finance_app/features/invoice/lab/cloud_invoice_persistence_models.dart';
import 'package:my_finance_app/features/invoice/lab/cloud_invoice_persistence_ports.dart';
import 'package:my_finance_app/features/invoice/lab/cloud_invoice_reconciliation_models.dart';
import 'package:my_finance_app/features/invoice/lab/cloud_invoice_reconciliation_review_decision.dart';
import 'package:my_finance_app/features/transaction/transaction_record.dart';
import 'package:my_finance_app/features/transaction/transaction_type.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<Database> openCanonicalPersistenceTestDatabase() async {
  final db = await openDatabase(
    inMemoryDatabasePath,
    singleInstance: false,
  );
  await db.execute('''
    CREATE TABLE transactions (
      id TEXT PRIMARY KEY,
      type TEXT NOT NULL,
      amount REAL NOT NULL,
      category TEXT NOT NULL,
      occurred_at TEXT NOT NULL,
      account_name TEXT NOT NULL,
      member_name TEXT NOT NULL,
      merchant_name TEXT NOT NULL,
      tag_name TEXT NOT NULL,
      note TEXT NOT NULL,
      currency_code TEXT NOT NULL,
      exchange_rate_to_base REAL NOT NULL,
      base_amount REAL NOT NULL,
      from_account_name TEXT,
      to_account_name TEXT,
      repayment_group_id TEXT,
      created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
    )
  ''');
  await db.execute('''
    CREATE TABLE accounts (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      type TEXT NOT NULL,
      initial_balance REAL NOT NULL,
      sort_order INTEGER NOT NULL,
      suffix TEXT NOT NULL,
      currency_code TEXT NOT NULL,
      credit_limit REAL NOT NULL DEFAULT 0,
      statement_day INTEGER NOT NULL DEFAULT 1,
      payment_due_day INTEGER NOT NULL DEFAULT 1,
      payment_reminder_enabled INTEGER NOT NULL DEFAULT 0,
      reminder_days_before INTEGER NOT NULL DEFAULT 3,
      loan_principal REAL NOT NULL DEFAULT 0,
      annual_interest_rate REAL NOT NULL DEFAULT 0,
      loan_term_months INTEGER NOT NULL DEFAULT 0,
      loan_repayment_method TEXT NOT NULL DEFAULT 'equalPrincipalAndInterest',
      loan_payment_due_day INTEGER NOT NULL DEFAULT 1,
      loan_reminder_enabled INTEGER NOT NULL DEFAULT 0,
      loan_reminder_days_before INTEGER NOT NULL DEFAULT 3,
      loan_start_date TEXT,
      loan_disbursement_account_name TEXT NOT NULL DEFAULT '',
      loan_handling_fee REAL NOT NULL DEFAULT 0,
      loan_disbursement_created INTEGER NOT NULL DEFAULT 0,
      note TEXT NOT NULL DEFAULT '',
      is_archived INTEGER NOT NULL DEFAULT 0
    )
  ''');
  await createCanonicalProductionV13Tables(db);
  return db;
}

Future<void> insertTestAccount(Database db, AccountRecord account) async {
  await db.insert('accounts', account.toMap());
}

Future<void> insertTestTransaction(
  Database db,
  TransactionRecord transaction,
) async {
  await db.insert('transactions', transaction.toMap());
}

AccountRecord testAccount({
  String id = 'account-1',
  String name = '現金',
  CurrencyCode currency = CurrencyCode.twd,
  bool archived = false,
}) {
  return AccountRecord(
    id: id,
    name: name,
    type: AccountType.cash,
    initialBalance: 0,
    sortOrder: 0,
    currency: currency,
    isArchived: archived,
  );
}

TransactionRecord testTransaction({
  String id = 'transaction-1',
  double amount = 100,
  String merchantName = '原商家',
  String note = '原備註',
}) {
  return TransactionRecord(
    id: id,
    type: TransactionType.expense,
    amount: amount,
    category: '餐飲',
    occurredAt: DateTime(2026, 6, 18, 9, 30),
    accountName: '現金',
    memberName: '',
    merchantName: merchantName,
    tagName: '午餐',
    note: note,
    currency: CurrencyCode.twd,
  );
}

CloudInvoiceCandidateFacts testFacts({
  double amount = 100,
  String sellerName = '測試商家',
  String? currencyCode,
  double? taxAmount,
  CloudInvoiceTimePrecision timePrecision = CloudInvoiceTimePrecision.dateOnly,
}) {
  return CloudInvoiceCandidateFacts(
    candidate: CloudInvoiceCandidate(
      source: CloudInvoiceCandidateSource.privateCloudResearch,
      status: CloudInvoiceCandidateStatus.pending,
      invoiceNumber: 'AB12345678',
      invoiceDate: timePrecision == CloudInvoiceTimePrecision.exactDateTime
          ? DateTime(2026, 6, 18, 11, 45, 50)
          : DateTime(2026, 6, 18),
      sellerIdentifier: '12345678',
      sellerName: sellerName,
      totalAmount: amount,
      taxAmount: taxAmount,
      carrierType: '手機條碼',
      carrierMaskedId: '',
      fetchedAt: DateTime.utc(2026, 6, 18),
      lineItems: <CloudInvoiceLineItem>[
        CloudInvoiceLineItem(name: '測試品項', amount: amount),
      ],
    ),
    timePrecision: timePrecision,
    timeSource: timePrecision == CloudInvoiceTimePrecision.exactDateTime
        ? CloudInvoiceTimeSource.officialInvoiceIssuedAt
        : CloudInvoiceTimeSource.unknown,
    currencyCode: currencyCode,
    currencySource: currencyCode == null
        ? CloudInvoiceCurrencySource.unknown
        : CloudInvoiceCurrencySource.officialDetail,
  );
}

CloudInvoicePersistenceRequest testRequest({
  required CloudInvoiceCandidateFacts facts,
  required CloudInvoiceReconciliationOutcome action,
  String? transactionId,
  String? accountId,
  String? expectedTransactionFingerprint,
  String? expectedAccountFingerprint,
  bool merchantConfirmed = false,
  bool replacementConfirmed = false,
}) {
  return CloudInvoicePersistenceRequest(
    facts: facts,
    decision: CloudInvoiceReconciliationReviewDecision(
      action: action,
      selectedTransactionId: transactionId,
      selectedAccountId: accountId,
      merchantProposalReviewed: true,
      merchantProposalConfirmed: merchantConfirmed,
      replacementSecondConfirmationCompleted: replacementConfirmed,
      candidateReference: facts.candidate.duplicateKey,
      decidedAt: DateTime.utc(2026, 6, 18, 11),
    ),
    expectedTransactionFingerprint: expectedTransactionFingerprint,
    expectedAccountFingerprint: expectedAccountFingerprint,
    requestedAt: DateTime.utc(2026, 6, 18, 12),
  );
}

class FixedPersistenceClock implements CloudInvoicePersistenceClock {
  @override
  DateTime now() => DateTime.utc(2026, 6, 18, 12);
}

class SequencePersistenceIds implements CloudInvoicePersistenceIdGenerator {
  final Map<String, int> _counts = <String, int>{};

  @override
  String nextId(String namespace) {
    final next = (_counts[namespace] ?? 0) + 1;
    _counts[namespace] = next;
    return '$namespace-$next';
  }
}
