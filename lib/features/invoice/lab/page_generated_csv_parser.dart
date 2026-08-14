import 'dart:convert';
import 'dart:typed_data';

import 'ephemeral_authenticated_csv_download.dart';
import 'official_cloud_invoice_csv_adapter.dart';
import 'private_cloud_invoice_csv_import_service.dart';

/// Parses CSV bytes generated inside the currently visible official page.
///
/// The bytes stay in memory only. This parser never receives a Cookie, URL,
/// Authorization header, DOM tree, or HTML string.
class PageGeneratedCsvParser {
  const PageGeneratedCsvParser({
    OfficialCloudInvoiceCsvAdapter adapter = const OfficialCloudInvoiceCsvAdapter(),
    this.maxBytes = 10 * 1024 * 1024,
  }) : _adapter = adapter;

  final OfficialCloudInvoiceCsvAdapter _adapter;
  final int maxBytes;

  PrivateCloudInvoiceCsvSource parse(
    Uint8List bytes, {
    String fileName = 'official_page_export.csv',
  }) {
    if (bytes.isEmpty) {
      throw const EphemeralCsvDownloadException('CSV_GENERATED_EMPTY');
    }
    if (bytes.length > maxBytes) {
      throw const EphemeralCsvDownloadException(
        'CSV_DOWNLOAD_SIZE_LIMIT_EXCEEDED',
      );
    }

    final String csvText;
    try {
      csvText = utf8.decode(bytes, allowMalformed: false);
    } on FormatException {
      throw const EphemeralCsvDownloadException('CSV_UTF8_INVALID');
    }

    final preview = _adapter.createPreview(csvText);
    final invalidHeader = preview.fileIssues.any(
      (issue) => issue.code == OfficialCloudInvoiceCsvIssueCode.invalidHeader,
    );
    if (invalidHeader) {
      throw const EphemeralCsvDownloadException('CSV_SIGNATURE_INVALID');
    }

    return PrivateCloudInvoiceCsvSource(
      fileName: _safeFileName(fileName),
      preview: preview,
    );
  }

  String _safeFileName(String candidate) {
    final normalized = candidate
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    if (normalized.isEmpty || !normalized.toLowerCase().endsWith('.csv')) {
      return 'official_page_export.csv';
    }
    return normalized;
  }
}
