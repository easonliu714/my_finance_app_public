// CI infrastructure contract: preserve the strict API35 C18 witness while
// bounding the disposable emulator's userdata disk and classifying host disk.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('API35 host disk first failure has bounded preflight and AVD size', () {
    final workflow =
        File('.github/workflows/flutter_android_ci.yml').readAsStringSync();
    const jobAnchor = '  android-api35-two-process-lease:';
    expect(workflow, contains(jobAnchor));
    final job = workflow.substring(workflow.indexOf(jobAnchor));
    expect(job, contains('ANDROID_API35_HOST_AVAILABLE_MB='));
    expect(job, contains('ANDROID_API35_HOST_DISK_INSUFFICIENT_PREBOOT'));
    expect(job, contains('disk-size: 4096M'));
    expect(job, contains('PlatformResultProcessLeaseInstrumentedTest'));
    expect(job, contains('ANDROID_API35_JUNIT_XML_MISSING'));
    expect(job, isNot(contains('continue-on-error: true')));
  });
}
