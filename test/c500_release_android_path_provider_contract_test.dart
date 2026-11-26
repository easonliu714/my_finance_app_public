import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// C500 #1498 release-AOT dependency regression: preserve the last non-JNI
/// Android path provider during isolation of Android Context class lookup.
/// This contract does NOT claim that the JNI dependency is the proven root
/// cause until the exact-HEAD Android release-AOT emulator witness passes.
const _nonJniPin = '2.2.23';
const _nonJniSha256 =
    '149441ca6e4f38193b2e004c0ca6376a3d11f51fa5a77552d8bd4d2b0c0912ba';

bool _hasPinnedPreJniAndroidPathProvider(String pubspec, String lockfile) {
  final lines = pubspec.split('\n');
  if (lines.where((line) => line == '  path_provider_android: $_nonJniPin')
          .length !=
      1) {
    return false;
  }
  // Fail closed on lock drift: CI release-AOT must test the exact dependency
  // that was code-reviewed, not a transitive auto-upgrade to JNI 2.3.x.
  const marker = '  path_provider_android:\n';
  final at = lockfile.indexOf(marker);
  if (at < 0 || lockfile.indexOf(marker, at + marker.length) >= 0) {
    return false;
  }
  final end = lockfile.indexOf('\n  path_provider_foundation:', at);
  if (end < 0) return false;
  final block = lockfile.substring(at, end);
  return block ==
      '  path_provider_android:\n'
          '    dependency: "direct main"\n'
          '    description:\n'
          '      name: path_provider_android\n'
          '      sha256: "$_nonJniSha256"\n'
          '      url: "https://pub.dev"\n'
          '    source: hosted\n'
          '    version: "$_nonJniPin"';
}

/// Detect orphan package fields and duplicate YAML keys in pubspec.lock.
/// Complements flutter pub get --enforce-lockfile and isolates the regression.
bool _lockPackageSectionsAreWellFormed(String lockfile) {
  final start = lockfile.indexOf('packages:\n');
  final end = lockfile.indexOf('\nsdks:\n');
  if (start < 0 || end <= start) return false;
  final packages = lockfile.substring(start + 'packages:\n'.length, end);
  final labels = RegExp(r'^  [a-zA-Z0-9_]+:$', multiLine: true)
      .allMatches(packages).toList();
  if (labels.isEmpty) return false;
  for (var i = 0; i < labels.length; i++) {
    final from = labels[i].start;
    final to = i + 1 < labels.length ? labels[i + 1].start : packages.length;
    final block = packages.substring(from, to);
    if (RegExp(r'^    dependency: ', multiLine: true).allMatches(block).length != 1 ||
        RegExp(r'^    source: ', multiLine: true).allMatches(block).length != 1 ||
        RegExp(r'^    version: ', multiLine: true).allMatches(block).length != 1) {
      return false;
    }
  }
  return true;
}

// Shell interpolation must remain literal in Dart contract assertions. This
// predicate also makes both the approved command and unsafe mutation testable.
bool _hasIsolatedScaffoldCustody(String workflow) {
  return workflow.contains(r'scaffold="$(mktemp -d)"') &&
      workflow.contains(r'flutter create --no-pub --platforms=android --project-name my_finance_app_android "$scaffold"') &&
      workflow.contains(r'cp -an -- "$scaffold/android/." ./android/') &&
      workflow.contains('flutter pub get --enforce-lockfile') &&
      workflow.contains(
        'test -s packages/flutter_pdf_text/android/build.gradle',
      ) &&
      workflow.contains('test -d packages/flutter_pdf_text/android/src/main') &&
      workflow.contains('test ! -e android/flutter_pdf_text') &&
      !workflow.contains('test -d android/flutter_pdf_text') &&
      !workflow.contains('flutter create --no-pub --platforms=android .');
}

