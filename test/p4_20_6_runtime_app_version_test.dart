import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('company registry card displays runtime package version, not static metadata', () {
    final myPage = File('lib/features/profile/my_page.dart').readAsStringSync();
    final card = File(
      'lib/features/profile/business_registry_update_card.dart',
    ).readAsStringSync();
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final lockfile = File('pubspec.lock').readAsStringSync();

    expect(myPage, contains('PackageInfo.fromPlatform()'));
    expect(myPage, contains("return build.isEmpty ? version : '\$version+\$build';"));
    expect(myPage, contains('appVersion: _installedAppVersion'));
    expect(card, contains('final String appVersion;'));
    expect(card, contains('value: appVersion'));
    expect(card, isNot(contains('AppBuildMetadata.appVersion')));
    expect(pubspec, contains('package_info_plus: 8.3.1'));
    expect(
      lockfile,
      contains(
        '  package_info_plus:\n'
        '    dependency: "direct main"',
      ),
    );
  });
}
