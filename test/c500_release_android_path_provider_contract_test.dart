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

void main() {
  final pubspec = File('pubspec.yaml').readAsStringSync();
  final lockfile = File('pubspec.lock').readAsStringSync();

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
