import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'invoice_award_refresh_policy.dart';

class InvoiceAwardRuntimeState {
  const InvoiceAwardRuntimeState({
    required this.automaticRefreshConsented,
    required this.periodId,
    required this.lastAttemptLocal,
    required this.lastOutcome,
    required this.generalDatasetPromoted,
    required this.cloudExclusiveDatasetPromoted,
    required this.scheduledTargetLocal,
    required this.pendingForegroundCatchUpAtLocal,
  });

  final bool automaticRefreshConsented;
  final String? periodId;
  final DateTime? lastAttemptLocal;
  final String? lastOutcome;
  final bool generalDatasetPromoted;
  final bool cloudExclusiveDatasetPromoted;
  final DateTime? scheduledTargetLocal;
  final DateTime? pendingForegroundCatchUpAtLocal;

  bool get hasPendingForegroundCatchUp =>
      pendingForegroundCatchUpAtLocal != null;
}

class InvoiceAwardRuntimeStateRepository {
  InvoiceAwardRuntimeStateRepository(this.preferences);

  final SharedPreferences preferences;

  static const _consentKey = 'issue13_award_auto_refresh_consent_v1';
  static const _periodKey = 'issue13_award_auto_refresh_period_v1';
  static const _lastAttemptKey = 'issue13_award_auto_refresh_last_attempt_v1';
  static const _lastOutcomeKey = 'issue13_award_auto_refresh_last_outcome_v1';
  static const _generalPromotedKey =
      'issue13_award_auto_refresh_general_promoted_v1';
  static const _cloudPromotedKey =
      'issue13_award_auto_refresh_cloud_promoted_v1';
  static const _scheduledTargetKey =
      'issue13_award_auto_refresh_scheduled_target_v1';
  static const _pendingForegroundCatchUpKey =
      'issue13_award_auto_refresh_pending_foreground_catch_up_v1';

  InvoiceAwardRuntimeState load() {
    DateTime? readTime(String key) {
      final value = preferences.getInt(key);
      return value == null ? null : DateTime.fromMillisecondsSinceEpoch(value);
    }

    return InvoiceAwardRuntimeState(
      automaticRefreshConsented: preferences.getBool(_consentKey) ?? false,
      periodId: preferences.getString(_periodKey),
      lastAttemptLocal: readTime(_lastAttemptKey),
      lastOutcome: preferences.getString(_lastOutcomeKey),
      generalDatasetPromoted:
          preferences.getBool(_generalPromotedKey) ?? false,
      cloudExclusiveDatasetPromoted:
          preferences.getBool(_cloudPromotedKey) ?? false,
      scheduledTargetLocal: readTime(_scheduledTargetKey),
      pendingForegroundCatchUpAtLocal:
          readTime(_pendingForegroundCatchUpKey),
    );
  }

  Future<void> setConsent(bool value) async {
    await preferences.setBool(_consentKey, value);
    if (!value) {
      await setScheduledTarget(null);
      await clearPendingForegroundCatchUp();
    }
  }

  Future<void> markPendingForegroundCatchUp(
    InvoiceAwardNativeWake wake,
  ) async {
    await preferences.setInt(
      _pendingForegroundCatchUpKey,
      wake.receivedAtLocal.millisecondsSinceEpoch,
    );
  }

  Future<void> clearPendingForegroundCatchUp() =>
      preferences.remove(_pendingForegroundCatchUpKey);

  Future<void> recordAttemptStarted({
    required DateTime nowLocal,
    required String periodId,
  }) async {
    final existingPeriod = preferences.getString(_periodKey);
    if (existingPeriod != periodId) {
      await preferences.setBool(_generalPromotedKey, false);
      await preferences.setBool(_cloudPromotedKey, false);
    }
    await preferences.setString(_periodKey, periodId);
    await preferences.setInt(
      _lastAttemptKey,
      nowLocal.millisecondsSinceEpoch,
    );
    await preferences.setString(_lastOutcomeKey, 'running');
    await clearPendingForegroundCatchUp();
  }

  Future<void> recordAttemptFinished({
    required String periodId,
    required bool generalDatasetPromoted,
    required bool cloudExclusiveDatasetPromoted,
  }) async {
    await preferences.setString(_periodKey, periodId);
    await preferences.setBool(
      _generalPromotedKey,
      generalDatasetPromoted,
    );
    await preferences.setBool(
      _cloudPromotedKey,
      cloudExclusiveDatasetPromoted,
    );
    await preferences.setString(
      _lastOutcomeKey,
      generalDatasetPromoted && cloudExclusiveDatasetPromoted
          ? 'complete'
          : 'partial',
    );
  }

  Future<void> setScheduledTarget(DateTime? targetLocal) async {
    if (targetLocal == null) {
      await preferences.remove(_scheduledTargetKey);
      return;
    }
    await preferences.setInt(
      _scheduledTargetKey,
      targetLocal.millisecondsSinceEpoch,
    );
  }
}

class InvoiceAwardNativeWake {
  const InvoiceAwardNativeWake({
    required this.targetLocal,
    required this.receivedAtLocal,
  });

  final DateTime targetLocal;
  final DateTime receivedAtLocal;
}

abstract class InvoiceAwardPlatformWakeScheduler {
  Future<void> schedule(DateTime targetLocal);
  Future<void> cancel();
  Future<InvoiceAwardNativeWake?> consumeDue();
}

