import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import '../account/account_record.dart';
import 'debit_card_settlement.dart';
import 'transaction_record.dart';

enum DebitCardSettlementConfirmationErrorCode {
  invalidRequest,
  settlementNotFound,
  settlementNotPending,
  settlementConflict,
  sourceTransactionNotFound,
  debitCardAccountNotFound,
  debitCardAccountArchived,
  debitCardAccountInvalid,
  linkedBankAccountNotFound,
  linkedBankAccountArchived,
  linkedBankAccountInvalid,
  profileNotFound,
  profileDisabled,
  profileMismatch,
  currencyMismatch,
  amountMismatch,
  transferTransactionConflict,
  replayConflict,
  concurrentModification,
  confirmedTransferImmutable,
}

class DebitCardSettlementConfirmationException implements Exception {
  const DebitCardSettlementConfirmationException(
    this.code,
    this.message,
  );

  final DebitCardSettlementConfirmationErrorCode code;
  final String message;

  String get userMessage => switch (code) {
        DebitCardSettlementConfirmationErrorCode.invalidRequest =>
          '扣款確認資料不完整，請重新確認。',
        DebitCardSettlementConfirmationErrorCode.settlementNotFound =>
          '找不到指定的簽帳金融卡待扣款資料。',
        DebitCardSettlementConfirmationErrorCode.settlementNotPending =>
          '此筆待扣款已不是可確認狀態。',
        DebitCardSettlementConfirmationErrorCode.settlementConflict =>
          '此筆待扣款已有不同的確認紀錄，已停止寫入。',
        DebitCardSettlementConfirmationErrorCode.sourceTransactionNotFound =>
          '找不到此筆待扣款的來源消費。',
        DebitCardSettlementConfirmationErrorCode.debitCardAccountNotFound =>
          '找不到來源簽帳金融卡帳戶。',
        DebitCardSettlementConfirmationErrorCode.debitCardAccountArchived =>
          '來源簽帳金融卡帳戶已封存，無法確認扣款。',
        DebitCardSettlementConfirmationErrorCode.debitCardAccountInvalid =>
          '來源帳戶不是有效的簽帳金融卡帳戶。',
        DebitCardSettlementConfirmationErrorCode.linkedBankAccountNotFound =>
          '找不到綁定的銀行帳戶。',
        DebitCardSettlementConfirmationErrorCode.linkedBankAccountArchived =>
          '綁定的銀行帳戶已封存，無法確認扣款。',
        DebitCardSettlementConfirmationErrorCode.linkedBankAccountInvalid =>
          '綁定的扣款帳戶不是有效的銀行帳戶。',
        DebitCardSettlementConfirmationErrorCode.profileNotFound =>
          '找不到此簽帳金融卡的扣款帳戶設定。',
        DebitCardSettlementConfirmationErrorCode.profileDisabled =>
          '此簽帳金融卡設定已停用。',
        DebitCardSettlementConfirmationErrorCode.profileMismatch =>
          '簽帳金融卡設定與待扣款資料不一致。',
        DebitCardSettlementConfirmationErrorCode.currencyMismatch =>
          '待扣款、來源交易與帳戶幣別不一致。',
        DebitCardSettlementConfirmationErrorCode.amountMismatch =>
          '待扣款金額與來源消費金額不一致。',
        DebitCardSettlementConfirmationErrorCode.transferTransactionConflict =>
          '扣款轉帳識別碼已被使用，已停止寫入。',
        DebitCardSettlementConfirmationErrorCode.replayConflict =>
          '偵測到重複確認要求，但內容不一致，已停止寫入。',
        DebitCardSettlementConfirmationErrorCode.concurrentModification =>
          '待扣款狀態已被其他操作更新，請重新整理後再確認。',
        DebitCardSettlementConfirmationErrorCode.confirmedTransferImmutable =>
          '此筆轉帳屬於已確認的簽帳金融卡扣款，無法直接編輯或刪除。',
      };

  @override
  String toString() => userMessage;
}

class DebitCardSettlementConfirmationRequest {
  const DebitCardSettlementConfirmationRequest({
    required this.requestId,
    required this.settlementId,
    required this.transferTransactionId,
    required this.confirmedAt,
  });

  final String requestId;
  final String settlementId;
  final String transferTransactionId;
  final DateTime confirmedAt;

