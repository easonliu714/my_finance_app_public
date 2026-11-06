import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  // CI #1390 built a release-AOT APK but then held because the assumed
  // ~/.android/debug.keystore was absent. The ephemeral CI signer must be
  // provisioned before Gradle builds, with no production signing authority.
  test('C500 release-AOT witness provisions and verifies disposable signer', () {
    final workflow = File('.github/workflows/flutter_android_ci.yml')
        .readAsStringSync();
    const jobMarker = '  c500-release-aot-witness:';
    expect(jobMarker.allMatches(workflow), hasLength(1));
    final job = workflow.substring(workflow.indexOf(jobMarker));
    const provision =
        '- name: Provision disposable debug signer for C500 release-AOT witness';
    const build =
        '- name: Build ephemeral release-AOT witness with default debug key only';
    expect(provision.allMatches(job), hasLength(1));
    expect(build.allMatches(job), hasLength(1));
    expect(job.indexOf(provision), lessThan(job.indexOf(build)));

    final setup = job.substring(job.indexOf(provision), job.indexOf(build));
    expect(setup, contains('umask 077'));
    expect(setup, contains(r'if [[ -e "$HOME/.android/debug.keystore" ]]'));
    expect(setup, contains('HOLD_WITNESS_UNEXPECTED_PREEXISTING_DEBUG_KEY'));
    expect(setup, contains('keytool -genkeypair -noprompt'));
    expect(setup, contains('-alias androiddebugkey'));
    expect(setup, contains('-storepass android -keypass android'));
    expect(setup, contains('-validity 2'));
    expect(setup, contains('HOLD_WITNESS_DEBUG_KEY_GENERATION_FAILED'));
    expect(setup, contains('C500_WITNESS_DISPOSABLE_DEBUG_KEY_READY'));

    final verify = job.substring(job.indexOf(build));
    expect(verify, contains('HOLD_WITNESS_APK_SIGNATURE_INVALID'));
    expect(verify, contains('HOLD_WITNESS_DEBUG_SIGNER_MISMATCH'));
    expect(verify, contains('C500_WITNESS_DEBUG_SIGNER_MATCH'));
    expect(verify, contains('Execute real release-AOT on disposable Android API35 emulator'));
    expect(job, contains("github.event_name == 'pull_request' && github.event.pull_request.number == 45"));
    expect(job, isNot(contains('secrets.')));
    expect(job, isNot(contains('actions/upload-artifact')));
    expect(job, isNot(contains('9BA2CA64E4218795A4313EFB8FDC020011DCEAE0C70F6F0614DF28328BBEDEB7')));
  });
}
