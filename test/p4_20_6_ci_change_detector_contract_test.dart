import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Flutter CI non-doc detector is safe under pipefail', () {
    final workflow =
        File('.github/workflows/flutter_android_ci.yml').readAsStringSync();

    expect(
      workflow,
      isNot(contains(
        "grep -Ev '^(docs/|.*\\.md$|\\.gitignore$)' changed_files.txt | grep -q .",
      )),
    );
    expect(workflow, contains('> non_docs_changed_files.txt || true'));
    expect(workflow, contains('if [[ -s non_docs_changed_files.txt ]]'));
    expect(workflow, contains('reason="non-docs files changed"'));
  });
}
