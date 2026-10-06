import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('cloud eligibility confirmation is local and accounting-readonly', () {
    final confirmation = File(
      'lib/features/invoice/invoice_award_cloud_eligibility_confirmation.dart',
    ).readAsStringSync();
    final page = File(
      'lib/features/invoice/invoice_award_production_page.dart',
    ).readAsStringSync();
    expect(confirmation, contains('confirmedAtUtc'));
    expect(confirmation, contains('officialPdfSha256'));
    expect(confirmation, contains('candidateSourceProvenance'));
    expect(confirmation, contains('canAuthorizeFutureBookkeepingEligibility'));
    expect(confirmation, isNot(contains('ProductionDatabaseCoordinator')));
    expect(confirmation, isNot(contains('INSERT INTO transactions')));
    expect(page, contains('確認符合資格'));
    expect(page, contains('確認不符合資格'));
    expect(page, contains('本版不會建立交易'));
  });

  test('review notification is distinct from confirmed winner authority', () {
    final runtime = File(
      'lib/features/invoice/invoice_award_notification_runtime.dart',
    ).readAsStringSync();
    final matcher = File(
      'lib/features/invoice/existing_invoice_award_cloud_batch_matcher.dart',
    ).readAsStringSync();
    expect(runtime, contains('eligibilityReviewRequired'));
    expect(runtime, contains('可能中獎，請確認資格'));
    expect(runtime, contains('matchedReviewRequired'));
    expect(matcher, contains('scopedPdfShaByTier'));
    expect(matcher, contains('scopedAuthority.pdfSha256'));
  });
}
