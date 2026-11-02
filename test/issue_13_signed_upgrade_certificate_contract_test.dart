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
    expect(canonical, '9BA2CA64E4218795A4313EFB8FDC020011DCEAE0C70F6F0614DF28328BBEDEB7');
    expect(RegExp(r'^(?:[A-F0-9]{2}:){31}[A-F0-9]{2}$', multiLine: true).allMatches(security), hasLength(1));
    expect(security, contains('36:1A:08:06:C3:1E:CE:FF:B0:DE:AD:7E:DA:5F:BC:D7:68:84:5D:8A:00:D6:69:B0:23:2B:8C:11:21:0A:ED:1A'));
    expect(security, contains('38562441477'));
    expect(security, contains('38562431249'));
    expect(security, contains('108d9f77065fbed24e5342fa7f49ec4496cca698dda0fc42fc3a7dd5db65bf63'));

    final pins = RegExp(r"^\s+pinned='([A-F0-9]{64})'$", multiLine: true)
        .allMatches(workflow)
        .map((match) => match.group(1)!)
        .toList();
    expect(pins, hasLength(2));
    final preflight = File('tool/issue_13_signer_continuity_preflight.sh').readAsStringSync();
    final preflightPin = RegExp(r"pinned='([A-F0-9]{64})'").firstMatch(preflight)?.group(1);
    expect(preflightPin, pins.first);
    // The public release-security document must be byte-for-byte identical
    // to the independently read trusted-main blob, not only share a pin.
    final docHash = Process.runSync('git', [
      'hash-object',
      'docs/public_release_signing_security.md',
    ]);
    expect(docHash.exitCode, 0);
    expect(
      preflight,
      contains("canonical_blob='${docHash.stdout.toString().trim()}'"),
    );
    expect(RegExp(r'bash tool/issue_13_signer_continuity_preflight.sh').allMatches(workflow), hasLength(2));
    expect(workflow.indexOf('Fail fast on independent installed-upgrade signer continuity'), lessThan(workflow.indexOf('uses: subosito/flutter-action@v2')));
    // Fail before CI polling or toolchain setup; preserve the immutable signer hold.
    expect(workflow.indexOf('Fail fast on independent installed-upgrade signer continuity'), lessThan(workflow.indexOf('Wait for exact-head Flutter Android CI authority')));
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

  // Execute the real Bash preflight using public synthetic certificate data.
  // No keystore, installed app, signing secret, or finance DB is accessed.
  test('Issue #13 signer preflight enforces parity and unique authority', () async {
    if (Platform.isWindows) return; // GitHub signed runner uses Ubuntu Bash.
    final source = File('tool/issue_13_signer_continuity_preflight.sh')
        .readAsStringSync();
    final security =
        File('docs/public_release_signing_security.md').readAsStringSync();
    final canonicalMatch =
        RegExp(r'^(?:[A-F0-9]{2}:){31}[A-F0-9]{2}$', multiLine: true)
            .firstMatch(security);
    expect(canonicalMatch, isNotNull);
    final canonicalLine = canonicalMatch!.group(0)!;
    final pin = RegExp(r"pinned='([A-F0-9]{64})'")
        .firstMatch(source)!
        .group(1)!;
    final matchingLine = List.generate(
      32,
      (index) => pin.substring(index * 2, index * 2 + 2),
    ).join(':');

    final root = Directory.systemTemp.createTempSync('issue13-signer-');
    try {
      final script = File(
        '${root.path}/tool/issue_13_signer_continuity_preflight.sh',
      );
      script.parent.createSync(recursive: true);
      script.writeAsStringSync(source);
      final baseline = File(
        '${root.path}/docs/public_release_signing_security.md',
      );
      baseline.parent.createSync(recursive: true);
      Future<ProcessResult> invoke(String fixture, {bool trustFixture = false}) async {
        baseline.writeAsStringSync(fixture);
        final digestResult = await Process.run('git', ['hash-object', baseline.path]);
        expect(digestResult.exitCode, 0);
        final digest = digestResult.stdout.toString().trim();
        // Only synthetic fixtures may replace the immutable blob anchor.
        script.writeAsStringSync(trustFixture
            ? source.replaceFirst(
                RegExp(r"canonical_blob='[0-9a-f]{40}'"),
                "canonical_blob='$digest'",
              )
            : source);
        return Process.run(
          'bash',
          ['tool/issue_13_signer_continuity_preflight.sh'],
          workingDirectory: root.path,
        );
      }

      final baseline = await invoke(security);
      expect(baseline.exitCode, 0);
      expect(baseline.stdout.toString(), contains('PIN_PARITY_ONLY_DEVICE_REQUIRED'));
      expect(baseline.stdout.toString(), isNot(contains('=PASS')));

      // A PR-local edit to the documented certificate may not make an
      // otherwise mismatched signer appear upgrade-compatible.
      final historicalLine = '36:1A:08:06:C3:1E:CE:FF:B0:DE:AD:7E:DA:5F:BC:D7:68:84:5D:8A:00:D6:69:B0:23:2B:8C:11:21:0A:ED:1A';
      final forgedParity = await invoke(
        security.replaceFirst(canonicalLine, historicalLine),
      );
      expect(forgedParity.exitCode, isNot(0));
      expect(
        forgedParity.stderr.toString(),
        contains('HOLD_CANONICAL_DOC_DRIFT'),
      );
      final unrelatedDocEdit = await invoke(
        security.replaceFirst(
          'The certificate fingerprint is public verification material.',
          'The certificate fingerprint is public verification material!',
        ),
      );
      expect(unrelatedDocEdit.exitCode, isNot(0));
      expect(
        unrelatedDocEdit.stderr.toString(),
        contains('HOLD_CANONICAL_DOC_DRIFT'),
      );

      final parity = await invoke(
        security.replaceFirst(canonicalLine, matchingLine),
        trustFixture: true,
      );
      expect(parity.exitCode, 0);
      expect(
        parity.stdout.toString(),
        contains('PIN_PARITY_ONLY_DEVICE_REQUIRED'),
      );
      expect(parity.stdout.toString(), isNot(contains('=PASS')));

      final trustedLegacy = await invoke(
        security.replaceFirst(canonicalLine, historicalLine),
        trustFixture: true,
      );
      expect(trustedLegacy.exitCode, isNot(0));
      expect(trustedLegacy.stderr.toString(), contains('HOLD_DOC_PIN_MISMATCH'));

      final missing = await invoke(
        security.replaceFirst(canonicalLine, 'INVALID_CERTIFICATE'),
        trustFixture: true,
      );
      expect(missing.exitCode, isNot(0));
      expect(
        missing.stderr.toString(),
        contains('HOLD_CANONICAL_CERT_AMBIGUOUS'),
      );

      final duplicate = await invoke(
        security.replaceFirst(
          canonicalLine,
          '$canonicalLine\n$canonicalLine',
        ),
        trustFixture: true,
      );
      expect(duplicate.exitCode, isNot(0));
      expect(
        duplicate.stderr.toString(),
        contains('HOLD_CANONICAL_CERT_AMBIGUOUS'),
      );
    } finally {
      root.deleteSync(recursive: true);
    }
  });
}
