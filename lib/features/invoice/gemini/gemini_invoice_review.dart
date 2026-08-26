import '../taiwan_tax_id.dart';

class GeminiInvoiceReviewLineItem {
  const GeminiInvoiceReviewLineItem({
    required this.name,
    this.quantity,
    this.unitPrice,
    this.amount,
  });

  final String name;
  final double? quantity;
  final double? unitPrice;
  final double? amount;

  bool get isBlank =>
      name.trim().isEmpty && quantity == null && unitPrice == null && amount == null;

  factory GeminiInvoiceReviewLineItem.fromJson(Map<String, Object?> json) {
    return GeminiInvoiceReviewLineItem(
      name: _text(json['name']),
      quantity: _nonNegativeNumber(json['quantity']),
      unitPrice: _nonNegativeNumber(json['unitPrice']),
      amount: _nonNegativeNumber(json['amount']),
    );
  }
}

enum GeminiInvoiceReviewField {
  invoiceNumber,
  invoicePeriod,
  randomCode,
  sellerTaxId,
  invoiceDate,
  invoiceTime,
  merchantName,
  totalAmount,
  lineItems,
}

class GeminiInvoiceReviewCandidate {
  const GeminiInvoiceReviewCandidate({
    required this.invoiceNumber,
    required this.invoicePeriod,
    this.randomCode = '',
    required this.sellerTaxId,
    required this.invoiceDate,
    required this.invoiceTime,
    required this.merchantName,
    required this.totalAmount,
    required this.lineItems,
    required this.confidence,
    required this.warnings,
  });

  final String invoiceNumber;
  final String invoicePeriod;
  final String randomCode;
  final String sellerTaxId;
  final String invoiceDate;
  final String invoiceTime;
  final String merchantName;
  final double? totalAmount;
  final List<GeminiInvoiceReviewLineItem> lineItems;
  final Map<GeminiInvoiceReviewField, double> confidence;
  final List<String> warnings;

  // P4.19.10 compatibility bridge: the production frozen-review page already
  // owns the current Gemini execution but the handoff-card API predates
  // field-level source selection. Keep only the latest successfully parsed
  // candidate and consume it only while that card reports AI comparison data.
  // A future page refactor can pass the candidate explicitly and remove this.
  static GeminiInvoiceReviewCandidate? _latestParsedCandidate;
  static GeminiInvoiceReviewCandidate? get latestParsedCandidate =>
      _latestParsedCandidate;

  bool get usedNetwork => true;
  bool get requiresUserReview => true;
  bool get canCreateFormalRecord => false;

  bool get hasAnyRecognizedValue =>
      invoiceNumber.isNotEmpty ||
      invoicePeriod.isNotEmpty ||
      randomCode.isNotEmpty ||
      sellerTaxId.isNotEmpty ||
      invoiceDate.isNotEmpty ||
      invoiceTime.isNotEmpty ||
      merchantName.isNotEmpty ||
      totalAmount != null ||
      lineItems.isNotEmpty;

  bool get hasCriticalIdentity =>
      invoiceNumber.isNotEmpty && invoicePeriod.isNotEmpty;

  factory GeminiInvoiceReviewCandidate.fromJson(Map<String, Object?> json) {
    final warnings = <String>[
      ..._stringList(json['warnings']),
    ];

    var invoiceNumber = _compactInvoiceNumber(json['invoiceNumber']);
    if (invoiceNumber.isNotEmpty &&
        !RegExp(r'^[A-Z]{2}\d{8}$').hasMatch(invoiceNumber)) {
      warnings.add('AI 發票號碼格式不符，已保持空白。');
      invoiceNumber = '';
    }

    var randomCode = _digits(json['randomCode']);
    if (randomCode.isNotEmpty && !RegExp(r'^\d{4}$').hasMatch(randomCode)) {
      warnings.add('AI 隨機碼不是完整 4 碼，已保持空白。');
      randomCode = '';
    }

    var sellerTaxId = _digits(json['sellerTaxId']);
    if (sellerTaxId.isNotEmpty && !isTaiwanTaxIdFormat(sellerTaxId)) {
      warnings.add('AI 統一編號格式不符，已保持空白。');
      sellerTaxId = '';
    } else if (sellerTaxId.isNotEmpty &&
        !hasValidTaiwanTaxIdChecksum(sellerTaxId)) {
      warnings.add('AI 統一編號校驗未通過，已保持空白。');
      sellerTaxId = '';
    }

    var invoiceDate = _text(json['invoiceDate']);
    if (invoiceDate.isNotEmpty && !_isIsoDate(invoiceDate)) {
      warnings.add('AI 日期格式或日期值不正確，已保持空白。');
      invoiceDate = '';
    }

    var invoiceTime = _text(json['invoiceTime']);
    if (invoiceTime.isNotEmpty &&
        !RegExp(r'^(?:[01]\d|2[0-3]):[0-5]\d(?::[0-5]\d)?$')
            .hasMatch(invoiceTime)) {
      warnings.add('AI 時間格式不正確，已保持空白。');
      invoiceTime = '';
    }

    final rawLineItems = json['lineItems'];
    final lineItems = rawLineItems is List
        ? rawLineItems
            .whereType<Map>()
            .map(
              (item) => GeminiInvoiceReviewLineItem.fromJson(
                Map<String, Object?>.from(item.cast<String, Object?>()),
              ),
            )
            .where((item) => !item.isBlank)
            .toList(growable: false)
        : const <GeminiInvoiceReviewLineItem>[];

    final rawConfidence = json['confidence'];
    final confidence = <GeminiInvoiceReviewField, double>{};
    if (rawConfidence is Map) {
      final values = Map<String, Object?>.from(
        rawConfidence.cast<String, Object?>(),
      );
      for (final field in GeminiInvoiceReviewField.values) {
        final value = _confidence(values[field.name]);
        if (value != null) confidence[field] = value;
      }
    }

    final invoiceTimeConfidence =
        confidence[GeminiInvoiceReviewField.invoiceTime] ?? 0;
    if (invoiceTime.endsWith(':00') && invoiceTimeConfidence < 0.99) {
      warnings.add('AI 秒數為 00 且未達近乎確定可信度，為避免補零誤判已保持時間空白。');
      invoiceTime = '';
    }

    final totalAmount = _nonNegativeNumber(json['totalAmount']);
    if (json['totalAmount'] != null && totalAmount == null) {
      warnings.add('AI 總金額無效，已保持空白。');
    }

    final candidate = GeminiInvoiceReviewCandidate(
      invoiceNumber: invoiceNumber,
      invoicePeriod: _normalizeInvoicePeriod(json['invoicePeriod']),
      randomCode: randomCode,
      sellerTaxId: sellerTaxId,
      invoiceDate: invoiceDate,
      invoiceTime: invoiceTime,
      merchantName: _text(json['merchantName']),
      totalAmount: totalAmount,
      lineItems: List<GeminiInvoiceReviewLineItem>.unmodifiable(lineItems),
      confidence: Map<GeminiInvoiceReviewField, double>.unmodifiable(confidence),
      warnings: List<String>.unmodifiable(
        warnings.map((value) => value.trim()).where((value) => value.isNotEmpty),
      ),
    );
    _latestParsedCandidate = candidate;
    return candidate;
  }

