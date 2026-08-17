import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/google_mlkit_traditional_invoice_recognizer.dart';
import 'package:my_finance_app/features/invoice/traditional_invoice_ocr_review.dart';

void main() {
  const parser = TraditionalInvoiceTextParser();

  test('parses invoice number, seller identity, ROC date, merchant and semantic total', () {
    final result = parser.parse(
      const LocalOcrTextDocument(
        fullText: '''
測試商店股份有限公司
電子發票證明聯
AB-12345678
統編 12345675
115年07月06日
小計 100
總計 NT\$ 120
''',
        lines: <String>[
          '測試商店股份有限公司',
          '電子發票證明聯',
          'AB-12345678',
          '統編 12345675',
          '115年07月06日',
          '小計 100',
          '總計 NT\$ 120',
        ],
      ),
    );

    expect(result.invoiceNumber, 'AB12345678');
    expect(result.sellerTaxId, '12345675');
    expect(result.sellerTaxIdSource, 'explicit_label');
    expect(result.invoiceDate, DateTime.utc(2026, 7, 6));
    expect(result.sellerName, '測試商店股份有限公司');
    expect(result.totalAmount, 120);
    expect(
      result.confidence[TraditionalInvoiceOcrField.invoiceNumber],
      TraditionalInvoiceOcrConfidence.high,
    );
    expect(
      result.confidence[TraditionalInvoiceOcrField.sellerTaxId],
      TraditionalInvoiceOcrConfidence.high,
    );
    expect(result.fieldWarnings, isEmpty);
  });

  test('invoice period is never treated as a ROC transaction date', () {
    final result = parser.parse(
      const LocalOcrTextDocument(
        fullText: '''
中華民國115年 5-6月份
收銀機統一發票
AA90000002
一品現泡茶店
''',
        lines: <String>[
          '中華民國115年 5-6月份',
          '收銀機統一發票',
          'AA90000002',
          '一品現泡茶店',
        ],
      ),
    );
    expect(result.invoiceNumber, 'AA90000002');
    expect(result.invoiceDate, isNull);
    expect(result.sellerName, '一品現泡茶店');
  });

  // P4.18.1: a checksum-valid contextual NO. value remains useful Live
  // evidence, but one frozen OCR frame is not authoritative seller identity.
  test('contextual NO tax ID stays non-authoritative in frozen OCR', () {
    final result = parser.parse(
      const LocalOcrTextDocument(
        fullText: '''
中華民國115年 5-6月份
收銀機統一發票
AA90000002
一品現泡茶店
NO.30340553
2026/06/19 11:35:00
小 計:110元
收 現:110元
''',
        lines: <String>[
          '中華民國115年 5-6月份',
          '收銀機統一發票',
          'AA90000002',
          '一品現泡茶店',
          'NO.30340553',
          '2026/06/19 11:35:00',
          '小 計:110元',
          '收 現:110元',
        ],
      ),
    );
    expect(result.sellerTaxId, isNull);
    expect(result.sellerTaxIdSource, isEmpty);
    expect(result.rawText, contains('NO.30340553'));
    expect(result.invoiceDate, DateTime.utc(2026, 6, 19));
    expect(result.sellerName, '一品現泡茶店');
    expect(result.totalAmount, 110);
  });

  test('OCR-misread contextual NO fails checksum and does not become seller identity', () {
    final evidence = extractTraditionalSellerTaxIdEvidence(const <String>[
      'AA90000001',
      '一品現泡茶店',
      'NO.30348553',
    ]);
    expect(evidence, isNull);
  });

  test('faded receipt corrections reject short serial and recover split amount', () {
    final result = parser.parse(
      const LocalOcrTextDocument(
        fullText: '''
中華民國115年 5-6月份
收銀機統一發票
AA90000002
一品現泡茶店
NO.383423
新北市土城區區光明街11號
電話:8262-9222
2O26/O6/19 11:35:O8
飲料X1
\$ 110
小
計:110元
收
現:110元
''',
        lines: <String>[
          '中華民國115年 5-6月份',
          '收銀機統一發票',
          'AA90000002',
          '一品現泡茶店',
          'NO.383423',
          '新北市土城區區光明街11號',
          '電話:8262-9222',
          '2O26/O6/19 11:35:O8',
          '飲料X1',
          '\$ 110',
          '小',
          '計:110元',
          '收',
          '現:110元',
        ],
      ),
    );
    expect(result.invoiceNumber, 'AA90000002');
    expect(result.invoiceDate, DateTime.utc(2026, 6, 19));
    expect(result.sellerName, '一品現泡茶店');
    expect(result.sellerTaxId, isNull);
    expect(result.totalAmount, 110);
    expect(result.rawText, contains('NO.383423'));
  });

  test('period year evidence repairs 2826/84/18 to 2026-04-18', () {
    final result = parser.parse(
      const LocalOcrTextDocument(
        fullText: '''
中華民國115年 3-4月份
XY90000021
2826/84/18 14:59:52
''',
        lines: <String>[
          '中華民國115年 3-4月份',
          'XY90000021',
          '2826/84/18 14:59:52',
        ],
      ),
    );
    expect(result.invoiceDate, DateTime.utc(2026, 4, 18));
  });

  test('single-digit year noise 2926 is repaired from independent period year', () {
    final result = parser.parse(
      const LocalOcrTextDocument(
        fullText: '''
中華民國115年 3-4月份
XY90000021
2926/84/18 14:59:52
''',
        lines: <String>[
          '中華民國115年 3-4月份',
          'XY90000021',
          '2926/84/18 14:59:52',
        ],
      ),
    );
    expect(result.invoiceDate, DateTime.utc(2026, 4, 18));
  });

  test('period year evidence repairs 2826/83/16 to 2026-03-16', () {
    final result = parser.parse(
      const LocalOcrTextDocument(
        fullText: '''
中華民國115年 3-4月份
XY90000020
2826/83/16 2:25:86
''',
        lines: <String>[
          '中華民國115年 3-4月份',
          'XY90000020',
          '2826/83/16 2:25:86',
        ],
      ),
    );
    expect(result.invoiceDate, DateTime.utc(2026, 3, 16));
  });

  test('period year evidence preserves an exact calendar-valid month', () {
    final result = parser.parse(
      const LocalOcrTextDocument(
        fullText: '''
中華民國115年 5-6月份
AA90000001
2826/05/23 12:96:35
''',
        lines: <String>[
          '中華民國115年 5-6月份',
          'AA90000001',
          '2826/05/23 12:96:35',
        ],
      ),
    );
    expect(result.invoiceDate, DateTime.utc(2026, 5, 23));
  });

  test('invoice period months never hard-reject an adjacent valid transaction month', () {
    final result = parser.parse(
      const LocalOcrTextDocument(
        fullText: '''
中華民國115年 5-6月份
AB12345678
2826/04/30 23:59:59
''',
        lines: <String>[
          '中華民國115年 5-6月份',
          'AB12345678',
          '2826/04/30 23:59:59',
        ],
      ),
    );
    expect(result.invoiceDate, DateTime.utc(2026, 4, 30));
  });

  test('fuzzy month recovery is calendar-bounded rather than period-bounded', () {
    final result = parser.parse(
      const LocalOcrTextDocument(
        fullText: '''
中華民國115年 3-4月份
AB12345678
2826/85/18 14:59:52
''',
        lines: <String>[
          '中華民國115年 3-4月份',
          'AB12345678',
          '2826/85/18 14:59:52',
        ],
      ),
    );
    expect(result.invoiceDate, DateTime.utc(2026, 5, 18));
  });

  test('B8 month and impossible 81 day repair only through unique 8-to-0 edits', () {
    final result = parser.parse(
      const LocalOcrTextDocument(
        fullText: '''
中華民國115年 7-8月份
CD90000017
2826/B8/81 12:28:21
''',
        lines: <String>[
          '中華民國115年 7-8月份',
          'CD90000017',
          '2826/B8/81 12:28:21',
        ],
      ),
    );
    expect(result.invoiceDate, DateTime.utc(2026, 8, 1));
  });

  test('calendar validity rejects April 31 even when OCR repair is otherwise bounded', () {
    final result = parser.parse(
      const LocalOcrTextDocument(
        fullText: '''
中華民國115年 5-6月份
AB12345678
2826/04/31 12:00:00
''',
        lines: <String>[
          '中華民國115年 5-6月份',
          'AB12345678',
          '2826/04/31 12:00:00',
        ],
      ),
    );
    expect(result.invoiceDate, isNull);
  });

  test('calendar validity rejects February 29 in non-leap year 2026', () {
    final result = parser.parse(
      const LocalOcrTextDocument(
        fullText: '''
中華民國115年 1-2月份
AB12345678
2826/02/29 12:00:00
''',
        lines: <String>[
          '中華民國115年 1-2月份',
          'AB12345678',
          '2826/02/29 12:00:00',
        ],
      ),
    );
    expect(result.invoiceDate, isNull);
  });

  test('impossible day tens are not arbitrarily mapped into 01-31', () {
    final result = parser.parse(
      const LocalOcrTextDocument(
        fullText: '''
中華民國115年 3-4月份
AB12345678
2826/04/91 12:00:00
''',
        lines: <String>[
          '中華民國115年 3-4月份',
          'AB12345678',
          '2826/04/91 12:00:00',
        ],
      ),
    );
    expect(result.invoiceDate, isNull);
  });

  test('corrupted date is not repaired without invoice-period year evidence', () {
    final result = parser.parse(
      const LocalOcrTextDocument(
        fullText: 'XY90000021\n2926/84/18 14:59:52',
        lines: <String>['XY90000021', '2926/84/18 14:59:52'],
      ),
    );
    expect(result.invoiceDate, isNull);
  });

  test('explicit 現 colon amount is a bounded fallback for traditional receipts', () {
    final result = parser.parse(
      const LocalOcrTextDocument(
        fullText: 'AA90000001\n現: 110元',
        lines: <String>['AA90000001', '現: 110元'],
      ),
    );
    expect(result.totalAmount, 110);
  });

  test('unlabelled colon amount is never promoted to a total', () {
    final result = parser.parse(
      const LocalOcrTextDocument(
        fullText: 'XY90000020\n:120元',
        lines: <String>['XY90000020', ':120元'],
      ),
    );
    expect(result.totalAmount, isNull);
  });

  test('does not pair unrelated numeric line with a split total keyword', () {
    final result = parser.parse(
      const LocalOcrTextDocument(
        fullText: '''AB12345678
測試早餐店
小
電話:8262-9222''',
        lines: <String>['AB12345678', '測試早餐店', '小', '電話:8262-9222'],
      ),
    );
    expect(result.totalAmount, isNull);
  });

  test('adapter keeps seller identity and network disabled', () async {
    const recognizer = GoogleMlKitTraditionalInvoiceRecognizer(
      engine: _FakeTextEngine(),
    );
    const coordinator = TraditionalInvoiceOcrCoordinator(recognizer: recognizer);
    final result = await coordinator.recognize('/tmp/invoice.jpg');
    expect(result.status, TraditionalInvoiceOcrStatus.success);
    expect(result.usedNetwork, isFalse);
    expect(result.canCreateFormalRecord, isFalse);
    expect(result.candidate?.invoiceNumber, 'CD87654321');
    expect(result.candidate?.sellerTaxId, '12345675');
    expect(result.candidate?.totalAmount, 88);
    expect(result.candidate?.rawText, contains('測試早餐店'));
  });

  test('missing core fields remain partial with explicit warnings', () async {
    const recognizer = GoogleMlKitTraditionalInvoiceRecognizer(
      engine: _SparseTextEngine(),
    );
    const coordinator = TraditionalInvoiceOcrCoordinator(recognizer: recognizer);
    final result = await coordinator.recognize('/tmp/sparse.jpg');
    expect(result.status, TraditionalInvoiceOcrStatus.partial);
    expect(result.candidate, isNotNull);
    expect(result.candidate?.sellerTaxId, isEmpty);
    expect(result.candidate?.fieldWarnings, isNotEmpty);
  });
}

class _FakeTextEngine implements LocalOcrTextEngine {
  const _FakeTextEngine();
  @override
  Future<LocalOcrTextDocument> recognize(String localReference) async {
    return const LocalOcrTextDocument(
      fullText: '''
測試早餐店
CD87654321
統編 12345675
2026/07/06
總計 88
''',
      lines: <String>[
        '測試早餐店',
        'CD87654321',
        '統編 12345675',
        '2026/07/06',
        '總計 88',
      ],
    );
  }
}

class _SparseTextEngine implements LocalOcrTextEngine {
  const _SparseTextEngine();
  @override
  Future<LocalOcrTextDocument> recognize(String localReference) async {
    return const LocalOcrTextDocument(
      fullText: '測試商店',
      lines: <String>['測試商店'],
    );
  }
}