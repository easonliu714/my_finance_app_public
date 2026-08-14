import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('pubspec keeps the Material icon asset declaration', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();

    expect(pubspec, contains('flutter:\n  uses-material-design: true'));
  });
}
