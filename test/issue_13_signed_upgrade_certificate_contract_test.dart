import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  // Issue #13: a signed canary is not an in-place upgrade until its signer
  // agrees with the independent release-security baseline. This is a
  // repository-only contract; no keystore or installed database is opened.
  test('Issue #13 signed canary fails closed on certificate drift', () {
    final security =
        File('docs/public_release_signing_security.md').readAsStringSync();
    final workflow = File(
      '.github/workflows/issue_13_invoice_award_mvp_signed_canary.yml',
    ).readAsStringSync();

    final canonicalMatch =
        RegExp(r'^(?:[A-F0-9]{2}:){31}[A-F0-9]{2}$', multiLine: true)
            .firstMatch(security);
    expect(canonicalMatch, isNotNull);
    final canonical = canonicalMatch!.group(0)!.replaceAll(':', '');
    expect(canonical, hasLength(64));

    final pins = RegExp(r"^\s+pinned='([A-F0-9]{64})'$", multiLine: true)
        .allMatches(workflow)
        .map((match) => match.group(1)!)
        .toList();
    expect(pins, hasLength(2));
    expect(pins.toSet(), hasLength(1));
    expect(workflow, contains('docs/public_release_signing_security.md'));
    expect(workflow, contains('SIGNER_UPGRADE_COMPATIBILITY=HOLD_DOC_PIN_MISMATCH'));
    expect(
      workflow,
      contains('SIGNER_UPGRADE_COMPATIBILITY=PIN_PARITY_ONLY_DEVICE_REQUIRED'),
    );
    expect(workflow, contains('exit 1'));

    // When the observed pins differ, no implicit upgrade PASS is allowed.
    if (pins.first != canonical) {
      expect(workflow, isNot(contains('SIGNER_UPGRADE_COMPATIBILITY=PASS')));
    }
  });
}
