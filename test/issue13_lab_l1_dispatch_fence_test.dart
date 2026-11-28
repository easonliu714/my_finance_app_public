import 'dart:convert';
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

  test('concurrent dispatch reservations permit only one durable marker',
      () async {
    Future<bool> attempt(LabL1DispatchFence fence, int page, String id) async {
      try {
        await fence.begin(firstPage: page, requestId: id, pdfSha256: sha);
        return true;
      } on StateError {
        return false;
      }
    }

    final first = LabL1DispatchFence(directory);
    final second = LabL1DispatchFence(directory);
    final results = await Future.wait(<Future<bool>>[
      attempt(first, 1, request),
      attempt(second, 5, '1234567890123457'),
    ]);
    expect(results.where((result) => result).length, 1);
    final marker = File('${directory.path}/l1-native-inflight.json');
    final bytes = await marker.readAsString();
    expect(bytes.trimRight().split('\\n').length, 1);
    expect(bytes, contains('"pdf_sha256":"$sha"'));
    expect(
      bytes,
      contains(results.first
          ? '"request_id":"$request"'
          : '"request_id":"1234567890123457"'),
    );
    await expectLater(first.requireClear(), throwsA(unresolved()));
    await expectLater(second.requireClear(), throwsA(unresolved()));
  });

  test('existing valid marker bytes are never overwritten by a second begin',
      () async {
    final fence = LabL1DispatchFence(directory);
    await fence.begin(firstPage: 1, requestId: request, pdfSha256: sha);
    final marker = File('${directory.path}/l1-native-inflight.json');
    final before = await marker.readAsBytes();
    await expectLater(
      LabL1DispatchFence(directory).begin(
        firstPage: 5,
        requestId: '1234567890123457',
        pdfSha256: sha,
      ),
      throwsA(unresolved()),
    );
    expect(await marker.readAsBytes(), before);
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

  Map<String, dynamic> ownerTerminal(String role, String id) => <String, dynamic>{
        'request_id': id,
        'status': 'complete',
        'stage': 'L1_OWNER_RENDERER_OPEN_COMPLETE',
        'role': role,
        'page_count': 77000,
        'authority': 'LAB_OWNER_ATTESTED_BYTES_ONLY',
        'global_not_win': 'HOLD',
      };

  test('owner-open marker survives restart and blocks other period export',
      () async {
    await LabL1DispatchFence(directory).beginOwnerOpen(
      role: 'sorted', requestId: request,
    );
    final restarted = LabL1DispatchFence(directory);
    await expectLater(restarted.requireClear(), throwsA(unresolved()));
    await expectLater(
      restarted.begin(firstPage: 1, requestId: request, pdfSha256: sha),
      throwsA(unresolved()),
    );
    await expectLater(
      restarted.beginOwnerOpen(role: 'draw_order', requestId: request),
      throwsA(unresolved()),
    );
  });

  test('only matching role and closed terminal can clear owner-open marker',
      () async {
    final fence = LabL1DispatchFence(directory);
    await fence.beginOwnerOpen(role: 'sorted', requestId: request);
    final restarted = LabL1DispatchFence(directory);
    for (final invalid in <Map<String, dynamic>>[
      {...ownerTerminal('sorted', request), 'status': 'process_exit'},
      {...ownerTerminal('sorted', request), 'status': 'failure'},
      {...ownerTerminal('sorted', request), 'page_count': 76999},
      {...ownerTerminal('sorted', request), 'stage': 'PLATFORM_RENDERER_OPEN_OK'},
      {...ownerTerminal('sorted', request), 'global_not_win': 'PASS'},
      {...ownerTerminal('sorted', request), 'authority': 'unknown'},
      ownerTerminal('draw_order', request),
      ownerTerminal('sorted', '999'),
    ]) {
      await expectLater(
        restarted.completeOwnerOpen(role: 'sorted', requestId: request,
          result: invalid),
        throwsA(unresolved()),
      );
      await expectLater(restarted.requireClear(), throwsA(unresolved()));
    }
    await expectLater(
      restarted.completeOwnerOpen(role: 'draw_order', requestId: request,
        result: ownerTerminal('draw_order', request)),
      throwsA(unresolved()),
    );
    await expectLater(
      restarted.complete(firstPage: 1, requestId: request, pdfSha256: sha),
      throwsA(unresolved()),
    );
    await restarted.completeOwnerOpen(role: 'sorted', requestId: request,
      result: ownerTerminal('sorted', request));
    await restarted.requireClear();
    await restarted.beginOwnerOpen(role: 'draw_order', requestId: '999');
    await expectLater(restarted.requireClear(), throwsA(unresolved()));
  });

  test('restart recovers only exact retained owner-open terminal', () async {
    final fence = LabL1DispatchFence(directory);
    expect(await fence.recoverOwnerOpen(), isFalse);
    await fence.beginOwnerOpen(role: 'sorted', requestId: request);
    final terminal = File('${directory.path}/platform_probe_$request.json');
    final receipt = jsonEncode(ownerTerminal('sorted', request));
    await terminal.writeAsString(receipt, flush: true);
    final restarted = LabL1DispatchFence(directory);
    expect(await restarted.recoverOwnerOpen(), isTrue);
    expect(await terminal.readAsString(), receipt);
    await restarted.requireClear();
    expect(await restarted.recoverOwnerOpen(), isFalse);
    await restarted.beginOwnerOpen(role: 'draw_order', requestId: '999');
  });

  test('restart retains owner marker for missing or untrusted terminal',
      () async {
    final fence = LabL1DispatchFence(directory);
    await fence.beginOwnerOpen(role: 'sorted', requestId: request);
    final marker = File('${directory.path}/l1-native-inflight.json');
    final before = await marker.readAsBytes();
    final terminal = File('${directory.path}/platform_probe_$request.json');
    final restarted = LabL1DispatchFence(directory);
    await expectLater(restarted.recoverOwnerOpen(), throwsA(unresolved()));
    for (final invalid in <String>[
      '{',
      '[]',
      List<String>.filled(4097, 'x').join(),
      jsonEncode(ownerTerminal('draw_order', request)),
      jsonEncode(ownerTerminal('sorted', '999')),
      jsonEncode({...ownerTerminal('sorted', request), 'status': 'running'}),
      jsonEncode({...ownerTerminal('sorted', request), 'status': 'failure'}),
      jsonEncode({...ownerTerminal('sorted', request), 'status': 'process_exit'}),
      jsonEncode({...ownerTerminal('sorted', request), 'stage': 'PLATFORM_RENDERER_OPEN_OK'}),
    ]) {
      await terminal.writeAsString(invalid, flush: true);
      await expectLater(restarted.recoverOwnerOpen(), throwsA(unresolved()));
      expect(await marker.readAsBytes(), before);
    }
    await terminal.delete();
    final outside = File('${directory.path}/outside.json');
    await outside.writeAsString(jsonEncode(ownerTerminal('sorted', request)));
    await Link(terminal.path).create(outside.path);
    await expectLater(restarted.recoverOwnerOpen(), throwsA(unresolved()));
    expect(await marker.readAsBytes(), before);
  });

  test('restart recovery never consumes legacy export marker', () async {
    final fence = LabL1DispatchFence(directory);
    await fence.begin(firstPage: 1, requestId: request, pdfSha256: sha);
    final marker = File('${directory.path}/l1-native-inflight.json');
    final before = await marker.readAsBytes();
    await File('${directory.path}/platform_probe_$request.json')
        .writeAsString(jsonEncode(ownerTerminal('sorted', request)));
    expect(await LabL1DispatchFence(directory).recoverOwnerOpen(), isFalse);
    expect(await marker.readAsBytes(), before);
    await expectLater(fence.requireClear(), throwsA(unresolved()));
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

  test('draw page recovery rejects mismatched or incomplete terminal', () async {
    final fence = LabL1DispatchFence(directory);
    await fence.beginDrawPage(page: 77000, requestId: request, pdfSha256: sha);
    final restarted = LabL1DispatchFence(directory);
    final terminal = File('${directory.path}/platform_probe_$request.json');
    await expectLater(restarted.recoverOwnerOpen(), throwsA(unresolved()));
    final receipt = <String, dynamic>{
      'request_id': request,
      'status': 'complete',
      'stage': 'L1_OWNER_DRAW_PAGE_COMPLETE',
      'role': 'draw_order',
      'page': 77000,
      'page_count': 77000,
      'pages_read': 1,
      'pdf_sha256': sha,
      'authority': 'LAB_OWNER_ATTESTED_BYTES_ONLY',
      'global_not_win': 'HOLD',
      'tokens': List.generate(50, (i) => 'AB${i.toString().padLeft(8, '0')}'),
    };
    for (final invalid in <String, dynamic>{
      'status': 'running',
      'page': 1,
      'role': 'sorted',
      'pdf_sha256': 'wrong',
      'global_not_win': 'PASS',
      'pages_read': 0,
      'tokens': List.filled(50, 'AB00000000'),
    }.entries) {
      await terminal.writeAsString(jsonEncode({...receipt, invalid.key: invalid.value}));
      await expectLater(restarted.recoverOwnerOpen(), throwsA(unresolved()));
      await expectLater(restarted.requireClear(), throwsA(unresolved()));
    }
    await terminal.writeAsString(jsonEncode(receipt));
    expect(await restarted.recoverOwnerOpen(), isTrue);
    await restarted.requireClear();
  });
}
