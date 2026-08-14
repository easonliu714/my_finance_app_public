import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'taiwan_tax_id.dart';
import 'traditional_invoice_ocr_review.dart';

class LocalOcrTextLine {
  const LocalOcrTextLine({
    required this.text,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final String text;
  final double left;
  final double top;
  final double right;
  final double bottom;

  double get width => (right - left).abs();
  double get height => (bottom - top).abs();
  double get centerX => (left + right) / 2;
}

class LocalOcrTextDocument {
  const LocalOcrTextDocument({
    required this.fullText,
    required this.lines,
    this.positionedLines = const <LocalOcrTextLine>[],
  });

  final String fullText;
  final List<String> lines;
  final List<LocalOcrTextLine> positionedLines;
}

abstract class LocalOcrTextEngine {
  Future<LocalOcrTextDocument> recognize(String localReference);
}

class GoogleMlKitChineseTextEngine implements LocalOcrTextEngine {
  const GoogleMlKitChineseTextEngine();

  @override
  Future<LocalOcrTextDocument> recognize(String localReference) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.chinese);
    try {
      final input = InputImage.fromFilePath(localReference);
      final positionedLines = <LocalOcrTextLine>[
        for (final block in (await recognizer.processImage(input)).blocks)
          for (final line in block.lines)
            if (line.text.trim().isNotEmpty)
              LocalOcrTextLine(
                text: line.text.trim(),
                left: line.boundingBox.left,
                top: line.boundingBox.top,
                right: line.boundingBox.right,
                bottom: line.boundingBox.bottom,
              ),
      ];
      return LocalOcrTextDocument(
        fullText: positionedLines.map((line) => line.text).join('\n'),
        lines: List<String>.unmodifiable(
          positionedLines.map((line) => line.text),
        ),
        positionedLines: List<LocalOcrTextLine>.unmodifiable(positionedLines),
      );
    } finally {
      await recognizer.close();
    }
  }
}

class GoogleMlKitTraditionalInvoiceRecognizer
    implements LocalTraditionalInvoiceRecognizer {
  const GoogleMlKitTraditionalInvoiceRecognizer({
    this.engine = const GoogleMlKitChineseTextEngine(),
    this.parser = const TraditionalInvoiceTextParser(),
  });

  final LocalOcrTextEngine engine;
  final TraditionalInvoiceTextParser parser;

  @override
  Future<TraditionalInvoiceOcrRecognition> recognizeLocalImage(
    String localReference,
  ) async {
    final reference = localReference.trim();
    if (reference.isEmpty) {
      throw ArgumentError.value(localReference, 'localReference');
    }
    final document = await engine.recognize(reference);
    return parser.parse(document);
  }
}

class TraditionalSellerTaxIdEvidence {
  const TraditionalSellerTaxIdEvidence({
    required this.value,
    required this.source,
    required this.checksumValid,
    required this.strongContext,
  });

  final String value;
  final String source;
  final bool checksumValid;
  final bool strongContext;

  bool get acceptedForLive =>
      isTaiwanTaxIdFormat(value) && checksumValid && strongContext;
}

bool hasStrongElectronicInvoiceSemanticEvidence(List<String> rawLines) {
  final lines = rawLines
      .map((line) => line.replaceAll(RegExp(r'\s+'), '').toUpperCase())
      .where((line) => line.isNotEmpty)
      .toList(growable: false);
  if (lines.any((line) => line.contains('電子發票證明聯'))) return true;
  final hasElectronicLabel = lines.any((line) => line.contains('電子發票'));
  if (!hasElectronicLabel) return false;
  var supportingSignals = 0;
  if (lines.any((line) => line.contains('隨機碼'))) supportingSignals += 1;
  if (lines.any((line) => line.contains('賣方'))) supportingSignals += 1;
  if (lines.any((line) => line.contains('買方'))) supportingSignals += 1;
  if (lines.any((line) => line.contains('QR'))) supportingSignals += 1;
  return supportingSignals >= 2;
}

