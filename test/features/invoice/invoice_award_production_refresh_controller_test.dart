import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/invoice_award_lkg_repository.dart';
import 'package:my_finance_app/features/invoice/invoice_award_official_acquisition.dart';
import 'package:my_finance_app/features/invoice/invoice_award_official_dataset.dart';
import 'package:my_finance_app/features/invoice/invoice_award_official_html_parser.dart';
import 'package:my_finance_app/features/invoice/invoice_award_production_refresh_controller.dart';

void main() {
  const period = OfficialInvoiceAwardPeriod(
    rocYear: 115,
    startMonth: 7,
    endMonth: 8,
  );
  const validator = OfficialInvoiceAwardDatasetValidator();
  const codec = OfficialInvoiceAwardLkgCodec();

  OfficialInvoiceAwardDataset dataset() => OfficialInvoiceAwardDataset(
        period: period,
        provenance: OfficialInvoiceAwardProvenance(
          sourceId: OfficialInvoiceAwardProvenance.ministryOfFinanceSourceId,
          fetchedAt: DateTime.utc(2026, 9, 25, 6),
          parserVersion: 'mof-general-award-html-v1',
          contentSha256: 'a' * 64,
        ),
        published: true,
        complete: true,
        rules: const <OfficialInvoiceAwardRule>[
          OfficialInvoiceAwardRule(
            kind: OfficialInvoiceAwardRuleKind.special,
            number: '12345678',
          ),
          OfficialInvoiceAwardRule(
            kind: OfficialInvoiceAwardRuleKind.grand,
            number: '23456789',
          ),
          OfficialInvoiceAwardRule(
            kind: OfficialInvoiceAwardRuleKind.first,
            number: '34567890',
          ),
        ],
      );

  test('hydrates durable LKG before network failure and preserves it', () async {
    final durable = _MemoryDurableRepository();
    await durable.replaceValidated(codec.encode(dataset(), validator));
    final volatile = InMemoryOfficialInvoiceAwardLastKnownGoodStore();
    final coordinator = OfficialInvoiceAwardAcquisitionCoordinator(
      parser: const MinistryOfFinanceGeneralAwardHtmlParser(),
      validator: validator,
      store: volatile,
    );
    final service = MinistryOfFinanceGeneralAwardHttpAcquisitionService(
      client: MockClient((_) async => throw http.ClientException('offline')),
      coordinator: coordinator,
    );
    final controller = InvoiceAwardProductionRefreshController(
      service: service,
      volatileStore: volatile,
      durableRepository: durable,
      validator: validator,
    );

    final result = await controller.refresh(period);

    expect(result.isSuccess, isFalse);
    expect(result.failure, OfficialInvoiceAwardRefreshFailure.networkFailure);
    expect(result.dataset?.period.id, '115-07-08');
    expect(volatile.read(period)?.provenance.contentSha256, 'a' * 64);
  });

  test('corrupt durable snapshot is never promoted', () async {
    final durable = _MemoryDurableRepository(
      initial: const OfficialInvoiceAwardLkgSnapshot(
        periodId: '115-07-08',
        payload: '{not-json',
      ),
    );
    final volatile = InMemoryOfficialInvoiceAwardLastKnownGoodStore();
    final coordinator = OfficialInvoiceAwardAcquisitionCoordinator(
      parser: const MinistryOfFinanceGeneralAwardHtmlParser(),
      validator: validator,
      store: volatile,
    );
    final service = MinistryOfFinanceGeneralAwardHttpAcquisitionService(
      client: MockClient((_) async => throw http.ClientException('offline')),
      coordinator: coordinator,
    );
    final controller = InvoiceAwardProductionRefreshController(
      service: service,
      volatileStore: volatile,
      durableRepository: durable,
      validator: validator,
    );

    final result = await controller.refresh(period);

    expect(result.failure, OfficialInvoiceAwardRefreshFailure.networkFailure);
    expect(result.dataset, isNull);
    expect(volatile.read(period), isNull);
  });
}

class _MemoryDurableRepository implements OfficialInvoiceAwardLkgRepository {
  _MemoryDurableRepository({this.initial});

  OfficialInvoiceAwardLkgSnapshot? initial;

  @override
  Future<OfficialInvoiceAwardLkgSnapshot?> read(String periodId) async => initial;

  @override
  Future<void> replaceValidated(OfficialInvoiceAwardLkgSnapshot snapshot) async {
    initial = snapshot;
  }
}
