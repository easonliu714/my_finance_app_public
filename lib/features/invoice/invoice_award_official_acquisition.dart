import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:http/http.dart' as http;
import 'package:my_finance_app/features/invoice/invoice_award_official_dataset.dart';

/// Raw bytes fetched from an official award-number publication surface.
/// This object deliberately contains no user invoice/accounting data.
class OfficialInvoiceAwardRawDocument {
  const OfficialInvoiceAwardRawDocument({
    required this.sourceUri,
    required this.fetchedAt,
    required this.bytes,
  });

  final Uri sourceUri;
  final DateTime fetchedAt;
  final Uint8List bytes;

  bool get isApprovedOfficialSource =>
      sourceUri.scheme == 'https' &&
      (sourceUri.host == 'invoice.etax.nat.gov.tw' ||
          sourceUri.host == 'www.etax.nat.gov.tw');
}

class OfficialInvoiceAwardParseContext {
  const OfficialInvoiceAwardParseContext({
    required this.expectedPeriod,
    required this.fetchedAt,
    required this.contentSha256,
  });

  final OfficialInvoiceAwardPeriod expectedPeriod;
  final DateTime fetchedAt;
  final String contentSha256;
}

abstract interface class OfficialInvoiceAwardDocumentParser {
  String get parserVersion;

  OfficialInvoiceAwardDataset parse(
    OfficialInvoiceAwardRawDocument document,
    OfficialInvoiceAwardParseContext context,
  );
}

abstract interface class OfficialInvoiceAwardLastKnownGoodStore {
  OfficialInvoiceAwardDataset? read(OfficialInvoiceAwardPeriod period);

  void replaceValidated(OfficialInvoiceAwardDataset dataset);
}

class InMemoryOfficialInvoiceAwardLastKnownGoodStore
    implements OfficialInvoiceAwardLastKnownGoodStore {
  final Map<String, OfficialInvoiceAwardDataset> _datasets = {};

  @override
  OfficialInvoiceAwardDataset? read(OfficialInvoiceAwardPeriod period) =>
      _datasets[period.id];

  @override
  void replaceValidated(OfficialInvoiceAwardDataset dataset) {
    _datasets[dataset.period.id] = dataset;
  }
}

enum OfficialInvoiceAwardRefreshFailure {
  networkFailure,
  httpStatusFailure,
  nonOfficialSource,
  parserFailure,
  validationFailure,
  unexpectedPeriod,
}

class OfficialInvoiceAwardRefreshResult {
  const OfficialInvoiceAwardRefreshResult._({
    required this.dataset,
    required this.failure,
    required this.replacedLastKnownGood,
  });

  const OfficialInvoiceAwardRefreshResult.success(
    OfficialInvoiceAwardDataset dataset,
  ) : this._(
          dataset: dataset,
          failure: null,
          replacedLastKnownGood: true,
        );

  const OfficialInvoiceAwardRefreshResult.failure(
    OfficialInvoiceAwardRefreshFailure failure,
    OfficialInvoiceAwardDataset? lastKnownGood,
  ) : this._(
          dataset: lastKnownGood,
          failure: failure,
          replacedLastKnownGood: false,
        );

  final OfficialInvoiceAwardDataset? dataset;
  final OfficialInvoiceAwardRefreshFailure? failure;
  final bool replacedLastKnownGood;

  bool get isSuccess => failure == null;
}

/// Bounded acquisition coordinator. Exact official bytes are fingerprinted,
/// parsed by the pinned parser, validated, and only then replace LKG.
class OfficialInvoiceAwardAcquisitionCoordinator {
  OfficialInvoiceAwardAcquisitionCoordinator({
    required this.parser,
    required this.validator,
    required this.store,
  });

  final OfficialInvoiceAwardDocumentParser parser;
  final OfficialInvoiceAwardDatasetValidator validator;
  final OfficialInvoiceAwardLastKnownGoodStore store;

  OfficialInvoiceAwardRefreshResult preserveLastKnownGood({
    required OfficialInvoiceAwardPeriod expectedPeriod,
    required OfficialInvoiceAwardRefreshFailure failure,
  }) =>
      OfficialInvoiceAwardRefreshResult.failure(
        failure,
        store.read(expectedPeriod),
      );

