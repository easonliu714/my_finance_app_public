import 'invoice_import_staging.dart';
import 'invoice_qr_parser.dart';

class InvoiceQrImportRejectedPayload {
  const InvoiceQrImportRejectedPayload({
    required this.index,
    required this.rawPayload,
    required this.errors,
    this.warnings = const <String>[],
  });

  final int index;
  final String rawPayload;
  final List<String> errors;
  final List<String> warnings;
}

class InvoiceQrImportStagingResult {
  const InvoiceQrImportStagingResult({
    required this.batch,
    required this.rejectedPayloads,
  });

  final InvoiceImportStagingBatch batch;
  final List<InvoiceQrImportRejectedPayload> rejectedPayloads;

  int get acceptedInputCount => batch.items.length;
  int get rejectedInputCount => rejectedPayloads.length;
  bool get hasRejectedPayloads => rejectedPayloads.isNotEmpty;
}

class InvoiceQrImportStagingService {
  const InvoiceQrImportStagingService({
    this.parser = const InvoiceQrParser(),
    this.stagingService = const InvoiceImportStagingService(),
  });

  final InvoiceQrParser parser;
  final InvoiceImportStagingService stagingService;

  InvoiceQrImportStagingResult createBatchFromPayloads({
    required String batchId,
    required List<String> rawPayloads,
    String Function(InvoiceQrParseResult result)? sellerNameResolver,
    DateTime? now,
  }) {
    final items = <InvoiceImportStagingItem>[];
    final rejected = <InvoiceQrImportRejectedPayload>[];
    final timestamp = now ?? DateTime.now().toUtc();

    for (var index = 0; index < rawPayloads.length; index += 1) {
      final rawPayload = rawPayloads[index];
      final result = parser.parse(rawPayload);
      if (!result.isValid) {
        rejected.add(
          InvoiceQrImportRejectedPayload(
            index: index,
            rawPayload: rawPayload,
            errors: result.errors,
            warnings: result.warnings,
          ),
        );
        continue;
      }

      final sellerName = sellerNameResolver?.call(result) ?? '';
      items.add(
        result.toStagingItemCandidate(
          id: '$batchId-qr-${index + 1}',
          sellerName: sellerName,
          note: 'QR parser batch staging',
          now: timestamp,
        ),
      );
    }

    final batch = stagingService.createBatch(id: batchId, items: items);
    return InvoiceQrImportStagingResult(
      batch: batch,
      rejectedPayloads: List<InvoiceQrImportRejectedPayload>.unmodifiable(rejected),
    );
  }
}
