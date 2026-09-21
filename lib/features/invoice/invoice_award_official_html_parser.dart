import 'dart:convert';

import 'package:my_finance_app/features/invoice/invoice_award_official_acquisition.dart';
import 'package:my_finance_app/features/invoice/invoice_award_official_dataset.dart';

/// Strict parser for the public Ministry of Finance general-award HTML surface.
///
/// This parser is intentionally narrow:
/// - only the official `invoice.etax.nat.gov.tw` root/index surface is accepted;
/// - the expected ROC two-month period must be present in the document;
/// - special / grand / exactly three first-prize numbers must be recoverable;
/// - second through sixth prizes are not parsed as independent numbers because
///   they are deterministically derived from the first-prize numbers by the
///   matcher contract;
/// - optional additional-sixth numbers are retained only when the official row
///   is explicitly present.
///
/// Cloud-exclusive numbers remain a separate authority domain and are not
/// parsed by this class.
class MinistryOfFinanceGeneralAwardHtmlParser
    implements OfficialInvoiceAwardDocumentParser {
  const MinistryOfFinanceGeneralAwardHtmlParser();

  static const String _officialHost = 'invoice.etax.nat.gov.tw';
  static const Set<String> _supportedPaths = <String>{'/', '/index.html'};

  @override
  String get parserVersion => 'mof-general-award-html-v1';

  @override
  OfficialInvoiceAwardDataset parse(
    OfficialInvoiceAwardRawDocument document,
    OfficialInvoiceAwardParseContext context,
  ) {
    if (document.sourceUri.scheme != 'https' ||
        document.sourceUri.host != _officialHost ||
        !_supportedPaths.contains(document.sourceUri.path)) {
      throw const FormatException('unsupported Ministry of Finance award surface');
    }

    final html = utf8.decode(document.bytes, allowMalformed: false);
    final text = _visibleText(html);
    final periodMarker =
        '${context.expectedPeriod.rocYear}年'
        '${context.expectedPeriod.startMonth.toString().padLeft(2, '0')}-'
        '${context.expectedPeriod.endMonth.toString().padLeft(2, '0')}月中獎號碼單';

    if (!text.contains(periodMarker)) {
      throw FormatException('expected award period not found: $periodMarker');
    }

    final special = _extractExactEightDigitRow(text, '特別獎');
    final grand = _extractExactEightDigitRow(text, '特獎');
    final firstNumbers = _extractFirstPrizeNumbers(text);
    final additionalSixth = _extractOptionalAdditionalSixthNumbers(text);

    return OfficialInvoiceAwardDataset(
      period: context.expectedPeriod,
      provenance: OfficialInvoiceAwardProvenance(
        sourceId: OfficialInvoiceAwardProvenance.ministryOfFinanceSourceId,
        fetchedAt: context.fetchedAt,
        parserVersion: parserVersion,
        contentSha256: context.contentSha256,
      ),
      published: true,
      complete: true,
      rules: <OfficialInvoiceAwardRule>[
        OfficialInvoiceAwardRule(
          kind: OfficialInvoiceAwardRuleKind.special,
          number: special,
        ),
        OfficialInvoiceAwardRule(
          kind: OfficialInvoiceAwardRuleKind.grand,
          number: grand,
        ),
        for (final number in firstNumbers)
          OfficialInvoiceAwardRule(
            kind: OfficialInvoiceAwardRuleKind.first,
            number: number,
          ),
        for (final number in additionalSixth)
          OfficialInvoiceAwardRule(
            kind: OfficialInvoiceAwardRuleKind.additionalSixth,
            number: number,
          ),
      ],
    );
  }

  String _extractExactEightDigitRow(String text, String label) {
    final match = RegExp(
      '${RegExp.escape(label)}\\s*([0-9\\s]{8,20})\\s*同期統一發票',
    ).firstMatch(text);
    if (match == null) {
      throw FormatException('missing $label row');
    }
    final digits = match.group(1)!.replaceAll(RegExp(r'\s+'), '');
    if (!RegExp(r'^\d{8}$').hasMatch(digits)) {
      throw FormatException('malformed $label number');
    }
    return digits;
  }

  List<String> _extractFirstPrizeNumbers(String text) {
    final match = RegExp(
      r'頭獎\s*([0-9\s]{24,60})\s*同期統一發票',
    ).firstMatch(text);
    if (match == null) {
      throw const FormatException('missing first-prize row');
    }

    final digits = match.group(1)!.replaceAll(RegExp(r'\s+'), '');
    if (digits.length != 24 || !RegExp(r'^\d{24}$').hasMatch(digits)) {
      throw const FormatException(
        'first-prize row must contain exactly three 8-digit numbers',
      );
    }

    return <String>[
      digits.substring(0, 8),
      digits.substring(8, 16),
      digits.substring(16, 24),
    ];
  }

  List<String> _extractOptionalAdditionalSixthNumbers(String text) {
    if (!text.contains('增開六獎')) {
      return const <String>[];
    }

    final match = RegExp(
      r'增開六獎\s*([0-9\s、,，]{3,80})\s*同期',
    ).firstMatch(text);
    if (match == null) {
      throw const FormatException('malformed additional-sixth row');
    }

    final digits = match.group(1)!.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty ||
        digits.length % 3 != 0 ||
        !RegExp(r'^\d+$').hasMatch(digits)) {
      throw const FormatException('malformed additional-sixth numbers');
    }

    return <String>[
      for (var offset = 0; offset < digits.length; offset += 3)
        digits.substring(offset, offset + 3),
    ];
  }

  String _visibleText(String html) {
    var text = html
        .replaceAll(
          RegExp(
            r'<script\b[^>]*>.*?</script>',
            caseSensitive: false,
            dotAll: true,
          ),
          ' ',
        )
        .replaceAll(
          RegExp(
            r'<style\b[^>]*>.*?</style>',
            caseSensitive: false,
            dotAll: true,
          ),
          ' ',
        )
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), ' ')
        .replaceAll(
          RegExp(
            r'</(?:td|th|tr|p|div|li|h[1-6])>',
            caseSensitive: false,
          ),
          ' ',
        )
        .replaceAll(RegExp(r'<[^>]+>'), ' ');

    const entities = <String, String>{
      '&nbsp;': ' ',
      '&#160;': ' ',
      '&amp;': '&',
      '&lt;': '<',
      '&gt;': '>',
      '&quot;': '"',
      '&#39;': "'",
    };
    for (final entry in entities.entries) {
      text = text.replaceAll(entry.key, entry.value);
    }
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}
