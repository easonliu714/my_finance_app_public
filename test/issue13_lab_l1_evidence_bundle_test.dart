import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:cryptography/cryptography.dart' as cryptography;
import 'package:flutter_test/flutter_test.dart';
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
}
