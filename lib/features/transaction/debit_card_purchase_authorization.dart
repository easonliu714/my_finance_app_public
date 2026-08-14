import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import '../account/account_record.dart';
import 'debit_card_settlement.dart';
import 'transaction_record.dart';

/// Typed failures returned by the local debit-card accounting gate.
enum DebitCardPurchaseAuthorizationErrorCode {
  invalidRequest,
  debitCardAccountNotFound,
  debitCardAccountArchived,
  wrongAccountType,
  profileNotFound,
  profileDisabled,
  linkedBankAccountNotFound,
  linkedBankAccountArchived,
  linkedBankAccountInvalid,
  currencyMismatch,
  insufficientAvailableBalance,
  replayConflict,
  transactionIdConflict,
  settlementIdConflict,
  authorizedTransactionImmutable,
}

class DebitCardPurchaseAuthorizationException implements Exception {
  const DebitCardPurchaseAuthorizationException(
    this.code,
    this.message, {
    this.availableBalance,
    this.requestedAmount,
  });

  final DebitCardPurchaseAuthorizationErrorCode code;
  final String message;
  final double? availableBalance;
  final double? requestedAmount;

  String get userMessage => switch (code) {
        DebitCardPurchaseAuthorizationErrorCode.invalidRequest =>
          '簽帳金融卡交易資料不完整或金額無效，請重新確認。',
        DebitCardPurchaseAuthorizationErrorCode.debitCardAccountNotFound =>
          '找不到指定的簽帳金融卡帳戶。',
        DebitCardPurchaseAuthorizationErrorCode.debitCardAccountArchived =>
          '此簽帳金融卡帳戶已封存，無法新增消費。',
        DebitCardPurchaseAuthorizationErrorCode.wrongAccountType =>
          '所選帳戶不是簽帳金融卡帳戶。',
        DebitCardPurchaseAuthorizationErrorCode.profileNotFound =>
          '此簽帳金融卡尚未完成扣款帳戶設定。',
        DebitCardPurchaseAuthorizationErrorCode.profileDisabled =>
          '此簽帳金融卡目前已停用。',
        DebitCardPurchaseAuthorizationErrorCode.linkedBankAccountNotFound =>
          '找不到此簽帳金融卡綁定的銀行帳戶。',
        DebitCardPurchaseAuthorizationErrorCode.linkedBankAccountArchived =>
          '綁定的銀行帳戶已封存，無法授權本次消費。',
        DebitCardPurchaseAuthorizationErrorCode.linkedBankAccountInvalid =>
          '簽帳金融卡綁定的扣款帳戶類型不正確。',
        DebitCardPurchaseAuthorizationErrorCode.currencyMismatch =>
          '簽帳金融卡、銀行帳戶與交易幣別不一致。',
        DebitCardPurchaseAuthorizationErrorCode.insufficientAvailableBalance =>
          '可用餘額不足：目前可用 ${availableBalance ?? 0}，'
          '本次需要 ${requestedAmount ?? 0}。',
        DebitCardPurchaseAuthorizationErrorCode.replayConflict =>
          '偵測到重複授權要求，但交易內容不一致，已停止寫入。',
        DebitCardPurchaseAuthorizationErrorCode.transactionIdConflict =>
          '交易識別碼已被使用，請重新建立交易。',
        DebitCardPurchaseAuthorizationErrorCode.settlementIdConflict =>
          '預計扣款識別碼已被使用，請重新建立交易。',
        DebitCardPurchaseAuthorizationErrorCode.authorizedTransactionImmutable =>
          '此筆簽帳金融卡消費已有預計扣款，無法直接編輯或刪除。',
      };

  @override
  String toString() => userMessage;
}

class DebitCardPurchaseAuthorizationRequest {
  const DebitCardPurchaseAuthorizationRequest({
    required this.requestId,
    required this.settlementId,
    required this.debitCardAccountId,
    required this.transaction,
    required this.requestedAt,
  });

  final String requestId;
  final String settlementId;
  final String debitCardAccountId;
  final TransactionRecord transaction;
  final DateTime requestedAt;

  String get normalizedRequestId => requestId.trim();
  String get normalizedSettlementId => settlementId.trim();
  String get normalizedDebitCardAccountId => debitCardAccountId.trim();

