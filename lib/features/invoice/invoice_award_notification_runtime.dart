import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'existing_invoice_award_cloud_batch_matcher.dart';
import 'existing_invoice_award_general_batch_matcher.dart';
import 'invoice_award_cloud_eligibility_confirmation.dart';

class InvoiceAwardNotificationSettings {
  const InvoiceAwardNotificationSettings({
    required this.winningNotificationsEnabled,
  });

  final bool winningNotificationsEnabled;
}

class InvoiceAwardNotificationSettingsRepository {
  InvoiceAwardNotificationSettingsRepository(this.preferences);

  final SharedPreferences preferences;

  static const _enabledKey = 'issue13_award_winning_notifications_enabled_v1';
  static const _sentKeysKey = 'issue13_award_winning_notification_sent_keys_v1';

  InvoiceAwardNotificationSettings load() => InvoiceAwardNotificationSettings(
        winningNotificationsEnabled: preferences.getBool(_enabledKey) ?? false,
      );

  Future<void> setWinningNotificationsEnabled(bool value) =>
      preferences.setBool(_enabledKey, value);

  Set<String> sentKeys() =>
      (preferences.getStringList(_sentKeysKey) ?? const <String>[]).toSet();

  Future<void> markSent(String key) async {
    final values = sentKeys()..add(key);
    final ordered = values.toList()..sort();
    await preferences.setStringList(_sentKeysKey, ordered);
  }
}

enum InvoiceAwardNotificationKind { confirmedWinner, eligibilityReviewRequired }

class InvoiceAwardNotificationMessage {
  const InvoiceAwardNotificationMessage({
    required this.dedupeKey,
    required this.periodLabel,
    required this.tierLabel,
    required this.amount,
    required this.kind,
  });

  final String dedupeKey;
  final String periodLabel;
  final String tierLabel;
  final int amount;
  final InvoiceAwardNotificationKind kind;

  String get title => kind == InvoiceAwardNotificationKind.confirmedWinner
      ? '統一發票中獎通知'
      : '統一發票雲端獎資格待確認';

  /// Privacy-minimal lock-screen copy. Invoice number, merchant, transaction ID
  /// and accounting data are intentionally excluded.
  String get body => kind == InvoiceAwardNotificationKind.confirmedWinner
      ? '$periodLabel · $tierLabel · NT\$$amount'
      : '$periodLabel · $tierLabel · NT\$$amount · 可能中獎，請確認資格';

  String get payload => kind == InvoiceAwardNotificationKind.confirmedWinner
      ? 'invoice-award-result'
      : 'invoice-award-eligibility-review';
}

abstract class InvoiceAwardNotificationPort {
  Future<bool> requestPermission();
  Future<void> show(InvoiceAwardNotificationMessage notification);
}

class FlutterInvoiceAwardNotificationPort
    implements InvoiceAwardNotificationPort {
  FlutterInvoiceAwardNotificationPort({
    FlutterLocalNotificationsPlugin? plugin,
  }) : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  static const _channelId = 'invoice_award_results';
  static const _channelName = '統一發票中獎通知';
  static const _channelDescription = '在官方資料完成驗證與對獎後通知中獎結果。';

  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialized = false;

  @override
  Future<bool> requestPermission() async {
    await _ensureInitialized();
    if (kIsWeb || !Platform.isAndroid) return false;
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    return await android?.requestNotificationsPermission() == true;
  }

  @override
  Future<void> show(InvoiceAwardNotificationMessage notification) async {
    await _ensureInitialized();
    await _plugin.show(
      _stableNotificationId(notification.dedupeKey),
      notification.title,
      notification.body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDescription,
          importance: Importance.high,
          priority: Priority.high,
          visibility: NotificationVisibility.private,
        ),
      ),
      payload: notification.payload,
    );
  }

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(
      const InitializationSettings(android: android),
    );
    _initialized = true;
  }
}

class InvoiceAwardWinningNotificationResult {
  const InvoiceAwardWinningNotificationResult({
    required this.deliveredCount,
    required this.skippedDuplicateCount,
    required this.skippedBecauseAuthorityIncomplete,
  });

  final int deliveredCount;
  final int skippedDuplicateCount;
  final bool skippedBecauseAuthorityIncomplete;
}

class InvoiceAwardWinningNotificationService {
  InvoiceAwardWinningNotificationService({
    required this.repository,
    required this.port,
    this.eligibilityConfirmationRepository,
  });

  final InvoiceAwardNotificationSettingsRepository repository;
  final InvoiceAwardNotificationPort port;
  final InvoiceAwardCloudEligibilityConfirmationRepository?
      eligibilityConfirmationRepository;