void main() {
  final pubspec = File('pubspec.yaml').readAsStringSync();
  final lockfile = File('pubspec.lock').readAsStringSync();

  // CI must resolve the committed graph without mutating pubspec.lock.
  // A normal pub get can silently change the dependency closure under test.
  test('CI enforces reviewed lockfile before Flutter tests', () {
    final workflow = File('.github/workflows/flutter_android_ci.yml')
        .readAsStringSync();
    expect(_hasIsolatedScaffoldCustody(workflow), isTrue);
    expect(workflow, contains('flutter pub get --enforce-lockfile'));
    expect(workflow, contains(r'flutter create --no-pub --platforms=android --project-name my_finance_app_android "$scaffold"'));
    expect(workflow, contains(r'scaffold="$(mktemp -d)"'));
    expect(workflow, contains(r'cp -an -- "$scaffold/android/." ./android/'));
    expect(workflow, contains('test -s packages/flutter_pdf_text/android/build.gradle'));
    expect(workflow, contains('PASS_C500_ISOLATED_ANDROID_SCAFFOLD_LOCK_CUSTODY'));
    expect(workflow, isNot(contains('flutter create --no-pub --platforms=android .')));
    // Only this job is subject to the reviewed-lockfile scaffold contract;
    // independent API35 and AOT jobs use their own Android host.
    final scaffoldStep = workflow.split('      - name: Ensure Android platform files exist').last
        .split('      - name: Patch Android permissions and desugaring').first;
    expect(scaffoldStep, isNot(contains('flutter create --platforms=android .')));
    expect(scaffoldStep, contains('flutter create --no-pub --platforms=android'));
    final unsafeStep = scaffoldStep.replaceFirst(
      'flutter create --no-pub --platforms=android --project-name my_finance_app_android',
      'flutter create --platforms=android',
    );
    expect(unsafeStep, contains('flutter create --platforms=android'));
    expect(_hasIsolatedScaffoldCustody(workflow.replaceFirst(
      'flutter create --no-pub --platforms=android --project-name my_finance_app_android',
      'flutter create --platforms=android',
    )), isFalse);
    expect(workflow, contains('git diff --exit-code -- pubspec.yaml pubspec.lock'));
    expect(workflow, contains('PASS_C500_CI_REVIEWED_LOCKFILE_UNCHANGED'));
    expect(workflow, isNot(contains('run: flutter pub get\\n')));
    final unsafeCreate = workflow.replaceFirst(
      r'flutter create --no-pub --platforms=android --project-name my_finance_app_android "$scaffold"',
      'flutter create --platforms=android .',
    );
    expect(unsafeCreate, isNot(contains(r'flutter create --no-pub --platforms=android --project-name my_finance_app_android "$scaffold"')));
    final unsafe = workflow.replaceFirst(
      'flutter pub get --enforce-lockfile', 'flutter pub get');
    expect(unsafe, isNot(contains('flutter pub get --enforce-lockfile')));
    expect(_hasIsolatedScaffoldCustody(unsafe), isFalse);
  });

  test('scaffold cannot write repository lockfile or silently skip custody', () {
    final workflow = File('.github/workflows/flutter_android_ci.yml').readAsStringSync();
    expect(workflow, isNot(contains('flutter create --no-pub --platforms=android .')));
    expect(workflow, contains('test -s packages/flutter_pdf_text/android/build.gradle'));
    expect(workflow, contains('git diff --exit-code -- pubspec.yaml pubspec.lock'));
    expect(workflow, contains(r'test -s "$scaffold/android/app/build.gradle.kts"'));
    expect(workflow, contains('test -d packages/flutter_pdf_text/android/src/main'));
    expect(workflow, contains('test ! -e android/flutter_pdf_text'));
    expect(workflow, isNot(contains('test -d android/flutter_pdf_text')));
    final falseLegacyGuard = workflow.replaceFirst('test -s packages/flutter_pdf_text/android/build.gradle', 'test -d android/flutter_pdf_text');
    expect(falseLegacyGuard, isNot(contains('test -s packages/flutter_pdf_text/android/build.gradle')));
    expect(_hasIsolatedScaffoldCustody(falseLegacyGuard), isFalse);
    final obsoleteNativeGuard = workflow.replaceFirst(
      'test -d packages/flutter_pdf_text/android/src/main',
      'test -d android/flutter_pdf_text',
    );
    expect(_hasIsolatedScaffoldCustody(obsoleteNativeGuard), isFalse);
    expect(_hasIsolatedScaffoldCustody(workflow.replaceFirst(r'cp -an -- "$scaffold/android/." ./android/', 'cp -a android .')), isFalse);
    final unsafe = workflow.replaceFirst(r'cp -an -- "$scaffold/android/." ./android/', r'cp -a -- "$scaffold" .');
    expect(unsafe, isNot(contains(r'cp -an -- "$scaffold/android/." ./android/')));
  });

  test('pre-JNI dependency closure excludes obsolete JNI tooling', () {
    for (final removed in <String>['jni', 'jni_flutter', 'package_config']) {
      expect(
        lockfile.contains('\n  $removed:\n'),
        isFalse,
        reason: 'Removed JNI dependency chain must not leave stale pub lock.',
      );
    }
  });

  test('lock cannot leave orphan dependency YAML fields', () {
    expect(_lockPackageSectionsAreWellFormed(lockfile), isTrue);
    final malformed = lockfile.replaceFirst(
      '  js:\n    dependency: transitive',
      '    dependency: transitive\n  js:\n    dependency: transitive',
    );
    expect(_lockPackageSectionsAreWellFormed(malformed), isFalse);
  });

  test('C500 release-AOT resolves exact reviewed pre-JNI Android provider',
      () {
    expect(_hasPinnedPreJniAndroidPathProvider(pubspec, lockfile), isTrue);
    expect(
      File('tool/run_c500_release_witness_android.sh')
          .readAsStringSync(),
      contains('C500_RELEASE_WITNESS_FAIL'),
      reason: 'Never bypass the actual Android release-AOT runtime gate.',
    );
  });

  test('C500 JNI 2.3.x dependency upgrade is rejected', () {
    expect(
      _hasPinnedPreJniAndroidPathProvider(
        pubspec.replaceFirst(
            '  path_provider_android: $_nonJniPin',
            '  path_provider_android: 2.3.1'),
        lockfile,
      ),
      isFalse,
    );
    expect(
      _hasPinnedPreJniAndroidPathProvider(
        pubspec,
        lockfile.replaceFirst('version: "$_nonJniPin"',
            'version: "2.3.1"'),
      ),
      isFalse,
    );
  });

  test('forged SHA and transitive-only pin never pass', () {
    expect(
      _hasPinnedPreJniAndroidPathProvider(
        pubspec,
        lockfile.replaceFirst(_nonJniSha256, '0' * 64),
      ),
      isFalse,
    );
    expect(
      _hasPinnedPreJniAndroidPathProvider(
        pubspec,
        lockfile.replaceFirst(
            '    dependency: "direct main"\n'
            '    description:\n'
            '      name: path_provider_android',
            '    dependency: transitive\n'
            '    description:\n'
            '      name: path_provider_android'),
      ),
      isFalse,
    );
  });
}
