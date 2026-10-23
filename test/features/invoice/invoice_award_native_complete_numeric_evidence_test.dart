import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/invoice_award_cloud_candidate_scope.dart';

void main() {
  group('native COMPLETE numeric evidence fail-closed', () {
    Map<String, dynamic> complete() => <String, dynamic>{
          'page_count': 87000,
          'pages_read': 13,
          'candidate_count': 47,
          'source_bytes': 135200798,
          'matched_pages': <String, dynamic>{'AB12345678': 43500},
        };

    String? violation(Map<String, dynamic> result) =>
        cloudAwardNativeCompleteNumericEvidenceViolation(terminal: result);

    test('accepts typed integral native evidence', () {
      expect(violation(complete()), isNull);
    });

    test('rejects fractional counts and source bytes without truncation', () {
      for (final field in <String>[
        'page_count',
        'pages_read',
        'candidate_count',
        'source_bytes',
      ]) {
        final result = complete();
        result[field] = (result[field] as int) + 0.5;
        expect(
          violation(result),
          'CLOUD_AWARD_CANDIDATE_WORKER_RESULT_INVALID',
          reason: field,
        );
      }
    });

    test('rejects string and boolean numeric impostors', () {
      for (final value in <Object>['47', true]) {
        expect(
          violation(complete()..['candidate_count'] = value),
          'CLOUD_AWARD_CANDIDATE_WORKER_RESULT_INVALID',
        );
      }
    });

    test('rejects absent numeric evidence', () {
      for (final field in <String>[
        'page_count',
        'pages_read',
        'candidate_count',
        'source_bytes',
      ]) {
        expect(
          violation(complete()..remove(field)),
          'CLOUD_AWARD_CANDIDATE_WORKER_RESULT_INVALID',
          reason: field,
        );
      }
    });

    test('rejects fractional matched page instead of rounding down', () {
      expect(
        violation(complete()
          ..['matched_pages'] = <String, dynamic>{'AB12345678': 43500.5}),
        'CLOUD_AWARD_CANDIDATE_WORKER_PAGE_EVIDENCE_MISMATCH',
      );
    });

    test('rejects string or boolean matched page', () {
      for (final value in <Object>['43500', true]) {
        expect(
          violation(complete()
            ..['matched_pages'] = <String, dynamic>{'AB12345678': value}),
          'CLOUD_AWARD_CANDIDATE_WORKER_PAGE_EVIDENCE_MISMATCH',
        );
      }
    });

    test('rejects missing or non-map page evidence', () {
      expect(
        violation(complete()..remove('matched_pages')),
        'CLOUD_AWARD_CANDIDATE_WORKER_RESULT_INVALID',
      );
      expect(
        violation(complete()..['matched_pages'] = <int>[43500]),
        'CLOUD_AWARD_CANDIDATE_WORKER_RESULT_INVALID',
      );
    });

    test('rejects positive match when native claims zero pages read', () {
      expect(
        violation(complete()..['pages_read'] = 0),
        'CLOUD_AWARD_CANDIDATE_WORKER_PAGE_EVIDENCE_MISMATCH',
      );
    });

    test('zero-read empty match remains UNKNOWN rather than negative proof', () {
      final result = complete()
        ..['pages_read'] = 0
        ..['matched_pages'] = <String, dynamic>{};
      expect(violation(result), isNull);
    });

    test('empty match map is shape-valid but not a proven negative', () {
      expect(
        violation(complete()..['matched_pages'] = <String, dynamic>{}),
        isNull,
      );
      // The existing repository-level all-positive gate still refuses
      // promotion of partial/unknown negatives into persisted authority.
    });
  });
}