  String get normalizedRequestId => requestId.trim();
  String get normalizedSettlementId => settlementId.trim();
  String get normalizedTransferTransactionId => transferTransactionId.trim();

  Future<String> payloadFingerprint() async {
    final canonical = jsonEncode(<String, Object?>{
      'settlement_id': normalizedSettlementId,
      'transfer_transaction_id': normalizedTransferTransactionId,
      'confirmed_at': confirmedAt.toUtc().toIso8601String(),
    });
    final digest = await Sha256().hash(utf8.encode(canonical));
    return digest.bytes
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
  }
}

class DebitCardSettlementConfirmationAuditRecord {
  const DebitCardSettlementConfirmationAuditRecord({
    required this.requestId,
    required this.payloadFingerprint,
    required this.settlementId,
    required this.sourceTransactionId,
    required this.transferTransactionId,
    required this.debitCardAccountId,
    required this.linkedBankAccountId,
    required this.amount,
    required this.currency,
    required this.ledgerBalanceBefore,
    required this.reservedBefore,
    required this.availableBefore,
    required this.ledgerBalanceAfter,
    required this.reservedAfter,
    required this.availableAfter,
    required this.confirmedAt,
    required this.statusBefore,
    required this.statusAfter,
  });

  factory DebitCardSettlementConfirmationAuditRecord.fromMap(
    Map<String, Object?> map,
  ) {
    return DebitCardSettlementConfirmationAuditRecord(
      requestId: map['request_id'] as String,
      payloadFingerprint: map['payload_fingerprint'] as String,
      settlementId: map['settlement_id'] as String,
      sourceTransactionId: map['source_transaction_id'] as String,
      transferTransactionId: map['transfer_transaction_id'] as String,
      debitCardAccountId: map['debit_card_account_id'] as String,
      linkedBankAccountId: map['linked_bank_account_id'] as String,
      amount: (map['amount'] as num).toDouble(),
      currency: currencyFromCode(map['currency_code'] as String?),
      ledgerBalanceBefore:
          (map['ledger_balance_before'] as num).toDouble(),
      reservedBefore: (map['reserved_before'] as num).toDouble(),
      availableBefore: (map['available_before'] as num).toDouble(),
      ledgerBalanceAfter: (map['ledger_balance_after'] as num).toDouble(),
      reservedAfter: (map['reserved_after'] as num).toDouble(),
      availableAfter: (map['available_after'] as num).toDouble(),
      confirmedAt: DateTime.parse(map['confirmed_at'] as String),
      statusBefore: map['status_before'] as String,
      statusAfter: map['status_after'] as String,
    );
  }

  final String requestId;
  final String payloadFingerprint;
  final String settlementId;
  final String sourceTransactionId;
  final String transferTransactionId;
  final String debitCardAccountId;
  final String linkedBankAccountId;
  final double amount;
  final CurrencyCode currency;
  final double ledgerBalanceBefore;
  final double reservedBefore;
  final double availableBefore;
  final double ledgerBalanceAfter;
  final double reservedAfter;
  final double availableAfter;
  final DateTime confirmedAt;
  final String statusBefore;
  final String statusAfter;

  Map<String, Object?> toMap() => <String, Object?>{
        'request_id': requestId,
        'payload_fingerprint': payloadFingerprint,
        'settlement_id': settlementId,
        'source_transaction_id': sourceTransactionId,
        'transfer_transaction_id': transferTransactionId,
        'debit_card_account_id': debitCardAccountId,
        'linked_bank_account_id': linkedBankAccountId,
        'amount': amount,
        'currency_code': currency.code,
        'ledger_balance_before': ledgerBalanceBefore,
        'reserved_before': reservedBefore,
        'available_before': availableBefore,
        'ledger_balance_after': ledgerBalanceAfter,
        'reserved_after': reservedAfter,
        'available_after': availableAfter,
        'confirmed_at': confirmedAt.toUtc().toIso8601String(),
        'status_before': statusBefore,
        'status_after': statusAfter,
      };
}

class DebitCardSettlementConfirmationReceipt {
  const DebitCardSettlementConfirmationReceipt({
    required this.sourceTransaction,
    required this.transferTransaction,
    required this.settlement,
    required this.audit,
    this.replayed = false,
  });

  final TransactionRecord sourceTransaction;
  final TransactionRecord transferTransaction;
  final DebitCardPendingSettlement settlement;
  final DebitCardSettlementConfirmationAuditRecord audit;
  final bool replayed;
}