class AndroidInvoiceAwardPlatformWakeScheduler
    implements InvoiceAwardPlatformWakeScheduler {
  const AndroidInvoiceAwardPlatformWakeScheduler();

  static const MethodChannel _channel = MethodChannel('pdf_text');

  @override
  Future<void> schedule(DateTime targetLocal) async {
    await _channel.invokeMethod<bool>(
      'scheduleInvoiceAwardRefreshWakeup',
      <String, Object>{
        'triggerAtMillis': targetLocal.millisecondsSinceEpoch,
      },
    );
  }

  @override
  Future<void> cancel() async {
    await _channel.invokeMethod<bool>('cancelInvoiceAwardRefreshWakeup');
  }

  @override
  Future<InvoiceAwardNativeWake?> consumeDue() async {
    final value = await _channel.invokeMapMethod<String, Object?>(
      'consumeInvoiceAwardRefreshWakeup',
    );
    if (value == null) return null;
    final target = value['targetMillis'];
    final received = value['receivedAtMillis'];
    if (target is! num || received is! num || target <= 0 || received <= 0) {
      return null;
    }
    return InvoiceAwardNativeWake(
      targetLocal: DateTime.fromMillisecondsSinceEpoch(target.toInt()),
      receivedAtLocal: DateTime.fromMillisecondsSinceEpoch(received.toInt()),
    );
  }
}

class InvoiceAwardRuntimeReconcileResult {
  const InvoiceAwardRuntimeReconcileResult({
    required this.consent,
    required this.nextTargetLocal,
    required this.currentPeriodComplete,
  });

  final bool consent;
  final DateTime? nextTargetLocal;
  final bool currentPeriodComplete;
}

/// Runtime bridge between the pure timing policy and Android best-effort wakeups.
///
/// Native alarms never perform network I/O. The only network authority remains
/// the canonical production refresh pipeline, invoked explicitly or by
/// foreground catch-up after consent has been re-checked.
class InvoiceAwardRuntimeScheduler {
  InvoiceAwardRuntimeScheduler({
    required this.repository,
    InvoiceAwardPlatformWakeScheduler? platform,
  }) : platform = platform ?? const AndroidInvoiceAwardPlatformWakeScheduler();

  final InvoiceAwardRuntimeStateRepository repository;
  final InvoiceAwardPlatformWakeScheduler platform;

  Future<void> setConsent(bool value) async {
    await repository.setConsent(value);
    if (!value) await platform.cancel();
  }

  Future<InvoiceAwardNativeWake?> consumeNativeWake() => platform.consumeDue();

  /// Captures a native best-effort wake at app scope without performing I/O.
  ///
  /// This deliberately persists only a local pending marker. Network authority
  /// remains with the canonical production refresh pipeline after consent is
  /// re-checked by the foreground consumer.
  Future<bool> captureNativeWakeForForeground() async {
    final wake = await platform.consumeDue();
    if (wake == null) return false;
    final state = repository.load();
    if (!state.automaticRefreshConsented) {
      await repository.clearPendingForegroundCatchUp();
      await platform.cancel();
      return false;
    }
    await repository.markPendingForegroundCatchUp(wake);
    return true;
  }

  Future<bool> foregroundCatchUpDue({
    required DateTime nowLocal,
    required String periodId,
  }) async {
    final state = repository.load();
    final samePeriod = state.periodId == periodId;
    return InvoiceAwardRefreshPolicy(
      automaticRefreshConsented: state.automaticRefreshConsented,
    ).foregroundCatchUpDue(
      nowLocal: nowLocal,
      lastAttemptLocal: samePeriod ? state.lastAttemptLocal : null,
      generalDatasetPromoted:
          samePeriod && state.generalDatasetPromoted,
      cloudExclusiveDatasetPromoted:
          samePeriod && state.cloudExclusiveDatasetPromoted,
    );
  }

  Future<void> recordAttemptStarted({
    required DateTime nowLocal,
    required String periodId,
  }) =>
      repository.recordAttemptStarted(nowLocal: nowLocal, periodId: periodId);

  Future<void> recordAttemptFinished({
    required String periodId,
    required bool generalDatasetPromoted,
    required bool cloudExclusiveDatasetPromoted,
  }) =>
      repository.recordAttemptFinished(
        periodId: periodId,
        generalDatasetPromoted: generalDatasetPromoted,
        cloudExclusiveDatasetPromoted: cloudExclusiveDatasetPromoted,
      );

  Future<InvoiceAwardRuntimeReconcileResult> reconcile({
    required DateTime nowLocal,
    required String periodId,
  }) async {
    final state = repository.load();
    final samePeriod = state.periodId == periodId;
    final generalPromoted =
        samePeriod && state.generalDatasetPromoted;
    final cloudPromoted =
        samePeriod && state.cloudExclusiveDatasetPromoted;
    final policy = InvoiceAwardRefreshPolicy(
      automaticRefreshConsented: state.automaticRefreshConsented,
    );
    final next = policy.nextTarget(
      nowLocal: nowLocal,
      generalDatasetPromoted: generalPromoted,
      cloudExclusiveDatasetPromoted: cloudPromoted,
    );

    if (next == null) {
      await platform.cancel();
      await repository.setScheduledTarget(null);
    } else {
      await platform.schedule(next);
      await repository.setScheduledTarget(next);
    }
    return InvoiceAwardRuntimeReconcileResult(
      consent: state.automaticRefreshConsented,
      nextTargetLocal: next,
      currentPeriodComplete: generalPromoted && cloudPromoted,
    );
  }
}
