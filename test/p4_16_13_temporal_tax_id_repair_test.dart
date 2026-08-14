import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/traditional_tax_id_temporal_repair.dart';

void main() {
  test('CD evidence repairs repeated 30348553 to 30340553', () {
    final result = resolvePositionalTaxIdTemporalRepair(
      history: const <PositionalTaxIdFrameObservation>[
        PositionalTaxIdFrameObservation(
          invoiceNumber: 'CD90000017',
          rawCandidate: '30348553',
        ),
      ],
      currentInvoiceNumber: 'CD90000017',
      currentRawCandidate: '30348553',
    );

    expect(result.accepted, isTrue);
    expect(result.repairedValue, '30340553');
    expect(result.observations, 2);
    expect(result.rule, positionalTaxIdSingleEightToZeroRule);
  });

  test('AA evidence family converges to the unique checksum-valid repair', () {
    final result = resolvePositionalTaxIdTemporalRepair(
      history: const <PositionalTaxIdFrameObservation>[
        PositionalTaxIdFrameObservation(
          invoiceNumber: 'AA90000001',
          rawCandidate: '38342553',
        ),
      ],
      currentInvoiceNumber: 'AA90000001',
      currentRawCandidate: '38340553',
    );

    expect(result.accepted, isTrue);
    expect(result.repairedValue, '30340553');
    expect(result.rawCandidates, <String>['38342553', '38340553']);
  });

  test('single frame can never authorize temporal repair', () {
    final result = resolvePositionalTaxIdTemporalRepair(
      history: const <PositionalTaxIdFrameObservation>[],
      currentInvoiceNumber: 'CD90000017',
      currentRawCandidate: '30348553',
    );

    expect(result.accepted, isFalse);
    expect(result.repairedValue, isEmpty);
  });

  test('different invoice identities do not combine evidence', () {
    final result = resolvePositionalTaxIdTemporalRepair(
      history: const <PositionalTaxIdFrameObservation>[
        PositionalTaxIdFrameObservation(
          invoiceNumber: 'AA90000001',
          rawCandidate: '30348553',
        ),
      ],
      currentInvoiceNumber: 'CD90000017',
      currentRawCandidate: '30348553',
    );

    expect(result.accepted, isFalse);
  });

  test('ambiguous checksum repairs fail closed', () {
    final result = resolvePositionalTaxIdTemporalRepair(
      history: const <PositionalTaxIdFrameObservation>[
        PositionalTaxIdFrameObservation(
          invoiceNumber: 'AA90000001',
          rawCandidate: '10000285',
        ),
      ],
      currentInvoiceNumber: 'AA90000001',
      currentRawCandidate: '10000288',
    );

    expect(repairSingleEightToZeroTaiwanTaxId('10000285'), '10000205');
    expect(repairSingleEightToZeroTaiwanTaxId('10000288'), '10000280');
    expect(result.accepted, isFalse);
    expect(result.repairedValue, isEmpty);
  });

  test('bounded header extractor finds the masked-NO candidate only', () {
    final candidate = extractUnverifiedPositionalHeaderTaxIdFromLines(
      rawLines: const <String>[
        '測試商行',
        'AA90000001',
        '30348553',
        '2026/05/23',
        '交易明細',
        '商品 A 110',
      ],
      invoiceNumber: 'AA90000001',
    );

    expect(candidate, '30348553');
  });

  test('buyer context and multiple header candidates are rejected', () {
    final buyer = extractUnverifiedPositionalHeaderTaxIdFromLines(
      rawLines: const <String>[
        '測試商行',
        'AA90000001',
        '買方',
        '30340553',
        '交易明細',
      ],
      invoiceNumber: 'AA90000001',
    );
    final multiple = extractUnverifiedPositionalHeaderTaxIdFromLines(
      rawLines: const <String>[
        '測試商行',
        'AA90000001',
        '30348553',
        '38340553',
        '交易明細',
      ],
      invoiceNumber: 'AA90000001',
    );

    expect(buyer, isNull);
    expect(multiple, isNull);
  });
}