  Map<String, Object?> toSafeSummary() {
    return <String, Object?>{
      'hasInvoiceNumber': invoiceNumber.isNotEmpty,
      'hasInvoicePeriod': invoicePeriod.isNotEmpty,
      'hasRandomCode': randomCode.isNotEmpty,
      'hasSellerTaxId': sellerTaxId.isNotEmpty,
      'hasInvoiceDate': invoiceDate.isNotEmpty,
      'hasInvoiceTime': invoiceTime.isNotEmpty,
      'hasMerchantName': merchantName.isNotEmpty,
      'hasTotalAmount': totalAmount != null,
      'lineItemCount': lineItems.length,
      'warningCount': warnings.length,
      'usedNetwork': usedNetwork,
      'requiresUserReview': requiresUserReview,
      'canCreateFormalRecord': canCreateFormalRecord,
    };
  }
}

String _text(Object? value) => value?.toString().trim() ?? '';

String _compactInvoiceNumber(Object? value) => _text(value)
    .toUpperCase()
    .replaceAll(RegExp(r'[^A-Z0-9]'), '');

String _normalizeInvoicePeriod(Object? value) {
  final raw = _text(value);
  if (raw.isEmpty) return '';
  final compact = raw.replaceAll(RegExp(r'\s+'), '');

  final full = RegExp(r'^(\d{2,3})(\d{2})-(\d{2,3})(\d{2})$')
      .firstMatch(compact);
  if (full != null) {
    final startYear = int.parse(full.group(1)!);
    final startMonth = int.parse(full.group(2)!);
    final endYear = int.parse(full.group(3)!);
    final endMonth = int.parse(full.group(4)!);
    if (startYear == endYear &&
        startYear >= 80 &&
        startYear <= 200 &&
        startMonth >= 1 &&
        endMonth <= 12 &&
        startMonth <= endMonth) {
      return '$startYear年$startMonth-$endMonth月份';
    }
  }

  final short = RegExp(r'^(\d{2,3})(\d{2})-(\d{2})$').firstMatch(compact);
  if (short != null) {
    final year = int.parse(short.group(1)!);
    final startMonth = int.parse(short.group(2)!);
    final endMonth = int.parse(short.group(3)!);
    if (year >= 80 &&
        year <= 200 &&
        startMonth >= 1 &&
        endMonth <= 12 &&
        startMonth <= endMonth) {
      return '$year年$startMonth-$endMonth月份';
    }
  }

  final compactBimonthly =
      RegExp(r'^(\d{2,3})(\d{2})(\d{2})$').firstMatch(compact);
  if (compactBimonthly != null) {
    final year = int.parse(compactBimonthly.group(1)!);
    final startMonth = int.parse(compactBimonthly.group(2)!);
    final endMonth = int.parse(compactBimonthly.group(3)!);
    final canonicalPair = startMonth >= 1 &&
        startMonth <= 11 &&
        startMonth.isOdd &&
        endMonth == startMonth + 1;
    if (year >= 80 && year <= 200 && canonicalPair) {
      return '$year年$startMonth-$endMonth月份';
    }
  }

  return raw;
}

String _digits(Object? value) =>
    _text(value).replaceAll(RegExp(r'[^0-9]'), '');

double? _nonNegativeNumber(Object? value) {
  final parsed = value is num ? value.toDouble() : double.tryParse(_text(value));
  if (parsed == null || !parsed.isFinite || parsed < 0) return null;
  return parsed;
}

double? _confidence(Object? value) {
  final parsed = _nonNegativeNumber(value);
  if (parsed == null) return null;
  return parsed.clamp(0, 1).toDouble();
}

List<String> _stringList(Object? value) {
  if (value is! List) return const <String>[];
  return value
      .map((item) => _text(item))
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}

bool _isIsoDate(String value) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
  if (match == null) return false;
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final parsed = DateTime.utc(year, month, day);
  return parsed.year == year && parsed.month == month && parsed.day == day;
}
