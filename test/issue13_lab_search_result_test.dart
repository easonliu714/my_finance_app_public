import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/issue13_lab_search_result.dart';

const candidate = 'CR30912111';

Map<String, dynamic> snapshot({bool matched = false}) => <String, dynamic>{
  'status': 'complete',
  'candidate': candidate,
  'matched': matched,
  'matched_page': matched ? 123 : 0,
  'pages_read': 17,
  'page_count': 87000,
  'elapsed_ms': 6612,
};

Future<void> show(WidgetTester tester, LabSearchResult result) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: SingleChildScrollView(
      child: LabSearchResultCard(result: result),
    )),
  ));
}

void main() {
  testWidgets('matched candidate displays page, no posting authority',
      (tester) async {
    final result = LabSearchResult.fromProbe(
      candidate: candidate, probe: snapshot(matched: true),
    );
    expect(result.verdict, LabSearchVerdict.matched);
    await show(tester, result);
    expect(find.byKey(const ValueKey<String>('lab-search-result')), findsOneWidget);
    expect(find.textContaining('頁碼：123'), findsOneWidget);
    expect(find.textContaining('尚非正式中獎或過帳'), findsOneWidget);
    expect(find.textContaining('mode=DIAGNOSTIC_ONLY'), findsOneWidget);
    expect(find.textContaining('pages_read=17 / page_count=87000'), findsOneWidget);
    expect(find.textContaining('elapsed_ms=6612'), findsOneWidget);
  });

  testWidgets('nonmatch never claims formal NOT_WIN or other tier',
      (tester) async {
    final result = LabSearchResult.fromProbe(
      candidate: candidate, probe: snapshot(),
    );
    expect(result.verdict, LabSearchVerdict.notMatched);
    await show(tester, result);
    expect(find.textContaining('不能做正式未中獎判定'), findsOneWidget);
    expect(find.textContaining('不可推論其他獎別'), findsOneWidget);
  });

  testWidgets('invalid or mismatched candidate fails closed', (tester) async {
    for (final bad in <String>['CR123', 'AB12345678']) {
      final result = LabSearchResult.fromProbe(
        candidate: bad, probe: snapshot(),
      );
      expect(result.verdict, LabSearchVerdict.hold);
      await show(tester, result);
      expect(find.textContaining('HOLD：'), findsOneWidget);
    }
  });

  testWidgets('timeout or process exit is HOLD', (tester) async {
    for (final status in <String>['timeout', 'process_exit', 'failure', 'running']) {
      final result = LabSearchResult.fromProbe(
        candidate: candidate, probe: snapshot()..['status'] = status,
      );
      expect(result.verdict, LabSearchVerdict.hold);
      await show(tester, result);
      expect(find.textContaining('禁止任何正式判定'), findsOneWidget);
    }
  });

  testWidgets('other tier, wrong source and malformed native result HOLD',
      (tester) async {
    final bad = <Map<String, dynamic>>[
      snapshot()..['tier'] = 'cloud-1000',
      snapshot()..['period'] = '115-05-06',
      snapshot()..['pdf_sha256'] = '0' * 64,
      snapshot()..['matched'] = 'false',
      snapshot()..['matched_page'] = 1,
      snapshot()..['pages_read'] = 0,
      snapshot()..['page_count'] = 100,
    ];
    for (final probe in bad) {
      final result = LabSearchResult.fromProbe(
        candidate: candidate, probe: probe,
      );
      expect(result.verdict, LabSearchVerdict.hold);
      await show(tester, result);
      expect(find.textContaining('HOLD：'), findsOneWidget);
    }
  });
}