TraditionalSellerTaxIdEvidence? extractTraditionalSellerTaxIdEvidence(
  List<String> rawLines, {
  String? invoiceNumber,
  List<LocalOcrTextLine> positionedLines = const <LocalOcrTextLine>[],
}) {
  final lines = rawLines
      .map((line) => line.replaceAll(RegExp(r'\s+'), ' ').trim())
      .where((line) => line.isNotEmpty)
      .toList(growable: false);

  final explicit = RegExp(
    r'(?:賣方(?:統編|統一編號)?|統編|統一編號)\s*[:：.]?\s*([0-9０-９OIl|]{8})',
    caseSensitive: false,
  );
  for (final line in lines) {
    final match = explicit.firstMatch(line);
    if (match == null) continue;
    final value = _normalizeEightDigits(match.group(1)!);
    if (!isTaiwanTaxIdFormat(value)) continue;
    return TraditionalSellerTaxIdEvidence(
      value: value,
      source: 'explicit_label',
      checksumValid: hasValidTaiwanTaxIdChecksum(value),
      strongContext: true,
    );
  }

  final noPattern = RegExp(
    r'^\s*NO\.?\s*[:：.]?\s*([0-9０-９OIl|]{8})\s*$',
    caseSensitive: false,
  );
  for (var index = 0; index < lines.length && index < 10; index += 1) {
    final match = noPattern.firstMatch(lines[index]);
    if (match == null) continue;
    final value = _normalizeEightDigits(match.group(1)!);
    if (!isTaiwanTaxIdFormat(value) ||
        !hasValidTaiwanTaxIdChecksum(value) ||
        !_hasMerchantHeaderContext(lines, index)) {
      continue;
    }
    return TraditionalSellerTaxIdEvidence(
      value: value,
      source: 'contextual_no_header',
      checksumValid: true,
      strongContext: true,
    );
  }

  return _extractPositionalHeaderTaxId(
    lines,
    invoiceNumber: invoiceNumber,
    positionedLines: positionedLines,
  );
}

TraditionalSellerTaxIdEvidence? _extractPositionalHeaderTaxId(
  List<String> lines, {
  required String? invoiceNumber,
  required List<LocalOcrTextLine> positionedLines,
}) {
  if (lines.isEmpty || positionedLines.length != lines.length) return null;
  final normalizedInvoice = (invoiceNumber ?? '')
      .replaceAll(RegExp(r'[^A-Z0-9]'), '')
      .toUpperCase();
  final invoicePattern = RegExp(
    r'^\s*[A-Z]{2}[\s-]?\d{8}\s*$',
    caseSensitive: false,
  );
  var invoiceIndex = -1;
  for (var index = 0; index < lines.length; index += 1) {
    final normalizedLine = lines[index]
        .replaceAll(RegExp(r'[^A-Z0-9]'), '')
        .toUpperCase();
    if ((normalizedInvoice.isNotEmpty && normalizedLine == normalizedInvoice) ||
        invoicePattern.hasMatch(lines[index])) {
      invoiceIndex = index;
      break;
    }
  }
  if (invoiceIndex < 0) return null;

  final invoiceLine = positionedLines[invoiceIndex];
  final candidatePattern = RegExp(r'^\s*([0-9０-９OIl|]{8})\s*$');
  final stopPattern = RegExp(
    r'(?:交易明細|商品明細|消費明細|銷售明細|發票明細|交易內容|品項|項目|總計|合計|小計)',
  );
  final excludedContextPattern = RegExp(
    r'(?:買方|買受人|隨機碼|會員|訂單|交易編號|機號|機台|收銀機|電話|TEL|PHONE|序號)',
    caseSensitive: false,
  );
  final invoiceDigits = normalizedInvoice.length == 10
      ? normalizedInvoice.substring(2)
      : '';
  final accepted = <String, int>{};
  final end = (invoiceIndex + 7).clamp(0, lines.length);
  for (var index = invoiceIndex + 1; index < end; index += 1) {
    final line = lines[index].trim();
    if (stopPattern.hasMatch(line)) break;
    final match = candidatePattern.firstMatch(line);
    if (match == null) continue;
    final previous = index > 0 ? lines[index - 1] : '';
    if (excludedContextPattern.hasMatch(previous)) continue;
    final value = _normalizeEightDigits(match.group(1)!);
    if (value == invoiceDigits ||
        !isTaiwanTaxIdFormat(value) ||
        !hasValidTaiwanTaxIdChecksum(value)) {
      continue;
    }
    final candidateLine = positionedLines[index];
    final invoiceHeight = invoiceLine.height <= 0 ? 1.0 : invoiceLine.height;
    final verticalGap = candidateLine.top - invoiceLine.bottom;
    if (verticalGap < -invoiceHeight * 0.3 ||
        verticalGap > invoiceHeight * 14) {
      continue;
    }
    final horizontalTolerance =
        (invoiceLine.width + candidateLine.width).clamp(1.0, double.infinity);
    if ((candidateLine.centerX - invoiceLine.centerX).abs() >
        horizontalTolerance) {
      continue;
    }
    accepted[value] = index;
  }
  if (accepted.length != 1) return null;
  return TraditionalSellerTaxIdEvidence(
    value: accepted.keys.single,
    source: 'positional_header_8digit',
    checksumValid: true,
    strongContext: true,
  );
}