  Future<String> payloadFingerprint() async {
    final canonical = jsonEncode(<String, Object?>{
      'settlement_id': normalizedSettlementId,
      'debit_card_account_id': normalizedDebitCardAccountId,
      'transaction_id': transaction.id.trim(),
      'type': transaction.type.name,
      'amount': transaction.currency.roundAmount(transaction.amount),
      'category': transaction.category.trim(),
      'occurred_at': transaction.occurredAt.toUtc().toIso8601String(),
      'account_name': transaction.accountName.trim(),
      'member_name': transaction.memberName.trim(),
      'merchant_name': transaction.merchantName.trim(),
      'tag_name': transaction.tagName.trim(),
      'note': transaction.note.trim(),
      'currency_code': transaction.currency.code,
      'exchange_rate_to_base': transaction.exchangeRateToBase,
      'from_account_name': transaction.fromAccountName?.trim(),
      'to_account_name': transaction.toAccountName?.trim(),
      'repayment_group_id': transaction.repaymentGroupId?.trim(),
    });
    final digest = await Sha256().hash(utf8.encode(canonical));
    return digest.bytes
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
  }
}

class DebitCardAuthorizationAuditRecord {
  const DebitCardAuthorizationAuditRecord({
    required this.requestId,
    required this.payloadFingerprint,
    required this.transactionId,
    required this.settlementId,
    required this.debitCardAccountId,
    required this.linkedBankAccountId,
    required this.amount,
    required this.currency,
    required this.ledgerBalanceBefore,
    required this.reservedBefore,
    required this.availableBefore,
    required this.availableAfter,
    required this.authorizedAt,
    required this.expectedSettlementDate,
  });

  factory DebitCardAuthorizationAuditRecord.fromMap(
    Map<String, Object?> map,
  ) {
    return DebitCardAuthorizationAuditRecord(
      requestId: map['request_id'] as String,
      payloadFingerprint: map['payload_fingerprint'] as String,
      transactionId: map['transaction_id'] as String,
      settlementId: map['settlement_id'] as String,
      debitCardAccountId: map['debit_card_account_id'] as String,
      linkedBankAccountId: map['linked_bank_account_id'] as String,
      amount: (map['amount'] as num).toDouble(),
      currency: currencyFromCode(map['currency_code'] as String?),
      ledgerBalanceBefore:
          (map['ledger_balance_before'] as num).toDouble(),
      reservedBefore: (map['reserved_before'] as num).toDouble(),
      availableBefore: (map['available_before'] as num).toDouble(),
      availableAfter: (map['available_after'] as num).toDouble(),
      authorizedAt: DateTime.parse(map['authorized_at'] as String),
      expectedSettlementDate:
          DateTime.parse(map['expected_settlement_date'] as String),
    );
  }

  final String requestId;
  final String payloadFingerprint;
  final String transactionId;
  final String settlementId;
  final String debitCardAccountId;
  final String linkedBankAccountId;
  final double amount;
  final CurrencyCode currency;
  final double ledgerBalanceBefore;
  final double reservedBefore;
  final double availableBefore;
  final double availableAfter;
  final DateTime authorizedAt;
  final DateTime expectedSettlementDate;

  Map<String, Object?> toMap() => <String, Object?>{
        'request_id': requestId,
        'payload_fingerprint': payloadFingerprint,
        'transaction_id': transactionId,
        'settlement_id': settlementId,
        'debit_card_account_id': debitCardAccountId,
        'linked_bank_account_id': linkedBankAccountId,
        'amount': amount,
        'currency_code': currency.code,
        'ledger_balance_before': ledgerBalanceBefore,
        'reserved_before': reservedBefore,
        'available_before': availableBefore,
        'available_after': availableAfter,
        'authorized_at': authorizedAt.toIso8601String(),
        'expected_settlement_date':
            expectedSettlementDate.toIso8601String(),
      };
}

class DebitCardPurchaseAuthorizationReceipt {
  const DebitCardPurchaseAuthorizationReceipt({
    required this.transaction,
    required this.settlement,
    required this.audit,
    this.replayed = false,
  });

  final TransactionRecord transaction;
  final DebitCardPendingSettlement settlement;
  final DebitCardAuthorizationAuditRecord audit;
  final bool replayed;
}
