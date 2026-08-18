import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/google_mlkit_traditional_invoice_recognizer.dart';
import 'package:my_finance_app/features/invoice/invoice_field_first_evidence.dart';
import 'package:my_finance_app/features/invoice/invoice_total_evidence.dart';
import 'package:my_finance_app/features/invoice/traditional_invoice_multi_variant_recognizer.dart';
import 'package:my_finance_app/features/invoice/traditional_invoice_ocr_review.dart';

void main() {
  test('two enhanced variants may fill missing review-only fields', () async {
    final provider = _FakeVariantProvider();
    final recognizer = GoogleMlKitMultiVariantTraditionalInvoiceRecognizer(
      engine: _MapTextEngine(<String, LocalOcrTextDocument>{
        '/original.jpg': _doc(<String>[
          '收銀機統一發票',
          'XY17859005',
        ]),
        '/contrast.png': _doc(<String>[
          '中華民國115年3-4月份',
          '收銀機統一發票',
          'XY17859005',
          '一品現泡茶店',
          '2026/04/18 14:59:52',
          '總計 95',
        ]),
        '/gray.png': _doc(<String>[
          '中華民國115年3-4月份',
          '收銀機統一發票',
          'XY17859005',
          '一品現泡茶店',
          '2026/04/18 14:59:52',
          '總計 95',
        ]),
        '/high.png': _doc(<String>[
          '中華民國115年3-4月份',
          '收銀機統一發票',
          'XY17859005',
          '一品現泡菜店',
          '2026/04/18 14:59:52',
          '總計 98',
        ]),
      }),
      variantProvider: provider,
    );

    final result = await recognizer.recognizeLocalImage('/original.jpg');

    expect(result.invoiceNumber, 'XY17859005');
    expect(result.invoiceDate, DateTime.utc(2026, 4, 18));
    expect(result.sellerName, '一品現泡茶店');
    expect(result.totalAmount, 95);
    expect(result.sellerTaxId, isNull);
    expect(
      parseInvoiceFieldFirstEvidence(result.rawLines).invoicePeriod,
      '115年3-4月份',
    );
    expect(result.rawLines, contains('P4_18_5_EXACT_TIME=14:59:52'));
    expect(
      result.rawLines,
      contains('P4_18_5_INVOICE_PERIOD=115年3-4月份'),
    );
    expect(
      result.fieldWarnings[TraditionalInvoiceOcrField.totalAmount]?.join(' '),
      contains('P4.18.6_MULTI_VARIANT_TOTAL_CONSENSUS'),
    );
    expect(provider.cleanedUp, isTrue);
  });

  test('original total conflict with enhanced consensus fails closed', () async {
    final provider = _FakeVariantProvider();
    final recognizer = GoogleMlKitMultiVariantTraditionalInvoiceRecognizer(
      engine: _MapTextEngine(<String, LocalOcrTextDocument>{
        '/original.jpg': _doc(<String>[
          'AA18231313',
          '一品現泡城店',
          '2026/05/23',
          '總計 118',
        ]),
        '/contrast.png': _doc(<String>[
          'AA18231313',
          '一品現泡茶店',
          '2026/05/23',
          '總計 110',
        ]),
        '/gray.png': _doc(<String>[
          'AA18231313',
          '一品現泡茶店',
          '2026/05/23',
          '總計 110',
        ]),
        '/high.png': _doc(<String>[
          'AA18231313',
          '一品現泡茶店',
          '2026/05/23',
          '總計 110',
        ]),
      }),
      variantProvider: provider,
    );

    final result = await recognizer.recognizeLocalImage('/original.jpg');

    expect(result.invoiceNumber, 'AA18231313');
    expect(result.sellerName, '一品現泡茶店');
    expect(result.totalAmount, isNull);
    expect(
      result.rawLines,
      contains('P4_18_5_TOTAL_DECISION_LOCK=CONFLICT'),
    );
    expect(resolveInvoiceTotalEvidence(result.rawLines), isNull);
    expect(
      result.fieldWarnings[TraditionalInvoiceOcrField.totalAmount]?.join(' '),
      contains('P4.18.6_MULTI_VARIANT_TOTAL_CONFLICT'),
    );
    expect(provider.cleanedUp, isTrue);
  });

  test('checksum-valid NO values never gain frozen authority from variants', () async {
    final provider = _FakeVariantProvider();
    final recognizer = GoogleMlKitMultiVariantTraditionalInvoiceRecognizer(
      engine: _MapTextEngine(<String, LocalOcrTextDocument>{
        '/original.jpg': _doc(<String>[
          'AA18231313',
        ]),
        '/contrast.png': _doc(<String>[
          'AA18231313',
          '一品現泡茶店',
          'NO.12345675',
        ]),
        '/gray.png': _doc(<String>[
          'AA18231313',
          '一品現泡茶店',
          'NO.12345675',
        ]),
        '/high.png': _doc(<String>[
          'AA18231313',
          '一品現泡茶店',
          'NO.12345675',
        ]),
      }),
      variantProvider: provider,
    );

    final result = await recognizer.recognizeLocalImage('/original.jpg');

    expect(result.sellerTaxId, isNull);
    expect(result.sellerTaxIdSource, isEmpty);
    expect(provider.cleanedUp, isTrue);
  });

  test('explicit seller-tax label needs two enhanced exact votes', () async {
    final provider = _FakeVariantProvider();
    final recognizer = GoogleMlKitMultiVariantTraditionalInvoiceRecognizer(
      engine: _MapTextEngine(<String, LocalOcrTextDocument>{
        '/original.jpg': _doc(<String>[
          'AA18231313',
        ]),
        '/contrast.png': _doc(<String>[
          'AA18231313',
          '賣方統編 12345675',
        ]),
        '/gray.png': _doc(<String>[
          'AA18231313',
          '賣方統編 12345675',
        ]),
        '/high.png': _doc(<String>[
          'AA18231313',
        ]),
      }),
      variantProvider: provider,
    );

    final result = await recognizer.recognizeLocalImage('/original.jpg');

    expect(result.sellerTaxId, '12345675');
    expect(result.sellerTaxIdSource, 'multi_variant_explicit_label_consensus');
    expect(
      result.confidence[TraditionalInvoiceOcrField.sellerTaxId],
      TraditionalInvoiceOcrConfidence.medium,
    );
    expect(provider.cleanedUp, isTrue);
  });

  test('strong electronic semantic evidence skips traditional preprocessing', () async {
    final provider = _FakeVariantProvider();
    final recognizer = GoogleMlKitMultiVariantTraditionalInvoiceRecognizer(
      engine: _MapTextEngine(<String, LocalOcrTextDocument>{
        '/original.jpg': _doc(<String>[
          '電子發票證明聯',
          'AB12345678',
        ]),
      }),
      variantProvider: provider,
    );

    final result = await recognizer.recognizeLocalImage('/original.jpg');

    expect(result.invoiceNumber, 'AB12345678');
    expect(provider.createCalls, 0);
    expect(provider.cleanedUp, isFalse);
  });
}