String _normalizeEightDigits(String value) {
  const fullWidth = '０１２３４５６７８９';
  const ascii = '0123456789';
  var normalized = value
      .replaceAll(RegExp(r'[ＯｏO]'), '0')
      .replaceAll(RegExp(r'[ＩIl|]'), '1');
  for (var index = 0; index < fullWidth.length; index += 1) {
    normalized = normalized.replaceAll(fullWidth[index], ascii[index]);
  }
  return normalized.replaceAll(RegExp(r'[^0-9]'), '');
}

bool _hasMerchantHeaderContext(List<String> lines, int index) {
  if (index <= 0 || index > 8) return false;
  final start = index >= 3 ? index - 3 : 0;
  final contextLines = lines.sublist(start, index);
  final invoiceIdentity = RegExp(
    r'^\s*[A-Z]{2}[\s-]?\d{8}\s*$',
    caseSensitive: false,
  );
  final strongMerchantSignal = RegExp(
    r'(?:店|商行|公司|有限公司|股份有限公司|門市|餐廳|茶|咖啡|超商|便利商店|市場|館|坊|社|中心)$',
  );
  final genericHeader = RegExp(
    r'^(?:交易明細|商品明細|消費明細|銷售明細|發票明細|交易內容|商品|品項|項目|明細)$',
  );
  final nonMerchantSignal = RegExp(
    r'(?:電子發票|發票證明聯|統一發票|收銀機|電話|地址|總計|合計|應付|實付|總額|小計|收現|現金|找零|統計)',
    caseSensitive: false,
  );

  for (final rawLine in contextLines.reversed) {
    final line = rawLine.trim();
    if (line.isEmpty ||
        invoiceIdentity.hasMatch(line) ||
        genericHeader.hasMatch(line) ||
        nonMerchantSignal.hasMatch(line)) {
      continue;
    }
    final cjkCount = RegExp(r'[\u3400-\u9FFF]').allMatches(line).length;
    if (cjkCount >= 2 && strongMerchantSignal.hasMatch(line)) {
      return true;
    }
  }
  return false;
}

class TraditionalInvoiceTextParser {
  const TraditionalInvoiceTextParser();

