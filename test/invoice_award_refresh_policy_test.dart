import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/invoice_award_refresh_policy.dart';

void main() {
  group('InvoiceAwardRefreshPolicy', () {
    test('opt-out is a hard zero-network boundary', () {
      const policy = InvoiceAwardRefreshPolicy(
        automaticRefreshConsented: false,
      );
      expect(policy.permitsAutomaticNetworkFetch, isFalse);
      expect(
        policy.nextTarget(
          nowLocal: DateTime(2026, 9, 25, 14),
          generalDatasetPromoted: false,
          cloudExclusiveDatasetPromoted: false,
        ),
        isNull,
      );
    });

    test('before odd-month 25th targets upcoming 14:00, not prior cycle', () {
      const policy = InvoiceAwardRefreshPolicy(
        automaticRefreshConsented: true,
      );
      expect(
        policy.nextTarget(
          nowLocal: DateTime(2026, 9, 21, 15, 28),
          generalDatasetPromoted: false,
          cloudExclusiveDatasetPromoted: false,
        ),
        DateTime(2026, 9, 25, 14),
      );
      expect(
        policy.foregroundCatchUpDue(
          nowLocal: DateTime(2026, 9, 21, 15, 28),
          lastAttemptLocal: null,
          generalDatasetPromoted: false,
          cloudExclusiveDatasetPromoted: false,
        ),
        isFalse,
      );
    });

    test('even month targets next odd-month publication instead of stale retry', () {
      const policy = InvoiceAwardRefreshPolicy(
        automaticRefreshConsented: true,
      );
      expect(
        policy.nextTarget(
          nowLocal: DateTime(2026, 10, 8, 9),
          generalDatasetPromoted: false,
          cloudExclusiveDatasetPromoted: false,
        ),
        DateTime(2026, 11, 25, 14),
      );
      expect(
        policy.foregroundCatchUpDue(
          nowLocal: DateTime(2026, 10, 8, 9),
          lastAttemptLocal: null,
          generalDatasetPromoted: false,
          cloudExclusiveDatasetPromoted: false,
        ),
        isFalse,
      );
    });

    test('first odd-month publication attempt targets 14:00 local time', () {
      const policy = InvoiceAwardRefreshPolicy(
        automaticRefreshConsented: true,
      );
      expect(
        policy.nextTarget(
          nowLocal: DateTime(2026, 9, 25, 13, 20),
          generalDatasetPromoted: false,
          cloudExclusiveDatasetPromoted: false,
        ),
        DateTime(2026, 9, 25, 14),
      );
    });

    test('retries approximately every 30 minutes while either domain missing', () {
      const policy = InvoiceAwardRefreshPolicy(
        automaticRefreshConsented: true,
      );
      expect(
        policy.nextTarget(
          nowLocal: DateTime(2026, 9, 25, 14, 7),
          generalDatasetPromoted: true,
          cloudExclusiveDatasetPromoted: false,
        ),
        DateTime(2026, 9, 25, 14, 30),
      );
      expect(
        policy.nextTarget(
          nowLocal: DateTime(2026, 9, 25, 14, 31),
          generalDatasetPromoted: false,
          cloudExclusiveDatasetPromoted: true,
        ),
        DateTime(2026, 9, 25, 15),
      );
    });

    test('stops after both official domains are promoted', () {
      const policy = InvoiceAwardRefreshPolicy(
        automaticRefreshConsented: true,
      );
      expect(
        policy.nextTarget(
          nowLocal: DateTime(2026, 9, 25, 15),
          generalDatasetPromoted: true,
          cloudExclusiveDatasetPromoted: true,
        ),
        isNull,
      );
    });

    test('foreground catch-up detects a missed best-effort attempt', () {
      const policy = InvoiceAwardRefreshPolicy(
        automaticRefreshConsented: true,
      );
      expect(
        policy.foregroundCatchUpDue(
          nowLocal: DateTime(2026, 9, 25, 15, 5),
          lastAttemptLocal: DateTime(2026, 9, 25, 14, 20),
          generalDatasetPromoted: true,
          cloudExclusiveDatasetPromoted: false,
        ),
        isTrue,
      );
    });

    test('policy never grants formal transaction authority', () {
      const policy = InvoiceAwardRefreshPolicy(
        automaticRefreshConsented: true,
      );
      expect(policy.canCreateFormalTransaction, isFalse);
    });
  });
}
