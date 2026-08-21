enum VoiceTransactionIntent { expense, unknown }

class VoiceTransactionItemCandidate {
  const VoiceTransactionItemCandidate({
    required this.name,
    this.quantity,
  });

  final String name;
  final double? quantity;

  Map<String, Object?> toSafeJson() => <String, Object?>{
        'name': name,
        'quantity': quantity,
      };
}

class VoiceTransactionParseCandidate {
  const VoiceTransactionParseCandidate({
    required this.transcript,
    required this.intent,
    this.merchantCandidate = '',
    this.accountCandidate = '',
    this.amount,
    this.items = const <VoiceTransactionItemCandidate>[],
    this.warnings = const <String>[],
  });

  final String transcript;
  final VoiceTransactionIntent intent;
  final String merchantCandidate;
  final String accountCandidate;
  final double? amount;
  final List<VoiceTransactionItemCandidate> items;
  final List<String> warnings;

  bool get isExpense => intent == VoiceTransactionIntent.expense;
  bool get hasPositiveAmount => amount != null && amount!.isFinite && amount! > 0;

  Map<String, Object?> toSafeJson() => <String, Object?>{
        'intent': intent.name,
        'merchantCandidate': merchantCandidate,
        'accountCandidate': accountCandidate,
        'amount': amount,
        'items': items.map((item) => item.toSafeJson()).toList(),
        'warnings': warnings,
      };
}

class VoiceTransactionReferenceMatcher {
  const VoiceTransactionReferenceMatcher._();

  static String? matchUnique(String rawCandidate, Iterable<String> options) {
    final candidate = _normalize(rawCandidate);
    if (candidate.isEmpty) return null;
    final normalized = <String, String>{};
    for (final raw in options) {
      final value = raw.trim();
      if (value.isEmpty) continue;
      normalized[value] = _normalize(value);
    }

    final exact = normalized.entries
        .where((entry) => entry.value == candidate)
        .map((entry) => entry.key)
        .toList(growable: false);
    if (exact.length == 1) return exact.single;
    if (exact.length > 1) return null;

    final compatible = normalized.entries
        .where((entry) =>
            entry.value.isNotEmpty &&
            (entry.value.contains(candidate) || candidate.contains(entry.value)))
        .map((entry) => entry.key)
        .toList(growable: false);
    return compatible.length == 1 ? compatible.single : null;
  }

  static String _normalize(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[\s·・_\-－—–]'), '')
      .replaceAll('臺', '台');
}

class VoiceTransactionParser {
  const VoiceTransactionParser();

  VoiceTransactionParseCandidate parse(String rawTranscript) {
    final transcript = _normalizeTranscript(rawTranscript);
    final warnings = <String>[];
    if (transcript.isEmpty) {
      return const VoiceTransactionParseCandidate(
        transcript: '',
        intent: VoiceTransactionIntent.unknown,
        warnings: <String>['語句不可空白。'],
      );
    }

    final intent = _parseIntent(transcript);
    final merchant = _parseMerchant(transcript);
    final account = _parseAccount(transcript);
    final amount = _parseAmount(transcript);
    final items = _parseItems(transcript);

    if (intent == VoiceTransactionIntent.unknown) {
      warnings.add('無法確認這是一筆支出，請人工確認交易類型。');
    }
    if (merchant.isEmpty) warnings.add('未辨識到商家。');
    if (account.isEmpty) warnings.add('未辨識到扣款帳戶或支付方式。');
    if (amount == null || !amount.isFinite || amount <= 0) {
      warnings.add('未辨識到有效總金額。');
    }

    return VoiceTransactionParseCandidate(
      transcript: transcript,
      intent: intent,
      merchantCandidate: merchant,
      accountCandidate: account,
      amount: amount,
      items: List<VoiceTransactionItemCandidate>.unmodifiable(items),
      warnings: List<String>.unmodifiable(warnings),
    );
  }

  static VoiceTransactionIntent _parseIntent(String value) {
    final expenseEvidence = RegExp(
      r'(支付|付款|付了|買了|購買|消費|花了|刷卡|結帳)',
    );
    return expenseEvidence.hasMatch(value)
        ? VoiceTransactionIntent.expense
        : VoiceTransactionIntent.unknown;
  }

  static String _parseMerchant(String value) {
    final patterns = <RegExp>[
      RegExp(r'(?:^|[，,。；;]|我)在\s*(.+?)\s*(?=用|以)'),
      RegExp(r'(?:^|[，,。；;])\s*(.+?)\s*(?:消費|結帳)'),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(value);
      final candidate = match?.group(1)?.trim() ?? '';
      if (candidate.isNotEmpty) return candidate;
    }
    return '';
  }

