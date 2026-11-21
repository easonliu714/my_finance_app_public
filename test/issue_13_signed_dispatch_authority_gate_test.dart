import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('PR45 signed candidate requires Owner consent and unchanged live head',
      () async {
    if (Platform.isWindows) return; // Signed CI uses Ubuntu/Python3.
    final workflow = File(
      '.github/workflows/issue_13_invoice_award_mvp_signed_canary.yml',
    ).readAsStringSync();
    expect(workflow, contains("default: 'NO_SIGN'"));
    // Prevent a signed B2 canary from claiming unproven C500 authority.
    expect(workflow, isNot(contains(
      'CLOUD_500_PLATFORM_RENDERER_BOUNDED_BINARY_SEARCH=PASS',
    )));
    expect(workflow, contains(
      'CLOUD_500_PLATFORM_RENDERER_BOUNDED_BINARY_SEARCH=CONTRACT_ONLY_GLOBAL_PROOF_HOLD',
    ));
    for (final hold in [
      'C500_G0=HOLD_OFFICIAL_SEMANTIC_COMPLETENESS',
      'C500_G1=HOLD_OFFICIAL_COMPLETE_RECORD_FEED_UNPROVEN',
      'C500_G2_G4=HOLD_ANDROID_GLOBAL_PROOF_UNPROVEN',
      'C500_ANDROID_RESOURCE=NO_GO_TESTED_DIRECT_ENGINES_ONLY',
      'C500_GLOBAL_NOT_WIN=HOLD',
      'C500_G5_OWNER_CHOICE=HOLD',
      'C500_G6=BLOCKED_OWNER_TECHNICAL_CHOICE_AND_SECURITY',
    ]) {
      expect(workflow, contains(hold), reason: hold);
    }

    expect(workflow, contains(
      "inputs.owner_signing_authorization == 'AUTHORIZE_SIGNED_CANDIDATE_ONLY'",
    ));
    expect(workflow, contains(
      "github.ref == 'refs/heads/issue-13-invoice-award-official-data'",
    ));
    expect(workflow, contains(
      'python3 tool/issue_13_signed_dispatch_authority_gate.py',
    ));
    expect(
      workflow.indexOf(
        'Recheck Owner explicit signing consent and live PR45 head before secrets',
      ),
      lessThan(workflow.indexOf('Prepare signing files and pin certificate')),
    );

    final sha = List.filled(40, 'a').join();
    final pr = <String, Object?>{
      'number': 45,
      'state': 'open',
      'draft': true,
      'merged_at': null,
      'head': {
        'ref': 'issue-13-invoice-award-official-data',
        'sha': sha,
        'repo': {'full_name': 'easonliu714/my_finance_app_public'},
      },
      'base': {'ref': 'main'},
    };

    Future<Map<String, Object>> invoke(
      Map<String, Object?> response, {
      Map<String, String> overrides = const {},
    }) async {
      final environment = <String, String>{
        'GITHUB_EVENT_NAME': 'workflow_dispatch',
        'GITHUB_ACTOR': 'easonliu714',
        'GITHUB_REPOSITORY': 'easonliu714/my_finance_app_public',
        'GITHUB_REF': 'refs/heads/issue-13-invoice-award-official-data',
        'OWNER_SIGNING_AUTHORIZATION': 'AUTHORIZE_SIGNED_CANDIDATE_ONLY',
        'GITHUB_SHA': sha,
        ...overrides,
      };
      final process = await Process.start(
        'python3',
        ['tool/issue_13_signed_dispatch_authority_gate.py'],
        environment: environment,
      );
      process.stdin.write(jsonEncode(response));
      await process.stdin.close();
      final streams = await Future.wait([
        utf8.decoder.bind(process.stdout).join(),
        utf8.decoder.bind(process.stderr).join(),
      ]);
      final exitCode = await process.exitCode;
      return {'exit': exitCode, 'out': streams[0], 'err': streams[1]};
    }

    final good = await invoke(pr);
    expect(good['exit'], 0);
    expect(good['out'], contains('PASS_OWNER_CONSENT_EXACT_DRAFT_PR45_ONLY'));
    expect(good['out'], isNot(contains('SIGNED_APK=PASS')));

    final negativeEvents = <Map<String, String>>[
      {'GITHUB_EVENT_NAME': 'push'},
      {'GITHUB_ACTOR': 'another-writer'},
      {'GITHUB_REPOSITORY': 'another/repo'},
      {'GITHUB_REF': 'refs/heads/main'},
      {'OWNER_SIGNING_AUTHORIZATION': 'NO_SIGN'},
      {'GITHUB_SHA': List.filled(40, 'b').join()},
    ];
    for (final changed in negativeEvents) {
      final result = await invoke(pr, overrides: changed);
      expect(result['exit'], isNot(0), reason: changed.toString());
      expect(result['err'], contains('SIGNED_DISPATCH_AUTHORITY=HOLD_'));
    }

    final notDraft = Map<String, Object?>.from(pr)..['draft'] = false;
    final merged = Map<String, Object?>.from(pr)
      ..['merged_at'] = '2026-11-05T00:00:00Z';
    final closed = Map<String, Object?>.from(pr)..['state'] = 'closed';
    for (final invalidPr in [notDraft, merged, closed]) {
      final result = await invoke(invalidPr);
      expect(result['exit'], isNot(0));
      expect(result['err'], contains('HOLD_PR45_STATE_OR_SCOPE_MISMATCH'));
    }
  });
}
