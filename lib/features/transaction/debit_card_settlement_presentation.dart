import '../account/account_record.dart';
import 'debit_card_settlement.dart';
import 'transaction_record.dart';

enum DebitCardSettlementPresentationStatus {
  upcoming,
  due,
  overdue,
  inactive,
}

class DebitCardSettlementPresentationClock {
  const DebitCardSettlementPresentationClock();

  static const Duration taiwanOffset = Duration(hours: 8);

  DateTime taiwanDate(DateTime value) {
    final taiwan = value.toUtc().add(taiwanOffset);
    return DateTime.utc(taiwan.year, taiwan.month, taiwan.day);
  }

  DebitCardSettlementPresentationStatus classify(
    DebitCardPendingSettlement settlement, {
    required DateTime now,
  }) {
    if (settlement.status != DebitCardSettlementStatus.pending) {
      return DebitCardSettlementPresentationStatus.inactive;
    }
    final today = taiwanDate(now);
    final expected = taiwanDate(settlement.expectedSettlementDate);
    if (expected.isAfter(today)) {
      return DebitCardSettlementPresentationStatus.upcoming;
    }
    if (expected.isBefore(today)) {
      return DebitCardSettlementPresentationStatus.overdue;
    }
    return DebitCardSettlementPresentationStatus.due;
  }

  DateTime reminderUtcAt(
    DebitCardPendingSettlement settlement, {
    required DateTime now,
  }) {
    final expected = taiwanDate(settlement.expectedSettlementDate);
    final scheduledTaiwanUtc = DateTime.utc(
      expected.year,
      expected.month,
      expected.day,
      9,
    ).subtract(taiwanOffset);
    final normalizedNow = now.toUtc();
    if (scheduledTaiwanUtc.isAfter(normalizedNow)) return scheduledTaiwanUtc;
    return normalizedNow.add(const Duration(seconds: 5));
  }
}

class DebitCardSettlementPresentation {
  const DebitCardSettlementPresentation({
    required this.settlement,
    required this.debitCardAccount,
    required this.linkedBankAccount,
    required this.transaction,
    required this.status,
  });

  final DebitCardPendingSettlement settlement;
  final AccountRecord debitCardAccount;
  final AccountRecord linkedBankAccount;
  final TransactionRecord transaction;
  final DebitCardSettlementPresentationStatus status;

  String get sourceTitle {
    final merchant = transaction.merchantName.trim();
    if (merchant.isNotEmpty) return merchant;
    final category = transaction.category.trim();
    if (category.isNotEmpty) return category;
    final note = transaction.note.trim();
    if (note.isNotEmpty) return note;
    return '簽帳金融卡消費';
  }

  String get statusLabel => switch (status) {
        DebitCardSettlementPresentationStatus.upcoming => '預計扣款',
        DebitCardSettlementPresentationStatus.due => '今日預計扣款',
        DebitCardSettlementPresentationStatus.overdue => '逾期未確認',
        DebitCardSettlementPresentationStatus.inactive => '已結束',
      };

  bool get isActive => status != DebitCardSettlementPresentationStatus.inactive;
}
