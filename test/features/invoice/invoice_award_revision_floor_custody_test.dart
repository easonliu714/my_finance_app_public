import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/invoice_award_revision_floor_custody.dart';

class _SyntheticStore implements InvoiceAwardIndependentRevisionStore {
  _SyntheticStore(this.floor);
  int? floor;
  bool rejectCas = false;
  bool throwOnRead = false;
  bool acknowledgeWithoutPersisting = false;
  int casCalls = 0;

  @override
  Future<int?> readFloor() async {
    if (throwOnRead) throw StateError('synthetic read failure');
    return floor;
  }

  @override
  Future<bool> compareAndAdvance(int expectedFloor, int nextFloor) async {
    casCalls++;
    if (rejectCas || floor != expectedFloor) return false;
    if (!acknowledgeWithoutPersisting) floor = nextFloor;
    return true;
  }
}

void main() {
  const gate = InvoiceAwardRevisionFloorCustody();

  test('synthetic monotonic CAS candidate and postwrite readback', () async {
    final store = _SyntheticStore(7);
    expect(await gate.advanceCandidate(
      store: store,
      independentlyAuthenticated: true,
      expectedFloor: 7,
      nextFloor: 8,
    ), isTrue);
    expect(store.floor, 8);
    expect(gate.canActivateProduction(), isFalse);
  });

  test('stale restored snapshot cannot lower independently held floor', () async {
    final store = _SyntheticStore(8);
    expect(await gate.advanceCandidate(
      store: store,
      independentlyAuthenticated: true,
      expectedFloor: 7,
      nextFloor: 9,
    ), isFalse);
    expect(store.floor, 8);
    expect(store.casCalls, 0);
  });

  test('missing authentication, invalid monotonicity and absent store fail', () async {
    for (final candidate in <({int expected, int next, bool authenticated})>[
      (expected: 7, next: 7, authenticated: true),
      (expected: 7, next: 6, authenticated: true),
      (expected: -1, next: 0, authenticated: true),
      (expected: 7, next: 8, authenticated: false),
    ]) {
      final store = _SyntheticStore(7);
      expect(await gate.advanceCandidate(
        store: store,
        independentlyAuthenticated: candidate.authenticated,
        expectedFloor: candidate.expected,
        nextFloor: candidate.next,
      ), isFalse, reason: '$candidate');
      expect(store.casCalls, 0);
    }
    expect(await gate.advanceCandidate(
      store: null,
      independentlyAuthenticated: true,
      expectedFloor: 7,
      nextFloor: 8,
    ), isFalse);
  });

  test('CAS contention, absent floor and false write receipt fail closed', () async {
    final rejected = _SyntheticStore(7)..rejectCas = true;
    final missing = _SyntheticStore(null);
    final falseReceipt = _SyntheticStore(7)
      ..acknowledgeWithoutPersisting = true;
    for (final store in <_SyntheticStore>[rejected, missing, falseReceipt]) {
      expect(await gate.advanceCandidate(
        store: store,
        independentlyAuthenticated: true,
        expectedFloor: 7,
        nextFloor: 8,
      ), isFalse);
    }
    expect(falseReceipt.floor, 7);
  });

  test('storage read exception fails closed', () async {
    final store = _SyntheticStore(7)..throwOnRead = true;
    expect(await gate.advanceCandidate(
      store: store,
      independentlyAuthenticated: true,
      expectedFloor: 7,
      nextFloor: 8,
    ), isFalse);
    expect(gate.canActivateProduction(), isFalse);
  });
}
