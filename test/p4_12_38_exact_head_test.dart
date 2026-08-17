import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('candidate version matches the active release phase', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('version: 4.18.3+430'));
  });
}
