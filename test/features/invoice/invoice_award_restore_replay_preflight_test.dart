import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/invoice_award_restore_replay_preflight.dart';

void main() {
  const gate = InvoiceAwardRestoreReplayPreflight();

  test('attested equal synthetic revisions are candidate-only', () {
    expect(
      gate.isCandidateCurrent(
        restoredRevision: 7,
        trustedRevisionFloor: 7,
        independentlyAttested: true,
      ),
      isTrue,
    );
    expect(gate.canActivateProduction(), isFalse);
  });

  test('stale backup, future revision, absent authority fail closed', () {
    for (final candidate in <({int? restored, int? floor, bool attested})>[
      (restored: 6, floor: 7, attested: true),
      (restored: 8, floor: 7, attested: true),
      (restored: 7, floor: null, attested: true),
      (restored: null, floor: 7, attested: true),
      (restored: 7, floor: 7, attested: false),
      (restored: -1, floor: 7, attested: true),
      (restored: 7, floor: -1, attested: true),
    ]) {
      expect(
        gate.isCandidateCurrent(
          restoredRevision: candidate.restored,
          trustedRevisionFloor: candidate.floor,
          independentlyAttested: candidate.attested,
        ),
        isFalse,
        reason: '$candidate',
      );
      expect(gate.canActivateProduction(), isFalse);
    }
  });
}
