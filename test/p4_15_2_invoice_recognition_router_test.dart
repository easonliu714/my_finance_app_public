import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/invoice_recognition_router.dart';

void main() {
  const router = InvoiceRecognitionRouter();
  const leftPayload =
      'AB123456781150609123400000064000000780000000024531234abcdefghijklmnopqrstuvwx';

  InvoiceRecognitionRoutingResult ambiguousResult() {
    return router.route(
      const <InvoiceRecognitionImageInput>[
        InvoiceRecognitionImageInput(
          localReference: '/tmp/mixed.jpg',
          fileName: 'mixed.jpg',
          payloads: <String>[
            leftPayload,
            '**detail-a',
            '**detail-b',
            'AB123',
          ],
        ),
      ],
    );
  }

  test('automatic route falls back to traditional OCR when no QR is found', () {
    final result = router.route(
      const <InvoiceRecognitionImageInput>[
        InvoiceRecognitionImageInput(
          localReference: '/tmp/invoice.jpg',
          fileName: 'invoice.jpg',
          payloads: <String>[],
        ),
      ],
    );

    expect(result.route, InvoiceRecognitionRoute.traditionalOcr);
    expect(result.shouldRunTraditionalOcr, isTrue);
    expect(result.usedNetwork, isFalse);
    expect(result.canCreateFormalRecord, isFalse);
  });

  test('one image containing left and right QR creates a complete pair', () {
    final result = router.route(
      const <InvoiceRecognitionImageInput>[
        InvoiceRecognitionImageInput(
          localReference: '/tmp/pair.jpg',
          fileName: 'pair.jpg',
          payloads: <String>[leftPayload, '**detail-payload'],
        ),
      ],
    );

    expect(result.route, InvoiceRecognitionRoute.electronicInvoiceQr);
    expect(result.pairs, hasLength(1));
    expect(result.pairs.single.isComplete, isTrue);
    expect(result.pairs.single.canCreateReviewCandidate, isTrue);
    expect(result.pairs.single.canCreateFormalRecord, isFalse);
    expect(result.hasReviewCandidate, isTrue);
  });

  test('left and right QR from separate images are paired when unique', () {
    final result = router.route(
      const <InvoiceRecognitionImageInput>[
        InvoiceRecognitionImageInput(
          localReference: '/tmp/left.jpg',
          fileName: 'left.jpg',
          payloads: <String>[leftPayload],
        ),
        InvoiceRecognitionImageInput(
          localReference: '/tmp/right.jpg',
          fileName: 'right.jpg',
          payloads: <String>['**detail-payload'],
        ),
      ],
    );

    expect(result.route, InvoiceRecognitionRoute.electronicInvoiceQr);
    expect(result.pairs.single.left.fileName, 'left.jpg');
    expect(result.pairs.single.right?.fileName, 'right.jpg');
  });

  test('left-only QR remains a limited review candidate with warning', () {
    final result = router.route(
      const <InvoiceRecognitionImageInput>[
        InvoiceRecognitionImageInput(
          localReference: '/tmp/left.jpg',
          fileName: 'left.jpg',
          payloads: <String>[leftPayload],
        ),
      ],
    );

    expect(result.route, InvoiceRecognitionRoute.electronicInvoiceQr);
    expect(result.pairs.single.isComplete, isFalse);
    expect(result.hasReviewCandidate, isTrue);
    expect(result.warnings, contains(contains('右側明細 QR')));
  });

  test('right-only QR requires a left code or manual designation', () {
    final result = router.route(
      const <InvoiceRecognitionImageInput>[
        InvoiceRecognitionImageInput(
          localReference: '/tmp/right.jpg',
          fileName: 'right.jpg',
          payloads: <String>['**detail-payload'],
        ),
      ],
    );

    expect(result.route, InvoiceRecognitionRoute.manualQrDesignation);
    expect(result.requiresManualQrDesignation, isTrue);
    expect(result.hasReviewCandidate, isFalse);
    expect(result.unresolvedEvidence, hasLength(1));
  });

  test('multiple right QR payloads remain blocked for manual selection', () {
    final result = router.route(
      const <InvoiceRecognitionImageInput>[
        InvoiceRecognitionImageInput(
          localReference: '/tmp/mixed.jpg',
          fileName: 'mixed.jpg',
          payloads: <String>[
            leftPayload,
            '**detail-a',
            '**detail-b',
          ],
        ),
      ],
    );

    expect(result.route, InvoiceRecognitionRoute.manualQrDesignation);
    expect(result.requiresManualQrDesignation, isTrue);
    expect(result.canCreateFormalRecord, isFalse);
  });

  test('invalid QR payload falls back to OCR without guessing fields', () {
    final result = router.route(
      const <InvoiceRecognitionImageInput>[
        InvoiceRecognitionImageInput(
          localReference: '/tmp/invalid.jpg',
          fileName: 'invalid.jpg',
          payloads: <String>['AB123'],
        ),
      ],
    );

    expect(result.route, InvoiceRecognitionRoute.traditionalOcr);
    expect(result.unresolvedEvidence, hasLength(1));
    expect(
      result.unresolvedEvidence.single.leftParseResult?.canStageCandidate,
      isFalse,
    );
  });

  test('multiple same-image pairs can be resolved without cross-pairing', () {
    const secondLeft =
        'CD8765432111506099999000000320000003C0000000024531234abcdefghijklmnopqrstuvwx';
    final result = router.route(
      const <InvoiceRecognitionImageInput>[
        InvoiceRecognitionImageInput(
          localReference: '/tmp/a.jpg',
          fileName: 'a.jpg',
          payloads: <String>[leftPayload, '**detail-a'],
        ),
        InvoiceRecognitionImageInput(
          localReference: '/tmp/b.jpg',
          fileName: 'b.jpg',
          payloads: <String>[secondLeft, '**detail-b'],
        ),
      ],
    );

    expect(result.route, InvoiceRecognitionRoute.electronicInvoiceQr);
    expect(result.pairs, hasLength(2));
    expect(result.unresolvedEvidence, isEmpty);
    expect(result.pairs.every((pair) => pair.isComplete), isTrue);
  });

  test('manual designation creates a complete review-only pair', () {
    final result = router.resolveManualDesignation(
      routingResult: ambiguousResult(),
      leftEvidenceIndex: 0,
      rightEvidenceIndex: 1,
    );

    expect(result.route, InvoiceRecognitionRoute.electronicInvoiceQr);
    expect(result.pairs.single.isComplete, isTrue);
    expect(result.hasReviewCandidate, isTrue);
    expect(result.usedNetwork, isFalse);
    expect(result.canCreateFormalRecord, isFalse);
    expect(result.message, isNot(contains(leftPayload)));
    expect(result.message, isNot(contains('**detail-a')));
  });

  test('manual designation allows a warned left-only review candidate', () {
    final result = router.resolveManualDesignation(
      routingResult: ambiguousResult(),
      leftEvidenceIndex: 0,
    );

    expect(result.route, InvoiceRecognitionRoute.electronicInvoiceQr);
    expect(result.pairs.single.isComplete, isFalse);
    expect(result.hasReviewCandidate, isTrue);
    expect(result.warnings, contains(contains('右側明細 QR')));
    expect(result.canCreateFormalRecord, isFalse);
  });

  test('right-only evidence cannot be designated as a left code', () {
    final rightOnly = router.route(
      const <InvoiceRecognitionImageInput>[
        InvoiceRecognitionImageInput(
          localReference: '/tmp/right.jpg',
          fileName: 'right.jpg',
          payloads: <String>['**detail-only'],
        ),
      ],
    );
    final result = router.resolveManualDesignation(
      routingResult: rightOnly,
      leftEvidenceIndex: 0,
    );

    expect(result.route, InvoiceRecognitionRoute.manualQrDesignation);
    expect(result.hasReviewCandidate, isFalse);
    expect(result.canCreateFormalRecord, isFalse);
  });

  test('unknown and duplicate selections remain fail closed', () {
    final ambiguous = ambiguousResult();
    final unknownRight = router.resolveManualDesignation(
      routingResult: ambiguous,
      leftEvidenceIndex: 0,
      rightEvidenceIndex: 3,
    );
    final duplicate = router.resolveManualDesignation(
      routingResult: ambiguous,
      leftEvidenceIndex: 0,
      rightEvidenceIndex: 0,
    );

    expect(unknownRight.route, InvoiceRecognitionRoute.manualQrDesignation);
    expect(unknownRight.hasReviewCandidate, isFalse);
    expect(duplicate.route, InvoiceRecognitionRoute.manualQrDesignation);
    expect(duplicate.hasReviewCandidate, isFalse);
  });

  test('out-of-range manual selection remains fail closed', () {
    final result = router.resolveManualDesignation(
      routingResult: ambiguousResult(),
      leftEvidenceIndex: 99,
      rightEvidenceIndex: 1,
    );

    expect(result.route, InvoiceRecognitionRoute.manualQrDesignation);
    expect(result.hasReviewCandidate, isFalse);
    expect(result.canCreateFormalRecord, isFalse);
  });
}
