import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/traditional_invoice_ocr_review.dart';

void main() {
  test('complete local recognition creates editable review-only candidate', () async {
    final coordinator = TraditionalInvoiceOcrCoordinator(
      recognizer: _FakeRecognizer(
        TraditionalInvoiceOcrRecognition(
          invoiceNumber: ' AB12345678 ',
          sellerTaxId: '12345675',
          sellerTaxIdSource: 'explicit_label',
          invoiceDate: _invoiceDate,
          sellerName: ' 測試商店 ',
          totalAmount: 168,
          visibleLineItems: const <TraditionalInvoiceOcrLineItem>[
            TraditionalInvoiceOcrLineItem(
              name: '咖啡',
              amount: 68,
              confidence: TraditionalInvoiceOcrConfidence.high,
            ),
            TraditionalInvoiceOcrLineItem(
              name: '三明治',
              amount: 100,
              confidence: TraditionalInvoiceOcrConfidence.medium,
            ),
          ],
          confidence: const <TraditionalInvoiceOcrField,
              TraditionalInvoiceOcrConfidence>{
            TraditionalInvoiceOcrField.invoiceNumber:
                TraditionalInvoiceOcrConfidence.high,
            TraditionalInvoiceOcrField.sellerTaxId:
                TraditionalInvoiceOcrConfidence.high,
            TraditionalInvoiceOcrField.invoiceDate:
                TraditionalInvoiceOcrConfidence.high,
            TraditionalInvoiceOcrField.sellerName:
                TraditionalInvoiceOcrConfidence.medium,
            TraditionalInvoiceOcrField.totalAmount:
                TraditionalInvoiceOcrConfidence.high,
          },
        ),
      ),
    );

    final result = await coordinator.recognize('/tmp/invoice.jpg');
    final candidate = result.candidate;

    expect(result.status, TraditionalInvoiceOcrStatus.success);
    expect(candidate, isNotNull);
    expect(candidate?.invoiceNumber, 'AB12345678');
    expect(candidate?.sellerTaxId, '12345675');
    expect(candidate?.sellerTaxIdSource, 'explicit_label');
    expect(candidate?.sellerName, '測試商店');
    expect(candidate?.visibleLineItems, hasLength(2));
    expect(candidate?.requiresUserReview, isTrue);
    expect(candidate?.usedNetwork, isFalse);
    expect(candidate?.canCreateFormalRecord, isFalse);

    final edited = candidate?.copyWith(
      sellerName: '人工修正商店',
      totalAmount: 170,
    );
    expect(edited?.sellerName, '人工修正商店');
    expect(edited?.totalAmount, 170);
    expect(edited?.canCreateFormalRecord, isFalse);
  });

  test('partial recognition keeps unreadable fields blank', () async {
    const coordinator = TraditionalInvoiceOcrCoordinator(
      recognizer: _FakeRecognizer(
        TraditionalInvoiceOcrRecognition(
          sellerName: '只看得到商家',
          fieldWarnings: <TraditionalInvoiceOcrField, List<String>>{
            TraditionalInvoiceOcrField.invoiceNumber: <String>[
              '號碼模糊，請人工輸入。',
            ],
          },
        ),
      ),
    );

    final result = await coordinator.recognize('/tmp/partial.jpg');
    final candidate = result.candidate;

    expect(result.status, TraditionalInvoiceOcrStatus.partial);
    expect(candidate?.invoiceNumber, isEmpty);
    expect(candidate?.invoiceDate, isNull);
    expect(candidate?.totalAmount, isNull);
    expect(candidate?.sellerName, '只看得到商家');
    expect(
      candidate?.fieldWarnings[TraditionalInvoiceOcrField.invoiceNumber],
      contains('號碼模糊，請人工輸入。'),
    );
    expect(result.message, contains('保持空白'));
  });

  test('invalid amounts are blanked and warned instead of guessed', () async {
    const coordinator = TraditionalInvoiceOcrCoordinator(
      recognizer: _FakeRecognizer(
        TraditionalInvoiceOcrRecognition(
          invoiceNumber: 'AB12345678',
          totalAmount: -1,
          visibleLineItems: <TraditionalInvoiceOcrLineItem>[
            TraditionalInvoiceOcrLineItem(name: '可見品項', amount: -5),
            TraditionalInvoiceOcrLineItem(name: '  '),
          ],
        ),
      ),
    );

    final result = await coordinator.recognize('/tmp/invalid-amount.jpg');
    final candidate = result.candidate;

    expect(result.status, TraditionalInvoiceOcrStatus.partial);
    expect(candidate?.totalAmount, isNull);
    expect(
      candidate?.fieldWarnings[TraditionalInvoiceOcrField.totalAmount],
      contains('辨識金額無效，已保持空白。'),
    );
    expect(candidate?.visibleLineItems, hasLength(1));
    expect(candidate?.visibleLineItems.single.amount, isNull);
    expect(
      candidate?.visibleLineItems.single.warnings,
      contains('品項金額無效，已保持空白。'),
    );
  });

  test('empty recognition returns failure without candidate', () async {
    const coordinator = TraditionalInvoiceOcrCoordinator(
      recognizer: _FakeRecognizer(TraditionalInvoiceOcrRecognition()),
    );

    final result = await coordinator.recognize('/tmp/empty.jpg');

    expect(result.status, TraditionalInvoiceOcrStatus.failed);
    expect(result.candidate, isNull);
    expect(result.hasReviewCandidate, isFalse);
    expect(result.usedNetwork, isFalse);
    expect(result.canCreateFormalRecord, isFalse);
  });

  test('recognizer exception fails closed without leaking private text', () async {
    const coordinator = TraditionalInvoiceOcrCoordinator(
      recognizer: _ThrowingRecognizer(),
    );

    final result = await coordinator.recognize('/tmp/private.jpg');

    expect(result.status, TraditionalInvoiceOcrStatus.failed);
    expect(result.candidate, isNull);
    expect(result.message, isNot(contains('private-ocr-payload')));
    expect(result.canCreateFormalRecord, isFalse);
  });

  test('blank image reference is rejected before recognizer call', () async {
    final recognizer = _CountingRecognizer();
    final coordinator = TraditionalInvoiceOcrCoordinator(
      recognizer: recognizer,
    );

    final result = await coordinator.recognize('   ');

    expect(result.status, TraditionalInvoiceOcrStatus.invalidInput);
    expect(recognizer.callCount, 0);
    expect(result.candidate, isNull);
  });

  test('safe summary exposes presence only, not recognized values', () async {
    final coordinator = TraditionalInvoiceOcrCoordinator(
      recognizer: _FakeRecognizer(
        TraditionalInvoiceOcrRecognition(
          invoiceNumber: 'AB12345678',
          invoiceDate: _invoiceDate,
          sellerName: '私密商家名稱',
          totalAmount: 999,
        ),
      ),
    );

    final result = await coordinator.recognize('/tmp/safe.jpg');
    final safeText = result.candidate?.toSafeSummary().toString() ?? '';

    expect(safeText, isNot(contains('AB12345678')));
    expect(safeText, isNot(contains('私密商家名稱')));
    expect(safeText, isNot(contains('999')));
    expect(safeText, contains('hasInvoiceNumber: true'));
    expect(safeText, contains('canCreateFormalRecord: false'));
  });
}

final DateTime _invoiceDate = DateTime.utc(2026, 7, 5);

class _FakeRecognizer implements LocalTraditionalInvoiceRecognizer {
  const _FakeRecognizer(this.result);

  final TraditionalInvoiceOcrRecognition result;

  @override
  Future<TraditionalInvoiceOcrRecognition> recognizeLocalImage(
    String localReference,
  ) async {
    return result;
  }
}

class _ThrowingRecognizer implements LocalTraditionalInvoiceRecognizer {
  const _ThrowingRecognizer();

  @override
  Future<TraditionalInvoiceOcrRecognition> recognizeLocalImage(
    String localReference,
  ) async {
    throw StateError('private-ocr-payload');
  }
}

class _CountingRecognizer implements LocalTraditionalInvoiceRecognizer {
  int callCount = 0;

  @override
  Future<TraditionalInvoiceOcrRecognition> recognizeLocalImage(
    String localReference,
  ) async {
    callCount += 1;
    return const TraditionalInvoiceOcrRecognition();
  }
}
