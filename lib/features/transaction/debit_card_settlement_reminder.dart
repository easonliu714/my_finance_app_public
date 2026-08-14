import 'dart:convert';

import 'debit_card_settlement_presentation.dart';

class DebitCardSettlementReminderRequest {
  const DebitCardSettlementReminderRequest({
    required this.notificationId,
    required this.settlementId,
    required this.title,
    required this.body,
    required this.scheduledAtUtc,
    required this.payload,
  });

  final int notificationId;
  final String settlementId;
  final String title;
  final String body;
  final DateTime scheduledAtUtc;
  final String payload;
}

abstract class DebitCardSettlementReminderPort {
  Future<Set<int>> pendingReminderIds();

  Future<void> schedule(DebitCardSettlementReminderRequest request);

  Future<void> cancel(int notificationId);
}

class NoopDebitCardSettlementReminderPort
    implements DebitCardSettlementReminderPort {
  const NoopDebitCardSettlementReminderPort();

  @override
  Future<void> cancel(int notificationId) async {}

  @override
  Future<Set<int>> pendingReminderIds() async => const <int>{};

  @override
  Future<void> schedule(DebitCardSettlementReminderRequest request) async {}
}

class DebitCardSettlementReminderPlanner {
  const DebitCardSettlementReminderPlanner({
    this.clock = const DebitCardSettlementPresentationClock(),
  });

  static const String payloadPrefix = 'debit_card_settlement:';
  static const int notificationIdBase = 420000000;
  static const int notificationIdRange = 1200000000;

  final DebitCardSettlementPresentationClock clock;

  List<DebitCardSettlementReminderRequest> build({
    required Iterable<DebitCardSettlementPresentation> settlements,
    required DateTime now,
  }) {
    final requests = <DebitCardSettlementReminderRequest>[];
    for (final item in settlements) {
      if (!item.isActive) continue;
      final title = switch (item.status) {
        DebitCardSettlementPresentationStatus.upcoming => '簽帳金融卡預計扣款',
        DebitCardSettlementPresentationStatus.due => '今日預計扣款',
        DebitCardSettlementPresentationStatus.overdue => '已逾預計扣款日',
        DebitCardSettlementPresentationStatus.inactive => '簽帳金融卡待扣款',
      };
      final body = switch (item.status) {
        DebitCardSettlementPresentationStatus.upcoming =>
          '${item.sourceTitle}・${item.settlement.amount} '
              '${item.settlement.currency.code}，請確認扣款帳戶餘額。',
        DebitCardSettlementPresentationStatus.due =>
          '${item.sourceTitle} 今日預計扣款；此為 App 推算，並非銀行回傳結果。',
        DebitCardSettlementPresentationStatus.overdue =>
          '${item.sourceTitle} 已逾預計扣款日，尚待確認；App 不會自動標記完成。',
        DebitCardSettlementPresentationStatus.inactive => '',
      };
      requests.add(
        DebitCardSettlementReminderRequest(
          notificationId: notificationIdFor(item.settlement.id),
          settlementId: item.settlement.id,
          title: title,
          body: body,
          scheduledAtUtc: clock.reminderUtcAt(
            item.settlement,
            now: now,
          ),
          payload: '$payloadPrefix${item.settlement.id}',
        ),
      );
    }
    requests.sort(
      (left, right) => left.scheduledAtUtc.compareTo(right.scheduledAtUtc),
    );
    return List<DebitCardSettlementReminderRequest>.unmodifiable(requests);
  }

  int notificationIdFor(String settlementId) {
    var hash = 0x811c9dc5;
    for (final byte in utf8.encode(settlementId.trim())) {
      hash ^= byte;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return notificationIdBase + (hash % notificationIdRange);
  }
}

class DebitCardSettlementReminderReconciliationService {
  const DebitCardSettlementReminderReconciliationService({
    required this.port,
    this.planner = const DebitCardSettlementReminderPlanner(),
  });

  final DebitCardSettlementReminderPort port;
  final DebitCardSettlementReminderPlanner planner;

  Future<void> reconcile({
    required Iterable<DebitCardSettlementPresentation> settlements,
    required DateTime now,
  }) async {
    final desired = planner.build(settlements: settlements, now: now);
    final desiredIds = desired
        .map((request) => request.notificationId)
        .toSet();
    final currentIds = await port.pendingReminderIds();

    for (final obsoleteId in currentIds.difference(desiredIds)) {
      await port.cancel(obsoleteId);
    }
    for (final request in desired) {
      await port.schedule(request);
    }
  }
}
