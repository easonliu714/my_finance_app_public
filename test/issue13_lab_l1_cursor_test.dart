import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/issue13_lab_l1_cursor.dart';

const sha = 'f50d0dcebc7497c51ce2eea9da9525232e638fdc4103decc6a8e0a1c1dac5571';
Map<String, Object> row(int n, int total, {String hash = sha}) => {
  'page': n, 'page_count': total, 'pdf_sha256': hash,
  'engine': 'android.graphics.pdf.PdfRenderer',
  'period': '115-07-08', 'tier': 'cloud-500',
  'text': 'AB${n.toString().padLeft(8, '0')}',
};

void main() {
  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('l1-cursor-'));
  tearDown(() async => dir.delete(recursive: true));
  Future<File> write(int first, List<Map<String, Object>> rows,
      {String id = '123456'}) async {
    final file = File('${dir.path}/l1-pages-$first-$id.jsonl');
    await file.writeAsString('${rows.map(jsonEncode).join('\n')}\n', flush: true);
    return file;
  }

  test('full native four-page batch', () async {
    final file = await write(1, [for (var i = 1; i <= 4; i++) row(i, 6)]);
    final batch = await LabL1Cursor.verify(dir, file, 1, sha,
        last: 4, count: 6);
    expect(batch.last, 4);
  });
  test('crash after native rename recovers final batch', () async {
    final file = await write(5, [row(5, 6), row(6, 6)]);
    final batch = await LabL1Cursor.recover(dir, 5, sha);
    expect(batch?.file.path, file.path);
    expect(batch?.last, 6);
    expect(await LabL1Cursor.recover(dir, 7, sha), isNull);
  });
  test('partial nonterminal batch holds', () async {
    final file = await write(1, [row(1, 6)]);
    await expectLater(LabL1Cursor.verify(dir, file, 1, sha),
        throwsStateError);
  });
  test('duplicate start holds instead of second export', () async {
    await write(1, [row(1, 1)]);
    await write(1, [row(1, 1)], id: '123457');
    await expectLater(LabL1Cursor.recover(dir, 1, sha), throwsStateError);
  });
  test('source SHA and page-count drift hold', () async {
    final file = await write(1, [row(1, 2, hash: 'a' * 64), row(2, 2)]);
    await expectLater(LabL1Cursor.verify(dir, file, 1, sha),
        throwsStateError);
    await file.writeAsString(
        '${jsonEncode(row(1, 2))}\n${jsonEncode(row(2, 3))}\n');
    await expectLater(LabL1Cursor.verify(dir, file, 1, sha),
        throwsStateError);
  });
  test('truncated and invalid UTF8 hold', () async {
    final file = await write(1, [row(1, 1)]);
    await file.writeAsString(jsonEncode(row(1, 1)));
    await expectLater(LabL1Cursor.verify(dir, file, 1, sha),
        throwsStateError);
    await file.writeAsBytes([0xff, 0x0a]);
    await expectLater(LabL1Cursor.verify(dir, file, 1, sha),
        throwsFormatException);
  });
  test('symlinked batch cannot be recovered', () async {
    final outside = await Directory.systemTemp.createTemp('l1-external-');
    addTearDown(() => outside.delete(recursive: true));
    final target = File('${outside.path}/batch.jsonl');
    await target.writeAsString('${jsonEncode(row(1, 1))}\n');
    await Link('${dir.path}/l1-pages-1-123456.jsonl').create(target.path);
    await expectLater(LabL1Cursor.recover(dir, 1, sha), throwsStateError);
  });
}
