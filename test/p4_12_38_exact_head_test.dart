import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('candidate version matches the active Issue #13 release phase', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('version: 4.20.7+465'));
  });
}
