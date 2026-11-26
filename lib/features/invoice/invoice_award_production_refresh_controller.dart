import 'invoice_award_lkg_repository.dart';
import 'invoice_award_official_acquisition.dart';
import 'invoice_award_official_dataset.dart';

/// Production orchestration for a user-initiated general-award refresh.
///
/// The controller hydrates the bounded durable LKG snapshot before network
/// acquisition, delegates official HTTPS acquisition/parsing/validation to the
/// canonical coordinator, and persists only a newly validated dataset. It has
/// no invoice/accounting upload or formal-transaction write authority.
class InvoiceAwardProductionRefreshController {
  const InvoiceAwardProductionRefreshController({
    required this.service,
    required this.volatileStore,
    required this.durableRepository,
    required this.validator,
    this.codec = const OfficialInvoiceAwardLkgCodec(),
  });

  final MinistryOfFinanceGeneralAwardHttpAcquisitionService service;
  final OfficialInvoiceAwardLastKnownGoodStore volatileStore;
  final OfficialInvoiceAwardLkgRepository durableRepository;
  final OfficialInvoiceAwardDatasetValidator validator;
  final OfficialInvoiceAwardLkgCodec codec;

  Future<OfficialInvoiceAwardRefreshResult> refresh(
    OfficialInvoiceAwardPeriod expectedPeriod,
  ) async {
    await _hydrateLastKnownGood(expectedPeriod);

    final result = await service.refresh(expectedPeriod);
    final dataset = result.dataset;
    if (!result.isSuccess || dataset == null) return result;

    // Persist only the canonical validator-approved result. If durable storage
    // fails, keep the already hydrated LKG rather than claiming durable success.
    try {
      final snapshot = codec.encode(dataset, validator);
      await durableRepository.replaceValidated(snapshot);
    } catch (_) {
      final retained = volatileStore.read(expectedPeriod);
      return OfficialInvoiceAwardRefreshResult.failure(
        OfficialInvoiceAwardRefreshFailure.validationFailure,
        retained,
      );
    }
    return result;
  }

  Future<void> _hydrateLastKnownGood(
    OfficialInvoiceAwardPeriod expectedPeriod,
  ) async {
    try {
      final snapshot = await durableRepository.read(expectedPeriod.id);
      if (snapshot == null) return;
      final dataset = codec.decode(snapshot, validator);
      if (dataset.period.id != expectedPeriod.id) return;
      volatileStore.replaceValidated(dataset);
    } catch (_) {
      // Corrupt/unreadable durable state is fail-closed. It is never promoted
      // into the acquisition coordinator and network refresh may still proceed.
    }
  }
}
