import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/invoice_award_cloud_candidate_scope.dart';

void main() {
  group('native COMPLETE exact matched identity fail-closed', () {
    const a = 'AB12345678';
    const b = 'CD87654321';
    const foreign = 'EF00000001';
    final expected = <String>{a, b};

    String? violation(Object? matches, Object? pages) =>
        cloudAwardNativeCompleteMatchedIdentityViolation(
          matchedRaw: matches,
          matchedPagesRaw: pages,
          expectedCandidates: expected,
        );


    test('COMPLETE consumer invokes strict identity gate before lossy normalize', () {
      final source = File(
        'lib/features/invoice/invoice_award_cloud_candidate_scope.dart',
      ).readAsStringSync();
      final consumer = source.indexOf(
        'final identityViolation = cloudAwardNativeCompleteMatchedIdentityViolation(',
      );
      expect(consumer, greaterThan(0));
      final normalize = source.indexOf(
        'final matched = normalizeCloudCandidateNumbers(',
        consumer,
      );
      expect(normalize, greaterThan(consumer));
      expect(
        source.indexOf('throw StateError(identityViolation);', consumer),
        inInclusiveRange(consumer, normalize),
      );
      expect(
        'String? cloudAwardNativeCompleteMatchedIdentityViolation({'
            .allMatches(source)
            .length,
        1,
      );
    });

    test('accepts exact positive identities with matching page keys', () {
      expect(
        violation(<String>[a, b], <String, dynamic>{a: 1, b: 87000}),
        isNull,
      );
    });

    test('partial or empty match is shape-valid but not negative proof', () {
      expect(violation(<String>[a], <String, dynamic>{a: 1}), isNull);
      expect(violation(<String>[], <String, dynamic>{}), isNull);
      // Repository persistence still requires every candidate positive.
    });

    test('rejects invalid match silently discarded by normalization', () {
      expect(
        violation(<String>[a, b, 'INVALID'], <String, dynamic>{a: 1, b: 2}),
        'CLOUD_AWARD_CANDIDATE_WORKER_SCOPE_MISMATCH',
      );
    });

    test('rejects case or whitespace coercion of native identities', () {
      for (final value in <String>['ab12345678', ' AB12345678 ']) {
        expect(
          violation(<String>[value], <String, dynamic>{value: 1}),
          'CLOUD_AWARD_CANDIDATE_WORKER_SCOPE_MISMATCH',
        );
      }
    });

    test('rejects duplicate positive match entries', () {
      expect(
        violation(<String>[a, a], <String, dynamic>{a: 1}),
        'CLOUD_AWARD_CANDIDATE_WORKER_SCOPE_MISMATCH',
      );
    });

    test('rejects match outside the requested candidate universe', () {
      expect(
        violation(<String>[foreign], <String, dynamic>{foreign: 1}),
        'CLOUD_AWARD_CANDIDATE_WORKER_SCOPE_MISMATCH',
      );
    });

    test('rejects non-string match entries', () {
      expect(
        violation(<Object>[a, 123], <String, dynamic>{a: 1}),
        'CLOUD_AWARD_CANDIDATE_WORKER_SCOPE_MISMATCH',
      );
    });

    test('rejects missing, extra or transformed page identity keys', () {
      for (final pages in <Map<String, dynamic>>[
        <String, dynamic>{},
        <String, dynamic>{a: 1, b: 2},
        <String, dynamic>{'ab12345678': 1},
      ]) {
        expect(
          violation(<String>[a], pages),
          'CLOUD_AWARD_CANDIDATE_WORKER_PAGE_EVIDENCE_MISMATCH',
        );
      }
    });

    test('rejects non-list matches and non-map page evidence', () {
      expect(
        violation(a, <String, dynamic>{a: 1}),
        'CLOUD_AWARD_CANDIDATE_WORKER_RESULT_INVALID',
      );
      expect(
        violation(<String>[a], <int>[1]),
        'CLOUD_AWARD_CANDIDATE_WORKER_RESULT_INVALID',
      );
    });
  });
}