  static String _parseAccount(String value) {
    final patterns = <RegExp>[
      RegExp(r'(?:用|以)\s*(.+?)\s*(?=支付|付款|付了|刷卡|結帳)'),
      RegExp(r'從\s*(.+?)\s*(?=扣款|支付|付款)'),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(value);
      final candidate = match?.group(1)?.trim() ?? '';
      if (candidate.isNotEmpty) return candidate;
    }
    return '';
  }

  static double? _parseAmount(String value) {
    final evidencePatterns = <RegExp>[
      RegExp(r'(?:支付|付款|付了|花了|花費|總共|總計|合計)\s*([0-9]+(?:\.[0-9]+)?)\s*元'),
      RegExp(r'(?:支付|付款|付了|花了|花費|總共|總計|合計)\s*([一二兩三四五六七八九十百]+)\s*元'),
    ];
    for (final pattern in evidencePatterns) {
      final match = pattern.firstMatch(value);
      final raw = match?.group(1);
      if (raw == null) continue;
      final parsed = double.tryParse(raw) ?? _parseChineseNumber(raw)?.toDouble();
      if (parsed != null && parsed.isFinite && parsed > 0) return parsed;
    }

    final numericAmounts = RegExp(r'([0-9]+(?:\.[0-9]+)?)\s*元')
        .allMatches(value)
        .map((match) => double.tryParse(match.group(1) ?? ''))
        .whereType<double>()
        .where((item) => item.isFinite && item > 0)
        .toSet();
    return numericAmounts.length == 1 ? numericAmounts.single : null;
  }

  static List<VoiceTransactionItemCandidate> _parseItems(String value) {
    final marker = RegExp(r'(?:買了|購買了|買|購買)\s*');
    final match = marker.firstMatch(value);
    if (match == null) return const <VoiceTransactionItemCandidate>[];
    var tail = value.substring(match.end).trim();
    tail = tail.split(RegExp(r'[。；;]')).first.trim();
    if (tail.isEmpty) return const <VoiceTransactionItemCandidate>[];

    final segments = tail
        .split(RegExp(r'[、，,]|以及|和'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty);
    final result = <VoiceTransactionItemCandidate>[];
    for (final segment in segments) {
      final parsed = _parseItemSegment(segment);
      if (parsed != null) result.add(parsed);
    }
    return result;
  }

  static VoiceTransactionItemCandidate? _parseItemSegment(String segment) {
    final normalized = segment.trim();
    if (normalized.isEmpty) return null;

    final quantified = RegExp(
      r'^(\d+(?:\.\d+)?|[一二兩三四五六七八九十百]+)\s*(個|杯|份|瓶|包|盒|張|件|條|顆|組|罐)\s*(.+)$',
    ).firstMatch(normalized);
    if (quantified != null) {
      final quantityToken = quantified.group(1) ?? '';
      final name = (quantified.group(3) ?? '').trim();
      final quantity = double.tryParse(quantityToken) ??
          _parseChineseNumber(quantityToken)?.toDouble();
      if (name.isEmpty || quantity == null || !quantity.isFinite || quantity <= 0) {
        return null;
      }
      return VoiceTransactionItemCandidate(name: name, quantity: quantity);
    }

    return VoiceTransactionItemCandidate(name: normalized);
  }

  static int? _parseChineseNumber(String value) {
    if (value.isEmpty) return null;
    const digits = <String, int>{
      '一': 1,
      '二': 2,
      '兩': 2,
      '三': 3,
      '四': 4,
      '五': 5,
      '六': 6,
      '七': 7,
      '八': 8,
      '九': 9,
    };
    if (digits.containsKey(value)) return digits[value];
    if (value == '十') return 10;
    if (value.contains('百')) {
      final parts = value.split('百');
      final hundreds = parts.first.isEmpty ? 1 : digits[parts.first];
      if (hundreds == null) return null;
      final remainder = parts.length > 1 ? _parseChineseNumber(parts[1]) ?? 0 : 0;
      return hundreds * 100 + remainder;
    }
    if (value.contains('十')) {
      final parts = value.split('十');
      final tens = parts.first.isEmpty ? 1 : digits[parts.first];
      if (tens == null) return null;
      final ones = parts.length > 1 && parts[1].isNotEmpty ? digits[parts[1]] : 0;
      if (ones == null) return null;
      return tens * 10 + ones;
    }
    return null;
  }

  static String _normalizeTranscript(String value) => value
      .trim()
      .replaceAll('：', ':')
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'\s*([，、。；])\s*'), r'$1');
}
