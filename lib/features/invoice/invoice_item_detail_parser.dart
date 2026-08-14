import 'cloud_invoice_candidate.dart';

class InvoiceItemDetail {
  const InvoiceItemDetail({
    required this.name,
    required this.quantity,
    required this.unitPrice,
  });

  final String name;
  final double quantity;
  final double unitPrice;

  double get amount => quantity * unitPrice;
}

class InvoiceItemDetailParseResult {
  const InvoiceItemDetailParseResult({
    required this.rawPayload,
    required this.items,
    required this.errors,
    required this.warnings,
  });

  final String rawPayload;
  final List<InvoiceItemDetail> items;
  final List<String> errors;
  final List<String> warnings;

  bool get isValid => errors.isEmpty && items.isNotEmpty;
  bool get isBlocked => !isValid;
  bool get requiresReview => warnings.isNotEmpty || isBlocked;
  String get warningSummary => warnings.join('、');
  String get errorSummary => errors.join('、');

  List<CloudInvoiceLineItem> toCloudInvoiceLineItems() {
    if (!isValid) {
      throw StateError('ITEM_DETAIL_NOT_READY');
    }
    return List<CloudInvoiceLineItem>.unmodifiable(
      items.map(
        (item) => CloudInvoiceLineItem(
          name: item.name,
          quantity: item.quantity,
          unitPrice: item.unitPrice,
          amount: item.amount,
          rawName: item.name,
        ),
      ),
    );
  }
}

class InvoiceItemDetailParser {
  const InvoiceItemDetailParser();

  static const String expectedPrefix = '*' '*';

  InvoiceItemDetailParseResult parse(String rawPayload) {
    final payload = rawPayload.trim();
    if (payload.isEmpty) return _blocked(payload, 'EMPTY_PAYLOAD');
    if (!payload.startsWith(expectedPrefix)) {
      return _blocked(payload, 'UNEXPECTED_PREFIX');
    }

    final body = payload.substring(expectedPrefix.length).trim();
    if (body.isEmpty) return _blocked(payload, 'EMPTY_ITEMS');

    final tokens = body
        .split(':')
        .map((token) => token.trim())
        .toList(growable: false);
    final warnings = <String>[];
    final items = <InvoiceItemDetail>[];

    if (tokens.length % 3 != 0) {
      warnings.add('TRAILING_FIELDS_IGNORED');
    }

    for (var index = 0; index + 2 < tokens.length; index += 3) {
      final name = tokens[index];
      final quantity = _positiveDecimal(tokens[index + 1]);
      final unitPrice = _nonNegativeDecimal(tokens[index + 2]);

      if (name.isEmpty) {
        warnings.add('EMPTY_NAME_SKIPPED');
      } else if (quantity == null) {
        warnings.add('BAD_QUANTITY_SKIPPED');
      } else if (unitPrice == null) {
        warnings.add('BAD_UNIT_PRICE_SKIPPED');
      } else {
        items.add(
          InvoiceItemDetail(
            name: name,
            quantity: quantity,
            unitPrice: unitPrice,
          ),
        );
      }
    }

    final errors = <String>[];
    if (items.isEmpty) errors.add('NO_USABLE_ITEMS');

    return InvoiceItemDetailParseResult(
      rawPayload: payload,
      items: List<InvoiceItemDetail>.unmodifiable(items),
      errors: List<String>.unmodifiable(errors),
      warnings: List<String>.unmodifiable(warnings),
    );
  }

  static InvoiceItemDetailParseResult _blocked(String rawPayload, String error) {
    return InvoiceItemDetailParseResult(
      rawPayload: rawPayload,
      items: const <InvoiceItemDetail>[],
      errors: <String>[error],
      warnings: const <String>[],
    );
  }

  static double? _positiveDecimal(String value) {
    final parsed = _decimal(value);
    if (parsed == null || parsed <= 0) return null;
    return parsed;
  }

  static double? _nonNegativeDecimal(String value) {
    final parsed = _decimal(value);
    if (parsed == null || parsed < 0) return null;
    return parsed;
  }

  static double? _decimal(String value) {
    final trimmed = value.trim();
    if (!RegExp(r'^\d+(\.\d+)?$').hasMatch(trimmed)) return null;
    return double.tryParse(trimmed);
  }
}
