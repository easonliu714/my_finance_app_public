import 'dart:convert';

import '../../account/account_record.dart';
import '../../transaction/transaction_record.dart';
import '../../transaction/transaction_type.dart';
import '../cloud_invoice_candidate.dart';

const int canonicalCloudInvoicePayloadVersion = 1;

String encodeCloudInvoiceLineItems(List<CloudInvoiceLineItem> items) {
  return jsonEncode(<String, Object?>{
    'version': canonicalCloudInvoicePayloadVersion,
    'items': items
        .map(
          (item) => <String, Object?>{
            'name': item.name,
            'amount': item.amount,
            'quantity': item.quantity,
            'unit_price': item.unitPrice,
            'raw_name': item.rawName,
            'category_suggestion': item.categorySuggestion,
          },
        )
        .toList(growable: false),
  });
}

List<CloudInvoiceLineItem> decodeCloudInvoiceLineItems(String payload) {
  final decoded = jsonDecode(payload);
  if (decoded is! Map<String, Object?>) {
    throw const FormatException('LINE_ITEMS_PAYLOAD_NOT_OBJECT');
  }
  final version = decoded['version'];
  if (version != canonicalCloudInvoicePayloadVersion) {
    throw FormatException('LINE_ITEMS_PAYLOAD_VERSION_UNSUPPORTED:$version');
  }
  final rawItems = decoded['items'];
  if (rawItems is! List<Object?>) {
    throw const FormatException('LINE_ITEMS_ARRAY_REQUIRED');
  }
  return rawItems.map((rawItem) {
    if (rawItem is! Map<String, Object?>) {
      throw const FormatException('LINE_ITEM_NOT_OBJECT');
    }
    final name = _nonEmptyString(rawItem, 'name');
    final amount = _requiredNum(rawItem, 'amount').toDouble();
    return CloudInvoiceLineItem(
      name: name,
      amount: amount,
      quantity: _nullableNum(rawItem['quantity']),
      unitPrice: _nullableNum(rawItem['unit_price']),
      rawName: rawItem['raw_name'] as String?,
      categorySuggestion: rawItem['category_suggestion'] as String?,
    );
  }).toList(growable: false);
}

String encodeTransactionBeforeImage(TransactionRecord record) {
  return jsonEncode(<String, Object?>{
    'version': canonicalCloudInvoicePayloadVersion,
    'transaction': record.toMap(),
  });
}

TransactionRecord decodeTransactionBeforeImage(String payload) {
  final decoded = jsonDecode(payload);
  if (decoded is! Map<String, Object?>) {
    throw const FormatException('TRANSACTION_PAYLOAD_NOT_OBJECT');
  }
  final version = decoded['version'];
  if (version != canonicalCloudInvoicePayloadVersion) {
    throw FormatException('TRANSACTION_PAYLOAD_VERSION_UNSUPPORTED:$version');
  }
  final transaction = decoded['transaction'];
  if (transaction is! Map<String, Object?>) {
    throw const FormatException('TRANSACTION_OBJECT_REQUIRED');
  }

  _nonEmptyString(transaction, 'id');
  _stringField(transaction, 'category');
  _nonEmptyString(transaction, 'occurred_at');
  _stringField(transaction, 'account_name');
  _stringField(transaction, 'member_name');
  _stringField(transaction, 'merchant_name');
  _stringField(transaction, 'tag_name');
  _stringField(transaction, 'note');
  _requiredNum(transaction, 'amount');

  final typeName = _nonEmptyString(transaction, 'type');
  if (!TransactionType.values.any((item) => item.name == typeName)) {
    throw FormatException('TRANSACTION_TYPE_UNSUPPORTED:$typeName');
  }

  final currencyCode = _nonEmptyString(transaction, 'currency_code');
  if (!CurrencyCode.values.any((item) => item.code == currencyCode)) {
    throw FormatException('TRANSACTION_CURRENCY_UNSUPPORTED:$currencyCode');
  }

  final occurredAtText = _nonEmptyString(transaction, 'occurred_at');
  if (DateTime.tryParse(occurredAtText) == null) {
    throw FormatException('TRANSACTION_OCCURRED_AT_INVALID:$occurredAtText');
  }

  return TransactionRecord.fromMap(transaction);
}

String _stringField(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is! String) {
    throw FormatException('REQUIRED_STRING_MISSING:$key');
  }
  return value;
}

String _nonEmptyString(Map<String, Object?> map, String key) {
  final value = _stringField(map, key);
  if (value.trim().isEmpty) {
    throw FormatException('REQUIRED_STRING_EMPTY:$key');
  }
  return value;
}

num _requiredNum(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is! num) {
    throw FormatException('REQUIRED_NUMBER_MISSING:$key');
  }
  return value;
}

double? _nullableNum(Object? value) {
  if (value == null) return null;
  if (value is! num) throw const FormatException('OPTIONAL_NUMBER_INVALID');
  return value.toDouble();
}
