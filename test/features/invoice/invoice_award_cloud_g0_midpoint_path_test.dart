// C500-G0r: synthetic ordinal-to-leaf contracts, NOT official PDF evidence.
import 'package:flutter_test/flutter_test.dart';
import '../../../tool/c500_g0_bounded_xref.dart';

void main() {
  const auditor = C500G0MidpointPageAuditor();
  Map<int, String> valid() => <int, String>{
    11: '<< /Type /Pages /Parent 10 0 R /Count 2 /Kids [21 0 R 22 0 R] >>',
    12: '<< /Type /Pages /Parent 10 0 R /Count 2 /Kids [23 0 R 24 0 R] >>',
    21: '<< /Type /Page /Parent 11 0 R >>',
    22: '<< /Type /Page /Parent 11 0 R >>',
    23: '<< /Type /Page /Parent 12 0 R >>',
    24: '<< /Type /Page /Parent 12 0 R >>',
  };
  Future<Map<String, Object?>> run(Map<int, String> objects, {
    String root = '<< /Type /Pages /Count 4 /Kids [11 0 R 12 0 R] >>',
    int declared = 4,
    int? targetPageIndex,
  }) => auditor.inspect(
    pagesBody: root, rootId: 10, rootGeneration: 0,
    declaredPages: declared, targetPageIndex: targetPageIndex,
    readObject: (id, generation) async {
      if (generation != 0 || !objects.containsKey(id)) {
        throw const C500G0BoundedXrefException('C500_G0R_XREF_UNAVAILABLE');
      }
      return objects[id]!;
    },
  );
  Matcher failure(String code) => isA<C500G0BoundedXrefException>()
      .having((e) => e.code, 'code', code);
  test('midpoint 2 reaches third leaf, both sibling sums', () async {
    final result = await run(valid());
    expect(result['midpoint_page_index'], 2);
    expect(result['midpoint_leaf_id'], 23);
    expect(result['midpoint_path_depth'], 2);
    expect(result['midpoint_path_objects_read'], 4);
    expect(result['all_pages'], 'NOT_VERIFIED');
    expect(result['global_not_win'], 'NOT_PROVEN');
  });
  test('forged parent rejected', () async {
    final o = valid();
    o[12] = o[12]!.replaceFirst('/Parent 10 0 R', '/Parent 9 0 R');
    await expectLater(run(o), throwsA(failure('C500_G0R_PARENT_MISMATCH')));
  });
  test('forged count rejected', () async {
    final o = valid();
    o[12] = o[12]!.replaceFirst('/Count 2', '/Count 3');
    await expectLater(run(o), throwsA(failure('C500_G0R_COUNT_OVERFLOW')));
  });
  test('sibling alias rejected', () async {
    await expectLater(run(valid(), root:
        '<< /Type /Pages /Count 4 /Kids [11 0 R 11 0 R] >>'),
        throwsA(failure('C500_G0R_BUDGET_ALIAS_OR_CYCLE')));
  });
  test('missing leaf fails closed', () async {
    final o = valid()..remove(23);
    await expectLater(run(o), throwsA(failure('C500_G0R_XREF_UNAVAILABLE')));
  });
  test('forged leaf count rejected', () async {
    final o = valid();
    o[23] = '<< /Type /Page /Parent 12 0 R /Count 1 >>';
    await expectLater(run(o), throwsA(failure('C500_G0R_CHILD_COUNT_INVALID')));
  });
  test('duplicate Kids rejected', () async {
    await expectLater(run(valid(), root: '<< /Type /Pages /Count 4 '
        '/Kids [11 0 R 12 0 R] /Kids [11 0 R 12 0 R] >>'),
        throwsA(failure('C500_G0R_KIDS_AMBIGUOUS')));
  });
  test('wrong root declared count rejected', () async {
    await expectLater(run(valid(), declared: 5),
        throwsA(failure('C500_G0R_PARENT_COUNT_MISMATCH')));
  });
  test('cycle to root rejected', () async {
    await expectLater(run(valid(), root:
        '<< /Type /Pages /Count 4 /Kids [10 0 R 12 0 R] >>'),
        throwsA(failure('C500_G0R_BUDGET_ALIAS_OR_CYCLE')));
  });
  // G0s synthetic tests: exact ordinal custody, not official source evidence.
  test('G0s first and last leaf distinct and bounded', () async {
    final a = await run(valid(), targetPageIndex: 0);
    final b = await run(valid(), targetPageIndex: 3);
    expect(a['sampled_leaf_id'], 21);
    expect(b['sampled_leaf_id'], 24);
    expect(a['sampled_page_index'], 0);
    expect(b['sampled_page_index'], 3);
    expect(b['global_not_win'], 'NOT_PROVEN');
  });
  test('G0s out of range ordinals fail closed', () async {
    await expectLater(run(valid(), targetPageIndex: -1),
        throwsA(failure('C500_G0S_TARGET_OUT_OF_RANGE')));
    await expectLater(run(valid(), targetPageIndex: 4),
        throwsA(failure('C500_G0S_TARGET_OUT_OF_RANGE')));
  });
  Future<Map<String, Object?>> spread(Map<int, String> objects, {
    int declared = 4,
  }) => const C500G0SpreadPageAuditor().inspect(
    pagesBody: '<< /Type /Pages /Count 4 /Kids [11 0 R 12 0 R] >>',
    rootId: 10, rootGeneration: 0, declaredPages: declared,
    readObject: (id, generation) async {
      if (generation != 0 || !objects.containsKey(id)) {
        throw const C500G0BoundedXrefException('C500_G0R_XREF_UNAVAILABLE');
      }
      return objects[id]!;
    },
  );
  test('G0s three independent distant paths', () async {
    final e = await spread(valid());
    expect(e['spread_page_indices'], <int>[0, 2, 3]);
    expect(e['spread_leaf_ids'], <int>[21, 23, 24]);
    expect(e['spread_path_objects_read_total'], 12);
    expect(e['spread_paths_verified'], 3);
    expect(e['all_pages'], 'NOT_VERIFIED');
  });
  test('G0s missing last leaf fails entire audit', () async {
    await expectLater(spread(valid()..remove(24)),
        throwsA(failure('C500_G0R_XREF_UNAVAILABLE')));
  });
  test('G0s forged last parent fails entire audit', () async {
    final o = valid();
    o[24] = o[24]!.replaceFirst('/Parent 12 0 R', '/Parent 11 0 R');
    await expectLater(spread(o),
        throwsA(failure('C500_G0R_PARENT_MISMATCH')));
  });
  test('G0s fewer than three pages fails closed', () async {
    await expectLater(spread(valid(), declared: 2),
        throwsA(failure('C500_G0S_COUNT_LIMIT')));
  });

}
