import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('canonical Flutter Android CI remains and obsolete workflows stay removed', () {
    expect(
      File('.github/workflows/flutter_android_ci.yml').existsSync(),
      isTrue,
    );

    const obsoletePaths = <String>[
      '.github/workflows/p4_12_18_current_diagnostics.yml',
      '.github/workflows/p4_12_20_detail_review_ci.yml',
      '.github/workflows/p4_12_21_formal_import_ci.yml',
      '.github/workflows/p4_12_23_signed_validation.yml',
      '.github/workflows/p4_12_25_signed_validation.yml',
      '.github/workflows/p4_12_26_signed_validation.yml',
      '.github/workflows/p4_12_27_signed_validation.yml',
      '.github/workflows/p4_12_34_test_diagnostics.yml',
    ];

    for (final path in obsoletePaths) {
      expect(File(path).existsSync(), isFalse, reason: path);
    }
  });
}
