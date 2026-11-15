import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/invoice_award_restore_floor_readback.dart';
import 'package:my_finance_app/features/invoice/invoice_award_revision_floor_custody.dart';

class _IndependentSyntheticFloor implements InvoiceAwardIndependentRevisionStore {
  _IndependentSyntheticFloor(this.values);
  final List<int?> values;
  int reads = 0;
  @override
  Future<int?> readFloor() async {
    final index = reads++;
    if (index >= values.length) throw StateError('floor read unavailable');
    return values[index];
  }

  @override
  Future<bool> compareAndAdvance(int expectedFloor, int nextFloor) async =>
      throw StateError('read-only restore check must never write');
}

void main() {
  const gate = InvoiceAwardRestoreFloorReadback();

  test('current independently authenticated synthetic floor is candidate only',
      () async {
    final store = _IndependentSyntheticFloor([8, 8]);
    expect(await gate.isCandidateCurrent(
      store: store, independentlyAuthenticated: true, restoredRevision: 8,
    ), isTrue);
    expect(store.reads, 2);
    expect(gate.canActivateProduction(), isFalse);
  });

  test('old restored backup and future snapshot both fail closed', () async {
    for (final restored in [7, 9]) {
      final store = _IndependentSyntheticFloor([8, 8]);
      expect(await gate.isCandidateCurrent(
        store: store, independentlyAuthenticated: true,
        restoredRevision: restored,
      ), isFalse);
      expect(store.reads, 1);
    }
  });

  test('absent or unauthenticated independent custody never reads', () async {
    final store = _IndependentSyntheticFloor([8, 8]);
    expect(await gate.isCandidateCurrent(
      store: store, independentlyAuthenticated: false, restoredRevision: 8,
    ), isFalse);
    expect(await gate.isCandidateCurrent(
      store: null, independentlyAuthenticated: true, restoredRevision: 8,
    ), isFalse);
    expect(await gate.isCandidateCurrent(
      store: store, independentlyAuthenticated: true, restoredRevision: null,
    ), isFalse);
    expect(await gate.isCandidateCurrent(
      store: store, independentlyAuthenticated: true, restoredRevision: -1,
    ), isFalse);
    expect(store.reads, 0);
  });

  test('missing, negative, moving or failed independent floor rejects', () async {
    for (final values in <List<int?>>[
      [null], [-1], [8, 9], [8], [8, null],
    ]) {
      expect(await gate.isCandidateCurrent(
        store: _IndependentSyntheticFloor(values),
        independentlyAuthenticated: true, restoredRevision: 8,
      ), isFalse, reason: '$values');
    }
  });
}