LocalOcrTextDocument _doc(List<String> lines) => LocalOcrTextDocument(
      fullText: lines.join('\n'),
      lines: lines,
    );

class _MapTextEngine implements LocalOcrTextEngine {
  const _MapTextEngine(this.documents);

  final Map<String, LocalOcrTextDocument> documents;

  @override
  Future<LocalOcrTextDocument> recognize(String localReference) async {
    final document = documents[localReference];
    if (document == null) {
      throw StateError('No OCR fixture for $localReference');
    }
    return document;
  }
}

class _FakeVariantProvider implements TraditionalInvoiceImageVariantProvider {
  int createCalls = 0;
  bool cleanedUp = false;

  @override
  Future<List<TraditionalInvoiceImageVariant>> createEnhancedVariants(
    String originalReference,
  ) async {
    createCalls += 1;
    return const <TraditionalInvoiceImageVariant>[
      TraditionalInvoiceImageVariant(
        label: 'contrast_moderate',
        localReference: '/contrast.png',
      ),
      TraditionalInvoiceImageVariant(
        label: 'grayscale_contrast',
        localReference: '/gray.png',
      ),
      TraditionalInvoiceImageVariant(
        label: 'grayscale_high_contrast',
        localReference: '/high.png',
      ),
    ];
  }

  @override
  Future<void> cleanupVariants(
    List<TraditionalInvoiceImageVariant> variants,
  ) async {
    cleanedUp = true;
  }
}
