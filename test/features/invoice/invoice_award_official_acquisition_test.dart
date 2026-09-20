import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/invoice_award_official_acquisition.dart';
import 'package:my_finance_app/features/invoice/invoice_award_official_dataset.dart';

void main() {
  const period = OfficialInvoiceAwardPeriod(
    rocYear: 115,
    startMonth: 5,
    endMonth: 6,
  );

  OfficialInvoiceAwardRawDocument document({
    String host = 'invoice.etax.nat.gov.tw',
    String body = 'official-award-document',
  }) =>
      OfficialInvoiceAwardRawDocument(
        sourceUri: Uri.https(host, '/'),
        fetchedAt: DateTime.utc(2026, 7, 25, 8),
        bytes: Uint8List.fromList(utf8.encode(body)),
      );

  test('official source is fingerprinted before validated LKG replacement', () async {
    final store = InMemoryOfficialInvoiceAwardLastKnownGoodStore();
    final coordinator = OfficialInvoiceAwardAcquisitionCoordinator(
      parser: const _FixtureParser(),
      validator: const OfficialInvoiceAwardDatasetValidator(),
      store: store,
    );

    final result = await coordinator.ingest(
      document: document(),
      expectedPeriod: period,
    );

    expect(result.isSuccess, isTrue);
    expect(result.replacedLastKnownGood, isTrue);
    expect(result.dataset?.provenance.contentSha256, hasLength(64));
    expect(store.read(period)?.provenance.contentSha256,
        result.dataset?.provenance.contentSha256);
  });

  test('third-party source fails closed before parser and preserves LKG', () async {
    final store = InMemoryOfficialInvoiceAwardLastKnownGoodStore();
    final parser = _FixtureParser();
    final coordinator = OfficialInvoiceAwardAcquisitionCoordinator(
      parser: parser,
      validator: const OfficialInvoiceAwardDatasetValidator(),
      store: store,
    );

    final seeded = await coordinator.ingest(
      document: document(),
      expectedPeriod: period,
    );
    final originalFingerprint = seeded.dataset!.provenance.contentSha256;
    final callsBefore = parser.calls;

    final rejected = await coordinator.ingest(
      document: document(host: 'example.com', body: 'tampered'),
      expectedPeriod: period,
    );

    expect(rejected.failure, OfficialInvoiceAwardRefreshFailure.nonOfficialSource);
    expect(rejected.replacedLastKnownGood, isFalse);
    expect(parser.calls, callsBefore);
    expect(store.read(period)?.provenance.contentSha256, originalFingerprint);
  });

  test('parser failure preserves last-known-good dataset', () async {
    final store = InMemoryOfficialInvoiceAwardLastKnownGoodStore();
    final goodCoordinator = OfficialInvoiceAwardAcquisitionCoordinator(
      parser: const _FixtureParser(),
      validator: const OfficialInvoiceAwardDatasetValidator(),
      store: store,
    );
    final seeded = await goodCoordinator.ingest(
      document: document(),
      expectedPeriod: period,
    );

    final failingCoordinator = OfficialInvoiceAwardAcquisitionCoordinator(
      parser: const _ThrowingParser(),
      validator: const OfficialInvoiceAwardDatasetValidator(),
      store: store,
    );
    final result = await failingCoordinator.ingest(
      document: document(body: 'schema-drift'),
      expectedPeriod: period,
    );

    expect(result.failure, OfficialInvoiceAwardRefreshFailure.parserFailure);
    expect(result.replacedLastKnownGood, isFalse);
    expect(result.dataset?.provenance.contentSha256,
        seeded.dataset?.provenance.contentSha256);
  });

  test('unexpected period fails closed and cannot replace requested LKG', () async {
    final store = InMemoryOfficialInvoiceAwardLastKnownGoodStore();
    final coordinator = OfficialInvoiceAwardAcquisitionCoordinator(
      parser: const _WrongPeriodParser(),
      validator: const OfficialInvoiceAwardDatasetValidator(),
      store: store,
    );

    final result = await coordinator.ingest(
      document: document(),
      expectedPeriod: period,
    );

    expect(result.failure, OfficialInvoiceAwardRefreshFailure.unexpectedPeriod);
    expect(result.replacedLastKnownGood, isFalse);
    expect(store.read(period), isNull);
  });
}

class _FixtureParser implements OfficialInvoiceAwardDocumentParser {
  const _FixtureParser();

  static int _globalCalls = 0;
  int get calls => _globalCalls;

  @override
  String get parserVersion => 'fixture-v1';

  @override
  OfficialInvoiceAwardDataset parse(
    OfficialInvoiceAwardRawDocument document,
    OfficialInvoiceAwardParseContext context,
  ) {
    _globalCalls += 1;
    return _dataset(context.expectedPeriod, context, parserVersion);
  }
}

class _ThrowingParser implements OfficialInvoiceAwardDocumentParser {
  const _ThrowingParser();

  @override
  String get parserVersion => 'fixture-v1';

  @override
  OfficialInvoiceAwardDataset parse(
    OfficialInvoiceAwardRawDocument document,
    OfficialInvoiceAwardParseContext context,
  ) =>
      throw const FormatException('schema drift');
}

class _WrongPeriodParser implements OfficialInvoiceAwardDocumentParser {
  const _WrongPeriodParser();

  @override
  String get parserVersion => 'fixture-v1';

  @override
  OfficialInvoiceAwardDataset parse(
    OfficialInvoiceAwardRawDocument document,
    OfficialInvoiceAwardParseContext context,
  ) =>
      _dataset(
        const OfficialInvoiceAwardPeriod(
          rocYear: 115,
          startMonth: 3,
          endMonth: 4,
        ),
        context,
        parserVersion,
      );
}

OfficialInvoiceAwardDataset _dataset(
  OfficialInvoiceAwardPeriod period,
  OfficialInvoiceAwardParseContext context,
  String parserVersion,
) =>
    OfficialInvoiceAwardDataset(
      period: period,
      provenance: OfficialInvoiceAwardProvenance(
        sourceId: OfficialInvoiceAwardProvenance.ministryOfFinanceSourceId,
        fetchedAt: context.fetchedAt,
        parserVersion: parserVersion,
        contentSha256: context.contentSha256,
      ),
      published: true,
      complete: true,
      rules: const [
        OfficialInvoiceAwardRule(
          kind: OfficialInvoiceAwardRuleKind.special,
          number: '38548029',
        ),
        OfficialInvoiceAwardRule(
          kind: OfficialInvoiceAwardRuleKind.grand,
          number: '10138845',
        ),
        OfficialInvoiceAwardRule(
          kind: OfficialInvoiceAwardRuleKind.first,
          number: '24121106',
        ),
      ],
    );