  Future<OfficialInvoiceAwardRefreshResult> ingest({
    required OfficialInvoiceAwardRawDocument document,
    required OfficialInvoiceAwardPeriod expectedPeriod,
  }) async {
    final previous = store.read(expectedPeriod);
    if (!document.isApprovedOfficialSource) {
      return OfficialInvoiceAwardRefreshResult.failure(
        OfficialInvoiceAwardRefreshFailure.nonOfficialSource,
        previous,
      );
    }

    final digest = await Sha256().hash(document.bytes);
    final contentSha256 = digest.bytes
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();

    OfficialInvoiceAwardDataset parsed;
    try {
      parsed = parser.parse(
        document,
        OfficialInvoiceAwardParseContext(
          expectedPeriod: expectedPeriod,
          fetchedAt: document.fetchedAt,
          contentSha256: contentSha256,
        ),
      );
    } catch (_) {
      return OfficialInvoiceAwardRefreshResult.failure(
        OfficialInvoiceAwardRefreshFailure.parserFailure,
        previous,
      );
    }

    if (parsed.period.id != expectedPeriod.id) {
      return OfficialInvoiceAwardRefreshResult.failure(
        OfficialInvoiceAwardRefreshFailure.unexpectedPeriod,
        previous,
      );
    }
    if (!validator.validate(parsed).isValid ||
        parsed.provenance.contentSha256 != contentSha256 ||
        parsed.provenance.parserVersion != parser.parserVersion) {
      return OfficialInvoiceAwardRefreshResult.failure(
        OfficialInvoiceAwardRefreshFailure.validationFailure,
        previous,
      );
    }

    store.replaceValidated(parsed);
    return OfficialInvoiceAwardRefreshResult.success(parsed);
  }
}

/// Production HTTP boundary for the Ministry of Finance general-award page.
///
/// Only the pinned HTTPS endpoint is requested. The request contains no user
/// invoice, accounting, merchant, device, or identity data. Non-200 responses
/// and transport failures fail closed and preserve the requested period's LKG.
class MinistryOfFinanceGeneralAwardHttpAcquisitionService {
  MinistryOfFinanceGeneralAwardHttpAcquisitionService({
    required http.Client client,
    required OfficialInvoiceAwardAcquisitionCoordinator coordinator,
    DateTime Function()? clock,
    Uri? sourceUri,
  })  : _client = client,
        _coordinator = coordinator,
        _clock = clock ?? DateTime.now,
        _sourceUri = sourceUri ?? currentSourceUri;

  static final Uri currentSourceUri =
      Uri.parse('https://invoice.etax.nat.gov.tw/');
  static final Uri previousSourceUri =
      Uri.parse('https://invoice.etax.nat.gov.tw/lastNumber.html');
  static final Uri officialSourceUri = currentSourceUri;

  final http.Client _client;
  final OfficialInvoiceAwardAcquisitionCoordinator _coordinator;
  final DateTime Function() _clock;
  final Uri _sourceUri;

  Future<OfficialInvoiceAwardRefreshResult> refresh(
    OfficialInvoiceAwardPeriod expectedPeriod,
  ) async {
    http.Response response;
    try {
      response = await _client.get(
        _sourceUri,
        headers: const <String, String>{
          'Accept': 'text/html,application/xhtml+xml',
        },
      );
    } catch (_) {
      return _coordinator.preserveLastKnownGood(
        expectedPeriod: expectedPeriod,
        failure: OfficialInvoiceAwardRefreshFailure.networkFailure,
      );
    }

    if (response.statusCode != 200) {
      return _coordinator.preserveLastKnownGood(
        expectedPeriod: expectedPeriod,
        failure: OfficialInvoiceAwardRefreshFailure.httpStatusFailure,
      );
    }

    return _coordinator.ingest(
      document: OfficialInvoiceAwardRawDocument(
        sourceUri: _sourceUri,
        fetchedAt: _clock().toUtc(),
        bytes: Uint8List.fromList(response.bodyBytes),
      ),
      expectedPeriod: expectedPeriod,
    );
  }
}