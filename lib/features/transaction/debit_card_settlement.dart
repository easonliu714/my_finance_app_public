import '../account/account_record.dart';
import 'taiwan_business_calendar.dart';

enum DebitCardSettlementStatus {
  pending,
  confirmed,
  cancelled,
  failed,
}

enum DebitCardAuthorizationErrorCode {
  invalidAmount,
  insufficientAvailableBalance,
}

class DebitCardAuthorizationException implements Exception {
  const DebitCardAuthorizationException(this.code, this.message);

  final DebitCardAuthorizationErrorCode code;
  final String message;

  @override
  String toString() => 'DebitCardAuthorizationException($code): $message';
}

class DebitCardPendingSettlement {
  const DebitCardPendingSettlement({
    required this.id,
    required this.debitCardAccountId,
    required this.linkedBankAccountId,
    required this.transactionId,
    required this.amount,
    required this.currency,
    required this.authorizedAt,
    required this.expectedSettlementDate,
    required this.status,
    this.terminalAt,
    this.failureReason,
    this.settlementTransferTransactionId,
  });

  factory DebitCardPendingSettlement.authorize({
    required String id,
    required String debitCardAccountId,
    required String linkedBankAccountId,
    required String transactionId,
    required double amount,
    required CurrencyCode currency,
    required DateTime authorizedAt,
    int settlementBusinessDays = 2,
    BusinessDayCalendar businessCalendar =
        const TaiwanBusinessCalendar.bundled(),
  }) {
    _requireNonEmpty(id, 'id');
    _requireNonEmpty(debitCardAccountId, 'debitCardAccountId');
    _requireNonEmpty(linkedBankAccountId, 'linkedBankAccountId');
    _requireNonEmpty(transactionId, 'transactionId');
    if (debitCardAccountId.trim() == linkedBankAccountId.trim()) {
      throw ArgumentError.value(
        linkedBankAccountId,
        'linkedBankAccountId',
        'Debit-card and linked bank-account identities must differ.',
      );
    }
    if (settlementBusinessDays < 0) {
      throw ArgumentError.value(
        settlementBusinessDays,
        'settlementBusinessDays',
        'Must not be negative.',
      );
    }

    final normalizedAmount = currency.roundAmount(amount);
    if (!normalizedAmount.isFinite || normalizedAmount <= 0) {
      throw const DebitCardAuthorizationException(
        DebitCardAuthorizationErrorCode.invalidAmount,
        'Authorization amount must be a finite positive value.',
      );
    }

    return DebitCardPendingSettlement(
      id: id.trim(),
      debitCardAccountId: debitCardAccountId.trim(),
      linkedBankAccountId: linkedBankAccountId.trim(),
      transactionId: transactionId.trim(),
      amount: normalizedAmount,
      currency: currency,
      authorizedAt: authorizedAt,
      expectedSettlementDate: DebitCardSettlementPlanner.addBusinessDays(
        authorizedAt,
        settlementBusinessDays,
        businessCalendar: businessCalendar,
      ),
      status: DebitCardSettlementStatus.pending,
    );
  }

  factory DebitCardPendingSettlement.fromMap(Map<String, Object?> map) {
    final terminalText = map['terminal_at'] as String?;
    return DebitCardPendingSettlement(
      id: map['id'] as String,
      debitCardAccountId: map['debit_card_account_id'] as String,
      linkedBankAccountId: map['linked_bank_account_id'] as String,
      transactionId: map['transaction_id'] as String,
      amount: (map['amount'] as num).toDouble(),
      currency: currencyFromCode(map['currency_code'] as String?),
      authorizedAt: DateTime.parse(map['authorized_at'] as String),
      expectedSettlementDate:
          DateTime.parse(map['expected_settlement_date'] as String),
      status: DebitCardSettlementStatus.values.byName(map['status'] as String),
      terminalAt: terminalText == null || terminalText.trim().isEmpty
          ? null
          : DateTime.parse(terminalText),
      failureReason: map['failure_reason'] as String?,
      settlementTransferTransactionId:
          map['settlement_transfer_transaction_id'] as String?,
    );
  }