  Future<InvoiceAwardWinningNotificationResult> deliverAwardNotifications({
    required String periodId,
    required String periodLabel,
    required bool generalDatasetValidated,
    required bool cloudDatasetValidated,
    required Iterable<ExistingInvoiceAwardGeneralEvaluation> generalEvaluations,
    required Iterable<ExistingInvoiceAwardCloudEvaluation> cloudEvaluations,
  }) async {
    final settings = repository.load();
    if (!settings.winningNotificationsEnabled) {
      return const InvoiceAwardWinningNotificationResult(
        deliveredCount: 0,
        skippedDuplicateCount: 0,
        skippedBecauseAuthorityIncomplete: false,
      );
    }
    if (!generalDatasetValidated || !cloudDatasetValidated) {
      return const InvoiceAwardWinningNotificationResult(
        deliveredCount: 0,
        skippedDuplicateCount: 0,
        skippedBecauseAuthorityIncomplete: true,
      );
    }

    final generalByCandidate = <String, ExistingInvoiceAwardGeneralEvaluation>{
      for (final value in generalEvaluations) value.candidate.dedupeKey: value,
    };
    final cloudByCandidate = <String, ExistingInvoiceAwardCloudEvaluation>{
      for (final value in cloudEvaluations) value.candidate.dedupeKey: value,
    };
    final candidateKeys = <String>{
      ...generalByCandidate.keys,
      ...cloudByCandidate.keys,
    };
    final sent = repository.sentKeys();

    var delivered = 0;
    var duplicates = 0;
    for (final candidateKey in candidateKeys) {
      final confirmed = _selectConfirmedWinner(
        periodId: periodId,
        periodLabel: periodLabel,
        candidateKey: candidateKey,
        general: generalByCandidate[candidateKey],
        cloud: cloudByCandidate[candidateKey],
      );
      if (confirmed != null) {
        if (sent.contains(confirmed.dedupeKey)) {
          duplicates += 1;
        } else {
          await port.show(confirmed);
          await repository.markSent(confirmed.dedupeKey);
          sent.add(confirmed.dedupeKey);
          delivered += 1;
        }
      }

      final cloud = cloudByCandidate[candidateKey];
      if (cloud == null) {
        continue;
      }
      final review = _selectEligibilityReview(
        periodId: periodId,
        periodLabel: periodLabel,
        candidateKey: candidateKey,
        cloud: cloud,
      );
      if (review == null) {
        continue;
      }
      final existingConfirmation = eligibilityConfirmationRepository
          ?.readForEvaluation(periodId: periodId, evaluation: cloud);
      if (existingConfirmation != null) {
        continue;
      }
      if (sent.contains(review.dedupeKey)) {
        duplicates += 1;
        continue;
      }
      await port.show(review);
      await repository.markSent(review.dedupeKey);
      sent.add(review.dedupeKey);
      delivered += 1;
    }

    return InvoiceAwardWinningNotificationResult(
      deliveredCount: delivered,
      skippedDuplicateCount: duplicates,
      skippedBecauseAuthorityIncomplete: false,
    );
  }

  InvoiceAwardNotificationMessage? _selectConfirmedWinner({
    required String periodId,
    required String periodLabel,
    required String candidateKey,
    required ExistingInvoiceAwardGeneralEvaluation? general,
    required ExistingInvoiceAwardCloudEvaluation? cloud,
  }) {
    final options = <({String tier, int amount})>[];
    if (general?.isWinner == true && general!.grossAmount > 0) {
      options.add((tier: general.tierLabel, amount: general.grossAmount));
    }
    if (cloud?.isConfirmedCloudNumberMatch == true && cloud!.grossAmount > 0) {
      options.add((
        tier: _cloudTierLabel(cloud.selectedTierCode),
        amount: cloud.grossAmount,
      ));
    }
    if (options.isEmpty) return null;

    // Notification-only precedence: one privacy-minimal result per invoice.
    // This does not establish payout/bookkeeping authority.
    options.sort((a, b) {
      final amount = b.amount.compareTo(a.amount);
      return amount != 0 ? amount : a.tier.compareTo(b.tier);
    });
    final selected = options.first;
    final dedupeKey = 'invoice-award-notify:$periodId:$candidateKey:${selected.tier}:${selected.amount}';
    return InvoiceAwardNotificationMessage(
      dedupeKey: dedupeKey,
      periodLabel: periodLabel,
      tierLabel: selected.tier,
      amount: selected.amount,
      kind: InvoiceAwardNotificationKind.confirmedWinner,
    );
  }

  InvoiceAwardNotificationMessage? _selectEligibilityReview({
    required String periodId,
    required String periodLabel,
    required String candidateKey,
    required ExistingInvoiceAwardCloudEvaluation cloud,
  }) {
    if (cloud.status !=
            ExistingInvoiceAwardCloudEvaluationStatus.matchedReviewRequired ||
        cloud.selectedTierCode == null ||
        cloud.grossAmount <= 0 ||
        cloud.pdfSha256 == null ||
        !RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(cloud.pdfSha256!)) {
      return null;
    }
    final tier = _cloudTierLabel(cloud.selectedTierCode);
    final dedupeKey =
        'invoice-award-review:$periodId:$candidateKey:$tier:${cloud.grossAmount}:${cloud.pdfSha256!.toLowerCase()}';
    return InvoiceAwardNotificationMessage(
      dedupeKey: dedupeKey,
      periodLabel: periodLabel,
      tierLabel: tier,
      amount: cloud.grossAmount,
      kind: InvoiceAwardNotificationKind.eligibilityReviewRequired,
    );
  }
}

String _cloudTierLabel(String? tierCode) => switch (tierCode) {
      'cloud-1000000' => '雲端專屬獎 100萬元獎',
      'cloud-2000' => '雲端專屬獎 2,000元獎',
      'cloud-800' => '雲端專屬獎 800元獎',
      'cloud-500' => '雲端專屬獎 500元獎',
      _ => '雲端專屬獎',
    };

int _stableNotificationId(String value) {
  var hash = 0x811c9dc5;
  for (final unit in value.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0x7fffffff;
  }
  return 410000 + (hash % 1000000000);
}