  static final RegExp _invoiceNumberPattern = RegExp(
    r'\b([A-Z]{2})[\s-]?(\d{8})\b',
    caseSensitive: false,
  );
  static final RegExp _gregorianDatePattern = RegExp(
    r'\b(20\d{2})[\s./年-]+(\d{1,2})[\s./月-]+(\d{1,2})(?:日)?\b',
  );
  static final RegExp _rocDatePattern = RegExp(
    r'\b(\d{2,3})[\s./年-]+(\d{1,2})[\s./月-]+(\d{1,2})(?:日)?(?!\s*月(?:份)?)\b',
  );
  static final RegExp _periodPattern = RegExp(
    r'(?:中華民國)?\s*(\d{2,3})年\s*(\d{1,2})\s*[-~～至]\s*(\d{1,2})月(?:份)?',
  );
  static final RegExp _fuzzyNumericDatePattern = RegExp(
    r'\b([0-9B]{4})[\s./-]+([0-9B]{1,2})[\s./-]+([0-9B]{1,2})\b',
    caseSensitive: false,
  );
  static final RegExp _amountPattern = RegExp(
    r'(?:NT\$|TWD|\$)?\s*([0-9]{1,3}(?:,[0-9]{3})*(?:\.[0-9]{1,2})?|[0-9]+(?:\.[0-9]{1,2})?)',
    caseSensitive: false,
  );
  static final RegExp _explicitCashAmountPattern = RegExp(
    r'^(?:收現|現金|現)\s*[:：]\s*(?:NT\$|TWD|\$)?\s*([0-9]{1,3}(?:,[0-9]{3})*(?:\.[0-9]{1,2})?|[0-9]+(?:\.[0-9]{1,2})?)\s*(?:元)?$',
    caseSensitive: false,
  );
  static final RegExp _receiptSerialPattern = RegExp(
    r'^(?:NO\.?|NO[:：]|編號[:：]?)\s*[A-Z0-9-]{4,}$',
    caseSensitive: false,
  );
  static final RegExp _phonePattern = RegExp(
    r'(?:電話|TEL|PHONE)\s*[:：.]?\s*[0-9()\s-]{6,}',
    caseSensitive: false,
  );
  static final RegExp _addressPattern = RegExp(
    r'(?:地址[:：]?)|(?:[縣市].*[區鄉鎮市])|(?:[路街巷弄]\s*\d+\s*號?)',
  );
  static final RegExp _merchantSignalPattern = RegExp(
    r'(?:店|商行|公司|門市|餐廳|茶|咖啡|超商|便利商店|市場|館|坊|社)$',
  );
  static final RegExp _itemPattern = RegExp(
    r'(?:X|×)\s*\d+(?:\.\d+)?',
    caseSensitive: false,
  );