  final String id;
  final String debitCardAccountId;
  final String linkedBankAccountId;
  final String transactionId;
  final double amount;
  final CurrencyCode currency;
  final DateTime authorizedAt;
  final DateTime expectedSettlementDate;
  final DebitCardSettlementStatus status;
  final DateTime? terminalAt;
  final String? failureReason;
  final String? settlementTransferTransactionId;

  bool get reservesAvailableBalance =>
      status == DebitCardSettlementStatus.pending;

  Map<String, Object?> toMap() => <String, Object?>{
        'id': id,
        'debit_card_account_id': debitCardAccountId,
        'linked_bank_account_id': linkedBankAccountId,
        'transaction_id': transactionId,
        'amount': amount,
        'currency_code': currency.code,
        'authorized_at': authorizedAt.toIso8601String(),
        'expected_settlement_date': expectedSettlementDate.toIso8601String(),
        'status': status.name,
        'terminal_at': terminalAt?.toIso8601String(),
        'failure_reason': failureReason,
        'settlement_transfer_transaction_id': settlementTransferTransactionId,
      };

  DebitCardPendingSettlement confirm(
    DateTime confirmedAt, {
    String? settlementTransferTransactionId,
  }) {
    final transferId = settlementTransferTransactionId?.trim();
    return _terminalTransition(
      nextStatus: DebitCardSettlementStatus.confirmed,
      terminalAt: confirmedAt,
      settlementTransferTransactionId:
          transferId == null || transferId.isEmpty ? null : transferId,
    );
  }

  DebitCardPendingSettlement cancel(DateTime cancelledAt) {
    return _terminalTransition(
      nextStatus: DebitCardSettlementStatus.cancelled,
      terminalAt: cancelledAt,
    );
  }

  DebitCardPendingSettlement fail({
    required DateTime failedAt,
    required String reason,
  }) {
    final normalizedReason = reason.trim();
    if (normalizedReason.isEmpty) {
      throw ArgumentError.value(
        reason,
        'reason',
        'Failure reason must not be empty.',
      );
    }
    return _terminalTransition(
      nextStatus: DebitCardSettlementStatus.failed,
      terminalAt: failedAt,
      failureReason: normalizedReason,
    );
  }

  DebitCardPendingSettlement _terminalTransition({
    required DebitCardSettlementStatus nextStatus,
    required DateTime terminalAt,
    String? failureReason,
    String? settlementTransferTransactionId,
  }) {
    if (status != DebitCardSettlementStatus.pending) {
      throw StateError(
        'Only a pending debit-card settlement can transition. '
        'Current status: ${status.name}.',
      );
    }
    if (terminalAt.isBefore(authorizedAt)) {
      throw ArgumentError.value(
        terminalAt,
        'terminalAt',
        'Terminal timestamp must not be before authorization.',
      );
    }
    if (nextStatus == DebitCardSettlementStatus.pending) {
      throw ArgumentError.value(
        nextStatus,
        'nextStatus',
        'Terminal transition cannot return to pending.',
      );
    }

    return DebitCardPendingSettlement(
      id: id,
      debitCardAccountId: debitCardAccountId,
      linkedBankAccountId: linkedBankAccountId,
      transactionId: transactionId,
      amount: amount,
      currency: currency,
      authorizedAt: authorizedAt,
      expectedSettlementDate: expectedSettlementDate,
      status: nextStatus,
      terminalAt: terminalAt,
      failureReason: failureReason,
      settlementTransferTransactionId: settlementTransferTransactionId,
    );
  }
}

class DebitCardSettlementPlanner {
  const DebitCardSettlementPlanner({
    this.businessCalendar = const TaiwanBusinessCalendar.bundled(),
  });

