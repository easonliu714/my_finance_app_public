import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:cryptography/cryptography.dart' as cryptography;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:my_finance_app/issue13_cloud500_diag_main.dart';
import 'package:my_finance_app/issue13_lab_l1_evidence_bundle.dart';

const head = 'cbaad08aa3709d098951797a841a98b43aa2c912';

Map<String, Object> row(int page) => <String, Object>{
  'page': page,
  'page_count': 87000,
  'pdf_sha256': LabL1EvidenceBundle.officialSha256,
  'engine': 'android.graphics.pdf.PdfRenderer',
  'period': '115-07-08',
  'tier': 'cloud-500',
  'text': 'AB${page.toString().padLeft(8, '0')}',
};

void main() {
  late Directory root;
  late Directory lab;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('l1-bundle-');
    lab = Directory('${root.path}/issue13_cloud500_diag');
    await lab.create();
    await File('${lab.path}/issue13_cloud500_diag.log')
        .writeAsString('DART LAB L1 SOURCE PREFLIGHT PASS\n', flush: true);
    await File('${root.path}/issue13_cloud500_diag_native.log')
        .writeAsString('NATIVE PLATFORM_RENDERER_OPEN_OK\n', flush: true);
  });
  tearDown(() async => root.delete(recursive: true));

  Future<void> batch(int first, {String id = '123456'}) async {
    final file = File('${lab.path}/l1-pages-$first-$id.jsonl');
    await file.writeAsString(
      '${[for (var p = first; p < first + 4; p++) jsonEncode(row(p))].join('\n')}\n',
      flush: true,
    );
  }

  Future<void> prepare(int n) async {
    for (var i = 0; i < n; i++) {
      await batch(1 + i * 4);
    }
    await File('${lab.path}/l1-next-page.txt')
        .writeAsString('${1 + n * 4}\n', flush: true);
  }

  Future<void> hold() async {
    await expectLater(
      LabL1EvidenceBundle.create(lab: lab, labHead: head),
      throwsStateError,
    );
    expect(await File('${lab.path}/l1-evidence-share.zip').exists(), isFalse);
  }

  test('nine batches produce one bounded ZIP, manifest and two logs', () async {
    await prepare(9);
    // A PDF file may exist locally but must never enter the shared bundle.
    await File('${lab.path}/${LabL1EvidenceBundle.officialSha256}.pdf')
        .writeAsString('not an actual PDF');
    final result = await LabL1EvidenceBundle.create(
      lab: lab, labHead: head,
    );
    expect(result.zipSha256, matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(result.manifest['batch_count'], 9);
    expect(result.manifest['last_page'], 36);
    expect(result.manifest['cursor_next_page'], 37);
    expect(result.manifest['official_full_page_evidence'], 'HOLD');
    expect(result.manifest['global_not_win'], 'HOLD');
    final zip = ZipDecoder().decodeBytes(await result.file.readAsBytes());
    final names = zip.files.map((f) => f.name).toList();
    expect(names.length, 12);
    expect(names, containsAll(<String>[
      'l1-pages-1-123456.jsonl',
      'l1-pages-33-123456.jsonl',
      'manifest.json',
      'dart-debug.log',
      'native-debug.log',
    ]));
    expect(names.any((n) => n.endsWith('.pdf')), isFalse);
    final manifestEntry = zip.files.singleWhere((f) => f.name == 'manifest.json');
    final manifest = jsonDecode(utf8.decode(manifestEntry.readBytes()!))
        as Map<String, dynamic>;
    expect(manifest['source_pin_basis'],
        'owner_runtime_log_not_independent_pdf_rehash');
    final records = manifest['jsonl'] as List<dynamic>;
    expect(records.length, 9);
    // Regression: verify the manifest hashes the real JSONL bytes, not an
    // unrelated archive SHA implementation with the same class name.
    final firstJsonl = File('${lab.path}/l1-pages-1-123456.jsonl');
    final independentDigest = await cryptography.Sha256()
        .hash(await firstJsonl.readAsBytes());
    final independentHex = independentDigest.bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    expect((records.first as Map)['sha256'], independentHex);
    expect((records.first as Map)['first_page'], 1);
    expect((records.last as Map)['last_page'], 36);
    expect(await File('${lab.path}/l1-next-page.txt').readAsString(), '37\n');
  });

  test('missing middle batch fails closed', () async {
    await prepare(9);
    await File('${lab.path}/l1-pages-5-123456.jsonl').delete();
    await hold();
  });

  test('duplicate first page cannot be silently selected', () async {
    await prepare(1);
    await batch(1, id: '123457');
    await hold();
  });

  test('torn native batch refuses share', () async {
    await prepare(1);
    await File('${lab.path}/l1-pages-5-123456.jsonl.part')
        .writeAsString('partial');
    await hold();
  });

  test('source SHA drift fails before packaging', () async {
    await prepare(1);
    final file = File('${lab.path}/l1-pages-1-123456.jsonl');
    final rows = <String>[];
    for (var i = 1; i <= 4; i++) {
      final bad = row(i);
      bad['pdf_sha256'] = List.filled(64, '0').join();
      rows.add(jsonEncode(bad));
    }
    await file.writeAsString('${rows.join('\n')}\n');
    await hold();
  });

  test('symlinked JSONL cannot enter bundle', () async {
    await prepare(1);
    final file = File('${lab.path}/l1-pages-1-123456.jsonl');
    final external = File('${root.path}/outside.jsonl');
    await file.rename(external.path);
    await Link(file.path).create(external.path);
    await hold();
  });

  test('cursor beyond durable batch fails closed', () async {
    await prepare(1);
    await File('${lab.path}/l1-next-page.txt').writeAsString('9\n');
    await hold();
  });

  test('inflight native marker forbids share', () async {
    await prepare(1);
    await File('${lab.path}/l1-native-inflight.json')
        .writeAsString('unresolved');
    await hold();
  });

  test('bounded log and batch budgets fail closed', () async {
    await prepare(1);
    await File('${lab.path}/issue13_cloud500_diag.log')
        .writeAsBytes(List<int>.filled(
          LabL1EvidenceBundle.maxLogBytes + 1, 65,
        ));
    await hold();
  });

  test('more than twelve batches refuses unbounded archive', () async {
    await prepare(13);
    await hold();
  });

  test('eighteen retained batches export two bounded linked real ZIPs',
      () async {
    await prepare(18);
    final first = await LabL1EvidenceBundle.create(
        lab: lab, labHead: head, windowIndex: 1);
    final second = await LabL1EvidenceBundle.create(
        lab: lab, labHead: head, windowIndex: 2);
    expect(first.manifest['batch_count'], 12);
    expect(second.manifest['batch_count'], 6);
    expect(first.manifest['window_first_page'], 1);
    expect(first.manifest['window_last_page'], 48);
    expect(second.manifest['window_first_page'], 49);
    expect(second.manifest['window_last_page'], 72);
    expect(first.manifest['durable_cursor_next_page'], 73);
    expect(second.manifest['durable_cursor_next_page'], 73);
    expect(second.manifest['previous_window_chain_sha256'],
        first.manifest['window_chain_sha256']);
    expect(first.manifest['window_chain_sha256'],
        matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(first.file.path, isNot(second.file.path));
    for (final result in <LabL1EvidenceBundleResult>[first, second]) {
      final zip = ZipDecoder().decodeBytes(await result.file.readAsBytes());
      final names = zip.files.map((entry) => entry.name).toList();
      expect(names.length, (result.manifest['batch_count'] as int) + 3);
      expect(names.any((name) => name.endsWith('.pdf')), isFalse);
      final embedded = jsonDecode(utf8.decode(zip.files
          .singleWhere((entry) => entry.name == 'manifest.json')
          .readBytes()!)) as Map<String, dynamic>;
      expect(embedded['window_chain_sha256'],
          result.manifest['window_chain_sha256']);
      for (final item in embedded['jsonl'] as List<dynamic>) {
        final entry = item as Map<String, dynamic>;
        final bytes = zip.files.singleWhere(
            (file) => file.name == entry['name']).readBytes()!;
        final digest = await cryptography.Sha256().hash(bytes);
        final hash = digest.bytes.map((b) =>
            b.toRadixString(16).padLeft(2, '0')).join();
        expect(hash, entry['sha256']);
      }
      expect(embedded['official_full_page_evidence'], 'HOLD');
      expect(embedded['global_not_win'], 'HOLD');
      expect(embedded['window_coverage'], 'PARTIAL_WINDOW_NOT_FULL_87000');
    }
    expect(await File('${lab.path}/l1-next-page.txt').readAsString(), '73\n');
    expect((await lab.list().where((f) => f.path.endsWith('.jsonl'))
        .length), 18);
  });

  test('twenty-five batches rotate two ZIP slots with linked third window',
      () async {
    await prepare(25);
    final second = await LabL1EvidenceBundle.create(
        lab: lab, labHead: head, windowIndex: 2);
    final third = await LabL1EvidenceBundle.create(
        lab: lab, labHead: head, windowIndex: 3);
    expect(third.manifest['batch_count'], 1);
    expect(third.manifest['window_first_page'], 97);
    expect(third.manifest['window_last_page'], 100);
    expect(third.manifest['previous_window_chain_sha256'],
        second.manifest['window_chain_sha256']);
    expect(third.manifest['export_slot'], 1);
    expect(third.file.path, endsWith('window-0001.zip'));
    expect(second.file.path, endsWith('window-0002.zip'));
  });

  test('window two refuses a missing earlier batch', () async {
    await prepare(18);
    await File('${lab.path}/l1-pages-5-123456.jsonl').delete();
    await expectLater(
      LabL1EvidenceBundle.create(lab: lab, labHead: head, windowIndex: 2),
      throwsStateError,
    );
    expect(await File('${lab.path}/l1-evidence-share-window-0002.zip')
        .exists(), isFalse);
  });

  test('window refuses duplicate, symlink, torn and pending native data',
      () async {
    await prepare(18);
    await batch(1, id: '123457');
    await expectLater(
      LabL1EvidenceBundle.create(lab: lab, labHead: head, windowIndex: 2),
      throwsStateError);
    await File('${lab.path}/l1-pages-1-123457.jsonl').delete();
    final first = File('${lab.path}/l1-pages-1-123456.jsonl');
    final outside = File('${root.path}/outside.jsonl');
    await first.rename(outside.path);
    await Link(first.path).create(outside.path);
    await expectLater(
      LabL1EvidenceBundle.create(lab: lab, labHead: head, windowIndex: 2),
      throwsStateError);
    await Link(first.path).delete();
    await outside.rename(first.path);
    await File('${lab.path}/l1-pages-73-123456.jsonl.part')
        .writeAsString('torn');
    await expectLater(
      LabL1EvidenceBundle.create(lab: lab, labHead: head, windowIndex: 2),
      throwsStateError);
    await File('${lab.path}/l1-pages-73-123456.jsonl.part').delete();
    await File('${lab.path}/l1-native-inflight.json')
        .writeAsString('pending');
    await expectLater(
      LabL1EvidenceBundle.create(lab: lab, labHead: head, windowIndex: 2),
      throwsStateError);
  });

  test('window source mutation cleans partial ZIP, keeps cursor and JSONL',
      () async {
    await prepare(18);
    final first = File('${lab.path}/l1-pages-1-123456.jsonl');
    await expectLater(
      LabL1EvidenceBundle.create(
        lab: lab, labHead: head, windowIndex: 2,
        afterArchiveWriteForTesting: () async {
          await first.writeAsString('changed');
        },
      ), throwsStateError);
    expect(await File('${lab.path}/l1-evidence-share-window-0002.zip.part')
        .exists(), isFalse);
    expect(await File('${lab.path}/l1-evidence-share-window-0002.zip')
        .exists(), isFalse);
    expect(await File('${lab.path}/l1-next-page.txt').readAsString(), '73\n');
  });

  test('window cursor drift after ZIP creation is rejected and cleaned',
      () async {
    await prepare(18);
    await expectLater(
      LabL1EvidenceBundle.create(
        lab: lab, labHead: head, windowIndex: 2,
        afterArchiveWriteForTesting: () async {
          await File('${lab.path}/l1-next-page.txt').writeAsString('77\n');
        },
      ), throwsStateError);
    expect(await File('${lab.path}/l1-evidence-share-window-0002.zip.part')
        .exists(), isFalse);
    expect(await File('${lab.path}/l1-evidence-share-window-0002.zip')
        .exists(), isFalse);
  });

  testWidgets('unwritable Lab log cannot suppress share failure feedback',
      (tester) async {
    PackageInfo.setMockInitialValues(
      appName: 'Lab', packageName: 'com.easonliu.cloud500diag',
      version: '0.4.37', buildNumber: '900037', buildSignature: '',
    );
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => root.path);
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance
        .defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
    await tester.pumpWidget(const Cloud500DiagnosticApp());
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('就緒'), findsOneWidget);

    // Simulate storage failure after initialization; no real user data.
    final log = File('${lab.path}/issue13_cloud500_diag.log');
    await log.delete();
    await Directory(log.path).create();

    final button = find.text('分包分享 JSONL＋SHA Manifest＋Debug Log');
    await tester.scrollUntilVisible(
      button, 220.0, scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    await tester.tap(button);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.textContaining('分包匯出失敗'), findsWidgets);
    expect(find.textContaining('LAB_LOG_WRITE_FAILED'), findsWidgets);
  });

  testWidgets('scrolled share action shows immediate visible failure',
      (tester) async {
    PackageInfo.setMockInitialValues(
      appName: 'Lab', packageName: 'com.easonliu.cloud500diag',
      version: '0.4.37', buildNumber: '900037', buildSignature: '',
    );
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => root.path);
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance
        .defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
    await tester.pumpWidget(const Cloud500DiagnosticApp());
    await tester.pump(const Duration(milliseconds: 300));
    final button = find.text('分包分享 JSONL＋SHA Manifest＋Debug Log');
    // ListView builds off-screen actions lazily: ensureVisible requires an
    // already-mounted element and fails before the share action is built.
    await tester.scrollUntilVisible(
      button, 220.0, scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    await tester.tap(button);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.textContaining('分包匯出失敗'), findsWidgets);
  });
}