  TraditionalInvoiceOcrRecognition parse(LocalOcrTextDocument document) {
    final normalizedLines = document.lines
        .map((line) => line.replaceAll(RegExp(r'\s+'), ' ').trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    final searchable = <String>[document.fullText, ...normalizedLines]
        .join('\n')
        .toUpperCase();

    final invoiceNumber = _parseInvoiceNumber(searchable);
    final taxEvidence = extractTraditionalSellerTaxIdEvidence(
      normalizedLines,
      invoiceNumber: invoiceNumber,
      positionedLines: document.positionedLines,
    );
    final sellerTaxId = taxEvidence?.value;
    final invoiceDate = _parseDate(searchable);
    final totalAmount = _parseTotalAmount(normalizedLines);
    final sellerName = _parseSellerName(
      lines: normalizedLines,
      invoiceNumber: invoiceNumber,
    );

    final warnings = <TraditionalInvoiceOcrField, List<String>>{
      if (invoiceNumber == null)
        TraditionalInvoiceOcrField.invoiceNumber: const <String>[
          '未可靠辨識發票號碼，請人工輸入。',
        ],
      if (sellerTaxId == null)
        TraditionalInvoiceOcrField.sellerTaxId: const <String>[
          '未取得高可信度賣方統編證據，請人工確認或交由 Gemini 覆核。',
        ]
      else if (taxEvidence?.checksumValid == false)
        TraditionalInvoiceOcrField.sellerTaxId: const <String>[
          '賣方統編格式為 8 碼，但 checksum 未通過，請人工覆核。',
        ],
      if (invoiceDate == null)
        TraditionalInvoiceOcrField.invoiceDate: const <String>[
          '未可靠辨識發票日期，請人工確認。',
        ],
      if (sellerName == null)
        TraditionalInvoiceOcrField.sellerName: const <String>[
          '未可靠辨識商家名稱，可保持空白或人工輸入。',
        ],
      if (totalAmount == null)
        TraditionalInvoiceOcrField.totalAmount: const <String>[
          '未找到帶有總計語意的金額，請人工輸入。',
        ],
    };

    return TraditionalInvoiceOcrRecognition(
      invoiceNumber: invoiceNumber,
      sellerTaxId: sellerTaxId,
      sellerTaxIdSource: taxEvidence?.source ?? '',
      invoiceDate: invoiceDate,
      sellerName: sellerName,
      totalAmount: totalAmount,
      confidence: <TraditionalInvoiceOcrField,
          TraditionalInvoiceOcrConfidence>{
        TraditionalInvoiceOcrField.invoiceNumber: invoiceNumber == null
            ? TraditionalInvoiceOcrConfidence.low
            : TraditionalInvoiceOcrConfidence.high,
        TraditionalInvoiceOcrField.sellerTaxId: sellerTaxId == null
            ? TraditionalInvoiceOcrConfidence.low
            : taxEvidence?.acceptedForLive == true
                ? TraditionalInvoiceOcrConfidence.high
                : TraditionalInvoiceOcrConfidence.medium,
        TraditionalInvoiceOcrField.invoiceDate: invoiceDate == null
            ? TraditionalInvoiceOcrConfidence.low
            : TraditionalInvoiceOcrConfidence.medium,
        TraditionalInvoiceOcrField.sellerName: sellerName == null
            ? TraditionalInvoiceOcrConfidence.low
            : TraditionalInvoiceOcrConfidence.medium,
        TraditionalInvoiceOcrField.totalAmount: totalAmount == null
            ? TraditionalInvoiceOcrConfidence.low
            : TraditionalInvoiceOcrConfidence.medium,
      },
      fieldWarnings: warnings,
      rawText: document.fullText,
      rawLines: List<String>.unmodifiable(document.lines),
    );
  }

  String? _parseInvoiceNumber(String text) {
    final match = _invoiceNumberPattern.firstMatch(text);
    if (match == null) return null;
    return '${match.group(1)!.toUpperCase()}${match.group(2)}';
  }

  DateTime? _parseDate(String text) {
    final normalized = _normalizeNumericDateEvidence(text);
    final gregorian = _gregorianDatePattern.firstMatch(normalized);
    if (gregorian != null) {
      return _safeDate(
        int.parse(gregorian.group(1)!),
        int.parse(gregorian.group(2)!),
        int.parse(gregorian.group(3)!),
      );
    }
    for (final match in _rocDatePattern.allMatches(normalized)) {
      final rocYear = int.parse(match.group(1)!);
      if (rocYear < 80 || rocYear > 200) continue;
      final value = _safeDate(
        rocYear + 1911,
        int.parse(match.group(2)!),
        int.parse(match.group(3)!),
      );
      if (value != null) return value;
    }

    final period = _parseInvoicePeriodContext(normalized);
    if (period == null) return null;
    final fuzzy = _normalizeFuzzyNumericDateEvidence(text);
    for (final match in _fuzzyNumericDatePattern.allMatches(fuzzy)) {
      final rawYear = match.group(1)!;
      final rawMonth = match.group(2)!;
      final rawDay = match.group(3)!;
      final repairedYear = _repairYearFromPeriod(rawYear, period.year);
      if (repairedYear == null) continue;
      final repairedMonth = _repairMonthFromCalendar(rawMonth);
      if (repairedMonth == null) continue;
      final repairedDay = _repairDayFromCalendar(
        rawDay,
        year: repairedYear,
        month: repairedMonth,
      );
      if (repairedDay == null) continue;
      final value = _safeDate(repairedYear, repairedMonth, repairedDay);
      if (value != null) return value;
    }
    return null;
  }

  ({int year, Set<int> months})? _parseInvoicePeriodContext(String text) {
    final match = _periodPattern.firstMatch(text);
    if (match == null) return null;
    final rocYear = int.tryParse(match.group(1)!);
    final startMonth = int.tryParse(match.group(2)!);
    final endMonth = int.tryParse(match.group(3)!);
    if (rocYear == null || rocYear < 80 || rocYear > 200) return null;
    if (startMonth == null || endMonth == null) return null;
    if (startMonth < 1 || endMonth > 12 || startMonth > endMonth) return null;
    return (
      year: rocYear + 1911,
      months: <int>{
        for (var month = startMonth; month <= endMonth; month++) month,
      },
    );
  }

  int? _repairYearFromPeriod(String rawYear, int expectedYear) {
    final expected = expectedYear.toString();
    if (rawYear == expected) return expectedYear;
    if (rawYear.length != expected.length || rawYear[0] != expected[0]) {
      return null;
    }
    var differences = 0;
    for (var index = 0; index < rawYear.length; index += 1) {
      if (rawYear[index] != expected[index]) differences += 1;
    }
    return differences == 1 ? expectedYear : null;
  }

  int? _repairMonthFromCalendar(String rawMonth) {
    final normalizedRaw = rawMonth.padLeft(2, '0');
    final exact = int.tryParse(normalizedRaw);
    if (exact != null && exact >= 1 && exact <= 12) return exact;

    final candidates = <int>{};
    for (var index = 0; index < normalizedRaw.length; index += 1) {
      if (normalizedRaw[index] != '8') continue;
      final repaired = '${normalizedRaw.substring(0, index)}0${normalizedRaw.substring(index + 1)}';
      final value = int.tryParse(repaired);
      if (value != null && value >= 1 && value <= 12) candidates.add(value);
    }
    return candidates.length == 1 ? candidates.single : null;
  }

  int? _repairDayFromCalendar(
    String rawDay, {
    required int year,
    required int month,
  }) {
    final normalizedRaw = rawDay.padLeft(2, '0');
    final exact = int.tryParse(normalizedRaw);
    if (exact != null && _safeDate(year, month, exact) != null) return exact;

    final candidates = <int>{};
    for (var index = 0; index < normalizedRaw.length; index += 1) {
      if (normalizedRaw[index] != '8') continue;
      final repaired = '${normalizedRaw.substring(0, index)}0${normalizedRaw.substring(index + 1)}';
      final value = int.tryParse(repaired);
      if (value == null || value < 1 || value > 31) continue;
      if (_safeDate(year, month, value) != null) candidates.add(value);
    }
    return candidates.length == 1 ? candidates.single : null;
  }

  String _normalizeNumericDateEvidence(String value) {
    return value
        .replaceAll(RegExp(r'[ＯｏO]'), '0')
        .replaceAll(RegExp(r'[ＩIl|]'), '1');
  }

  String _normalizeFuzzyNumericDateEvidence(String value) {
    return _normalizeNumericDateEvidence(value)
        .replaceAll(RegExp(r'[ＢｂB]'), '8');
  }

  double? _parseTotalAmount(List<String> lines) {
    const strongKeywords = <String>[
      '總計',
      '合計',
      '應付',
      '實付',
      '總額',
      'TOTAL',
      'AMOUNTDUE',
    ];
    const secondaryKeywords = <String>['收現', '現金', '統計', '小計'];
    final evidenceLines = <String>[...lines];
    for (var index = 0; index + 1 < lines.length; index += 1) {
      final first = lines[index].replaceAll(RegExp(r'\s+'), '');
      final second = lines[index + 1].replaceAll(RegExp(r'\s+'), '');
      final compactPair = '$first$second'.toUpperCase();
      final splitPaymentLabel =
          (first == '小' && second.startsWith('計')) ||
          (first == '收' && second.startsWith('現')) ||
          (first == '總' && second.startsWith('計')) ||
          (first == '合' && second.startsWith('計'));
      if (splitPaymentLabel &&
          [...strongKeywords, ...secondaryKeywords].any(compactPair.contains)) {
        evidenceLines.add('${lines[index]} ${lines[index + 1]}');
      }
    }

    double? findFor(List<String> keywords) {
      for (final line in evidenceLines.reversed) {
        final compactUpper =
            line.toUpperCase().replaceAll(RegExp(r'\s+'), '');
        if (!keywords.any(compactUpper.contains)) continue;
        final matches = _amountPattern.allMatches(line).toList(growable: false);
        if (matches.isEmpty) continue;
        final raw = matches.last.group(1)?.replaceAll(',', '');
        final value = double.tryParse(raw ?? '');
        if (value != null && value >= 0 && value.isFinite) return value;
      }
      return null;
    }

    double? findExplicitCash() {
      for (final line in lines.reversed) {
        final match = _explicitCashAmountPattern.firstMatch(line.trim());
        if (match == null) continue;
        final value = double.tryParse(match.group(1)!.replaceAll(',', ''));
        if (value != null && value >= 0 && value.isFinite) return value;
      }
      return null;
    }

    return findFor(strongKeywords) ??
        findExplicitCash() ??
        findFor(secondaryKeywords);
  }

  String? _parseSellerName({
    required List<String> lines,
    required String? invoiceNumber,
  }) {
    String? best;
    var bestScore = -1;
    for (var index = 0; index < lines.length && index < 12; index += 1) {
      var value = lines[index].trim();
      value = value.replaceFirst(RegExp(r'^[|｜!]+\s*'), '');
      final upper = value.toUpperCase();
      if (value.length < 2 || value.length > 40) {
        continue;
      }
      if (invoiceNumber != null && upper.contains(invoiceNumber)) {
        continue;
      }
      if (_invoiceNumberPattern.hasMatch(upper)) {
        continue;
      }
      if (_gregorianDatePattern.hasMatch(_normalizeNumericDateEvidence(value)) ||
          _rocDatePattern.hasMatch(_normalizeNumericDateEvidence(value))) {
        continue;
      }
      if (upper.contains('中華民國') || upper.contains('月份')) {
        continue;
      }
      if (upper.contains('電子發票') ||
          upper.contains('發票證明聯') ||
          upper.contains('統一發票') ||
          upper.contains('收銀機') ||
          upper.contains('RECEIPT') ||
          upper.contains('INVOICE')) {
        continue;
      }
      if (_receiptSerialPattern.hasMatch(value) ||
          _phonePattern.hasMatch(value) ||
          _addressPattern.hasMatch(value)) {
        continue;
      }
      if (RegExp(
        r'(?:統編|統一編號)\s*[:：.]?\s*\d{6,10}',
        caseSensitive: false,
      ).hasMatch(value)) {
        continue;
      }
      const paymentWords = <String>[
        '總計',
        '合計',
        '應付',
        '實付',
        '總額',
        '小計',
        '收現',
        '現金',
        '找零',
        '統計',
      ];
      final compactUpper = upper.replaceAll(RegExp(r'\s+'), '');
      if (paymentWords.any(compactUpper.contains)) {
        continue;
      }
      if (value.contains('元') && _amountPattern.hasMatch(value)) {
        continue;
      }
      if (_itemPattern.hasMatch(value)) {
        continue;
      }
      if (_amountPattern.hasMatch(value) &&
          RegExp(r'^[\d\s,.$:-]+$').hasMatch(value)) {
        continue;
      }
      final cjkCount = RegExp(r'[\u3400-\u9FFF]').allMatches(value).length;
      if (cjkCount < 2) {
        continue;
      }
      var score = 1;
      if (index <= 5) score += 1;
      if (_merchantSignalPattern.hasMatch(value)) score += 4;
      if (value.length <= 16) score += 1;
      if (score > bestScore) {
        best = value;
        bestScore = score;
      }
    }
    return bestScore >= 4 ? best : null;
  }

  DateTime? _safeDate(int year, int month, int day) {
    if (year < 2000 || year > 2100) return null;
    try {
      final value = DateTime.utc(year, month, day);
      if (value.year != year || value.month != month || value.day != day) {
        return null;
      }
      return value;
    } on ArgumentError {
      return null;
    }
  }
}
