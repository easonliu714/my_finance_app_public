import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/issue13_lab_l1_dispatch_fence.dart';

void main() {
  const sha =
      'f50d0dcebc7497c51ce2eea9da9525232e638fdc4103decc6a8e0a1c1dac5571';
  const request = '1234567890123456';
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('l1-dispatch-fence-');
  });
  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  Matcher unresolved() => isA<StateError>().having(
        (e) => e.toString(),
        'unresolved native process',
        contains(LabL1DispatchFence.unresolved),
      );

  test('exclusive marker blocks duplicate and survives app restart', () async {
    final first = LabL1DispatchFence(directory);
    await first.begin(firstPage: 1, requestId: request, pdfSha256: sha);
    final restarted = LabL1DispatchFence(directory);
    await expectLater(restarted.requireClear(), throwsA(unresolved()));
    await expectLater(
      restarted.begin(firstPage: 1, requestId: request, pdfSha256: sha),
      throwsA(unresolved()),
    );
    expect(
      await File('${directory.path}/l1-native-inflight.json').exists(),
      isTrue,
    );
  });

  test('wrong request, page or source cannot clear in-flight evidence', () async {
    final fence = LabL1DispatchFence(directory);
    await fence.begin(firstPage: 5, requestId: request, pdfSha256: sha);
    final wrong = <(int, String, String)>[
      (5, '9999999999999999', sha),
      (1, request, sha),
      (5, request, List<String>.filled(64, '0').join()),
    ];
    for (final args in wrong) {
      await expectLater(
        fence.complete(
          firstPage: args.$1,
          requestId: args.$2,
          pdfSha256: args.$3,
        ),
        throwsA(unresolved()),
      );
    }
    await expectLater(fence.requireClear(), throwsA(unresolved()));
    await fence.complete(firstPage: 5, requestId: request, pdfSha256: sha);
    await fence.requireClear();
  });

  test('torn or malformed marker remains HOLD', () async {
    final marker = File('${directory.path}/l1-native-inflight.json');
    await marker.writeAsString('{"version":1');
    final fence = LabL1DispatchFence(directory);
    await expectLater(fence.requireClear(), throwsA(unresolved()));
    await expectLater(
      fence.complete(firstPage: 1, requestId: request, pdfSha256: sha),
      throwsA(unresolved()),
    );
    expect(await marker.readAsString(), '{"version":1');
  });

  test('symlinked marker is not followed or overwritten', () async {
    final target = File('${directory.path}/outside.txt');
    await target.writeAsString('preserve');
    final link = Link('${directory.path}/l1-native-inflight.json');
    await link.create(target.path);
    final fence = LabL1DispatchFence(directory);
    await expectLater(fence.requireClear(), throwsA(unresolved()));
    await expectLater(
      fence.begin(firstPage: 1, requestId: request, pdfSha256: sha),
      throwsA(unresolved()),
    );
    expect(await target.readAsString(), 'preserve');
  });

  test('terminal verified completion permits later dispatch', () async {
    final fence = LabL1DispatchFence(directory);
    await fence.requireClear();
    await fence.begin(firstPage: 1, requestId: request, pdfSha256: sha);
    await fence.complete(firstPage: 1, requestId: request, pdfSha256: sha);
    await fence.requireClear();
    await fence.begin(
      firstPage: 5,
      requestId: '1234567890123457',
      pdfSha256: sha,
    );
    await expectLater(fence.requireClear(), throwsA(unresolved()));
  });
}
