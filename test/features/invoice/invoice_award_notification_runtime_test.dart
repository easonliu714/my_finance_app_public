import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:my_finance_app/features/invoice/existing_invoice_award_candidate_repository.dart';
import 'package:my_finance_app/features/invoice/existing_invoice_award_cloud_batch_matcher.dart';
import 'package:my_finance_app/features/invoice/existing_invoice_award_general_batch_matcher.dart';
import 'package:my_finance_app/features/invoice/invoice_award_notification_runtime.dart';
import 'package:my_finance_app/features/invoice/invoice_award_official_dataset.dart';

void main() {
  late InvoiceAwardNotificationSettingsRepository repository;
  late _InMemoryPort port;
  late InvoiceAwardWinningNotificationService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final preferences = await SharedPreferences.getInstance();
    repository = InvoiceAwardNotificationSettingsRepository(preferences);
    port = _InMemoryPort();
    service = InvoiceAwardWinningNotificationService(
      repository: repository,
      port: port,
    );
  });

  ExistingInvoiceAwardCandidate candidate(String number) =>
      ExistingInvoiceAwardCandidate(
        transactionId: 'txn-$number',
        invoiceNumber: number,
        invoiceDate: DateTime(2026, 8, 31, 19, 26),
        awardPeriod: '115/08',
        identitySource: ExistingInvoiceAwardIdentitySource.cloudMetadata,
        sourceProvenance: 'test',
        cloudEligibility: ExistingInvoiceAwardCloudEligibility.eligible,
        merchantName: '不應出現在通知',
        transactionAmount: 123,
      );

  test('notifications are opt-in', () async {
    final result = await service.deliverConfirmedWinners(
      periodId: '115-07-08',
      periodLabel: '115年07-08月',
      generalDatasetValidated: true,
      cloudDatasetValidated: true,
      generalEvaluations: const <ExistingInvoiceAwardGeneralEvaluation>[],
      cloudEvaluations: const <ExistingInvoiceAwardCloudEvaluation>[],
    );
    expect(result.deliveredCount, 0);
    expect(port.notifications, isEmpty);
  });

  test('incomplete authority never emits a winner notification', () async {
    await repository.setWinningNotificationsEnabled(true);
    final value = candidate('AB12345678');
    final general = ExistingInvoiceAwardGeneralEvaluation(
      candidate: value,
      status: ExistingInvoiceAwardGeneralEvaluationStatus.winner,
      matchKind: OfficialInvoiceAwardMatchKind.sixth,
    );

    final result = await service.deliverConfirmedWinners(
      periodId: '115-07-08',
      periodLabel: '115年07-08月',
      generalDatasetValidated: true,
      cloudDatasetValidated: false,
      generalEvaluations: <ExistingInvoiceAwardGeneralEvaluation>[general],
      cloudEvaluations: const <ExistingInvoiceAwardCloudEvaluation>[],
    );

    expect(result.skippedBecauseAuthorityIncomplete, isTrue);
    expect(port.notifications, isEmpty);
  });

  test('confirmed result is private and idempotent', () async {
    await repository.setWinningNotificationsEnabled(true);
    final value = candidate('CR30912111');
    final general = ExistingInvoiceAwardGeneralEvaluation(
      candidate: value,
      status: ExistingInvoiceAwardGeneralEvaluationStatus.winner,
      matchKind: OfficialInvoiceAwardMatchKind.sixth,
    );

    for (var i = 0; i < 2; i++) {
      await service.deliverConfirmedWinners(
        periodId: '115-07-08',
        periodLabel: '115年07-08月',
        generalDatasetValidated: true,
        cloudDatasetValidated: true,
        generalEvaluations: <ExistingInvoiceAwardGeneralEvaluation>[general],
        cloudEvaluations: const <ExistingInvoiceAwardCloudEvaluation>[],
      );
    }

    expect(port.notifications, hasLength(1));
    final notification = port.notifications.single;
    expect(notification.body, contains('115年07-08月'));
    expect(notification.body, contains('六獎'));
    expect(notification.body, contains('NT\$200'));
    expect(notification.body, isNot(contains('CR30912111')));
    expect(notification.body, isNot(contains('不應出現在通知')));
    expect(notification.body, isNot(contains('txn-')));
  });

  test('review-required cloud number match is not announced as winner', () async {
    await repository.setWinningNotificationsEnabled(true);
    final value = candidate('BM23888900');
    final cloud = ExistingInvoiceAwardCloudEvaluation(
      candidate: value,
      status: ExistingInvoiceAwardCloudEvaluationStatus.matchedReviewRequired,
      missingTierCodes: const <String>{},
      matchedTierCodes: const <String>{'cloud-500'},
      selectedTierCode: 'cloud-500',
      grossAmount: 500,
    );

    await service.deliverConfirmedWinners(
      periodId: '115-05-06',
      periodLabel: '115年05-06月',
      generalDatasetValidated: true,
      cloudDatasetValidated: true,
      generalEvaluations: const <ExistingInvoiceAwardGeneralEvaluation>[],
      cloudEvaluations: <ExistingInvoiceAwardCloudEvaluation>[cloud],
    );

    expect(port.notifications, isEmpty);
  });
}

class _InMemoryPort implements InvoiceAwardNotificationPort {
  final List<InvoiceAwardWinnerNotification> notifications =
      <InvoiceAwardWinnerNotification>[];

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> show(InvoiceAwardWinnerNotification notification) async {
    notifications.add(notification);
  }
}