  final BusinessDayCalendar businessCalendar;

  static DateTime addBusinessDays(
    DateTime start,
    int businessDays, {
    BusinessDayCalendar businessCalendar =
        const TaiwanBusinessCalendar.bundled(),
  }) {
    if (businessDays < 0) {
      throw ArgumentError.value(
        businessDays,
        'businessDays',
        'Must not be negative.',
      );
    }

    businessCalendar.requireCoverage(start);
    var current = start;
    var added = 0;
    while (added < businessDays) {
      current = _nextCalendarDay(current);
      if (businessCalendar.isBusinessDay(current)) {
        added += 1;
      }
    }
    return current;
  }

  double reservedAmount({
    required Iterable<DebitCardPendingSettlement> settlements,
    required String linkedBankAccountId,
    required CurrencyCode currency,
  }) {
    final normalizedBankAccountId = linkedBankAccountId.trim();
    final reserved = settlements
        .where(
          (item) =>
              item.reservesAvailableBalance &&
              item.linkedBankAccountId == normalizedBankAccountId &&
              item.currency == currency,
        )
        .fold<double>(0, (sum, item) => sum + item.amount);
    return currency.roundAmount(reserved);
  }

  double availableBalance({
    required double currentBankBalance,
    required Iterable<DebitCardPendingSettlement> settlements,
    required String linkedBankAccountId,
    required CurrencyCode currency,
  }) {
    final normalizedBalance = currency.roundAmount(currentBankBalance);
    final reserved = reservedAmount(
      settlements: settlements,
      linkedBankAccountId: linkedBankAccountId,
      currency: currency,
    );
    return currency.roundAmount(normalizedBalance - reserved);
  }

  DebitCardPendingSettlement authorize({
    required String id,
    required String debitCardAccountId,
    required String linkedBankAccountId,
    required String transactionId,
    required double amount,
    required CurrencyCode currency,
    required DateTime authorizedAt,
    required double currentBankBalance,
    Iterable<DebitCardPendingSettlement> existingSettlements = const [],
    int settlementBusinessDays = 2,
  }) {
    final normalizedAmount = currency.roundAmount(amount);
    if (!normalizedAmount.isFinite || normalizedAmount <= 0) {
      throw const DebitCardAuthorizationException(
        DebitCardAuthorizationErrorCode.invalidAmount,
        'Authorization amount must be a finite positive value.',
      );
    }

    final available = availableBalance(
      currentBankBalance: currentBankBalance,
      settlements: existingSettlements,
      linkedBankAccountId: linkedBankAccountId,
      currency: currency,
    );
    if (normalizedAmount > available) {
      throw DebitCardAuthorizationException(
        DebitCardAuthorizationErrorCode.insufficientAvailableBalance,
        'Requested $normalizedAmount ${currency.code}, but only '
        '$available ${currency.code} is available.',
      );
    }

    return DebitCardPendingSettlement.authorize(
      id: id,
      debitCardAccountId: debitCardAccountId,
      linkedBankAccountId: linkedBankAccountId,
      transactionId: transactionId,
      amount: normalizedAmount,
      currency: currency,
      authorizedAt: authorizedAt,
      settlementBusinessDays: settlementBusinessDays,
      businessCalendar: businessCalendar,
    );
  }
}

DateTime _nextCalendarDay(DateTime value) {
  if (value.isUtc) {
    return DateTime.utc(
      value.year,
      value.month,
      value.day + 1,
      value.hour,
      value.minute,
      value.second,
      value.millisecond,
      value.microsecond,
    );
  }
  return DateTime(
    value.year,
    value.month,
    value.day + 1,
    value.hour,
    value.minute,
    value.second,
    value.millisecond,
    value.microsecond,
  );
}

void _requireNonEmpty(String value, String name) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, name, 'Must not be empty.');
  }
}
