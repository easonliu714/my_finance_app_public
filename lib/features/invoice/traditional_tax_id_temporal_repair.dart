import 'taiwan_tax_id.dart';

const String positionalTaxIdUnverifiedSource =
    'positional_header_8digit_unverified';
const String positionalTaxIdTemporalRepairSource =
    'positional_header_8digit_temporal_repair';
const String positionalTaxIdSingleEightToZeroRule =
    'single_8_to_0_checksum';

class PositionalTaxIdFrameObservation {
  const PositionalTaxIdFrameObservation({
    required this.invoiceNumber,
    required this.rawCandidate,
  });

  final String invoiceNumber;
  final String rawCandidate;
}

class PositionalTaxIdTemporalRepairResult {
  const PositionalTaxIdTemporalRepairResult._({
    required this.repairedValue,
    required this.observations,
    required this.rawCandidates,
    required this.rule,
  });

  const PositionalTaxIdTemporalRepairResult.none()
      : repairedValue = '',
        observations = 0,
        rawCandidates = const <String>[],
        rule = '';

  final String repairedValue;
  final int observations;
  final List<String> rawCandidates;
  final String rule;

  bool get accepted => repairedValue.isNotEmpty && observations >= 2;
}

String? extractUnverifiedPositionalHeaderTaxIdFromLines({
  required List<String> rawLines,
  required String invoiceNumber,
}) {
  final lines = rawLines
      .map((line) => line.replaceAll(RegExp(r'\s+'), ' ').trim())
      .where((line) => line.isNotEmpty)
      .toList(growable: false);
  final invoice = _normalizeInvoiceNumber(invoiceNumber);
  if (invoice.length != 10 || lines.isEmpty) return null;

  var invoiceIndex = -1;
  for (var index = 0; index < lines.length; index += 1) {
    if (_normalizeInvoiceNumber(lines[index]) == invoice) {
      invoiceIndex = index;
      break;
    }
  }
  if (invoiceIndex < 0) return null;

  final candidatePattern = RegExp(r'^\s*([0-9０-９OIl|]{8})\s*$');
  final stopPattern = RegExp(
    r'(?:交易明細|商品明細|消費明細|銷售明細|發票明細|交易內容|品項|項目|總計|合計|小計)',
  );
  final excludedContextPattern = RegExp(
    r'(?:買方|買受人|隨機碼|會員|訂單|交易編號|機號|機台|收銀機|電話|TEL|PHONE|序號)',
    caseSensitive: false,
  );
  final invoiceDigits = invoice.substring(2);
  final candidates = <String>{};
  final end = (invoiceIndex + 7).clamp(0, lines.length);
  for (var index = invoiceIndex + 1; index < end; index += 1) {
    final line = lines[index];
    if (stopPattern.hasMatch(line)) break;
    final match = candidatePattern.firstMatch(line);
    if (match == null) continue;
    final previous = index > 0 ? lines[index - 1] : '';
    if (excludedContextPattern.hasMatch(previous)) continue;
    final value = _normalizeEightDigits(match.group(1)!);
    if (!isTaiwanTaxIdFormat(value) || value == invoiceDigits) continue;
    candidates.add(value);
  }
  return candidates.length == 1 ? candidates.single : null;
}

String? repairSingleEightToZeroTaiwanTaxId(String rawValue) {
  final value = _normalizeEightDigits(rawValue);
  if (!isTaiwanTaxIdFormat(value) || hasValidTaiwanTaxIdChecksum(value)) {
    return null;
  }
  final repaired = <String>{};
  for (var index = 0; index < value.length; index += 1) {
    if (value[index] != '8') continue;
    final candidate =
        '${value.substring(0, index)}0${value.substring(index + 1)}';
    if (hasValidTaiwanTaxIdChecksum(candidate)) repaired.add(candidate);
  }
  return repaired.length == 1 ? repaired.single : null;
}

PositionalTaxIdTemporalRepairResult resolvePositionalTaxIdTemporalRepair({
  required List<PositionalTaxIdFrameObservation> history,
  required String currentInvoiceNumber,
  required String currentRawCandidate,
  int windowSize = 4,
}) {
  final invoice = _normalizeInvoiceNumber(currentInvoiceNumber);
  final current = _normalizeEightDigits(currentRawCandidate);
  if (invoice.isEmpty || !isTaiwanTaxIdFormat(current)) {
    return const PositionalTaxIdTemporalRepairResult.none();
  }

  final observations = <PositionalTaxIdFrameObservation>[
    ...history,
    PositionalTaxIdFrameObservation(
      invoiceNumber: invoice,
      rawCandidate: current,
    ),
  ];
  final recent = observations.length <= windowSize
      ? observations
      : observations.sublist(observations.length - windowSize);
  final sameInvoice = recent
      .where(
        (item) =>
            _normalizeInvoiceNumber(item.invoiceNumber) == invoice &&
            isTaiwanTaxIdFormat(_normalizeEightDigits(item.rawCandidate)),
      )
      .map(
        (item) => PositionalTaxIdFrameObservation(
          invoiceNumber: invoice,
          rawCandidate: _normalizeEightDigits(item.rawCandidate),
        ),
      )
      .toList(growable: false);

  final family = sameInvoice
      .where((item) => _hammingDistance(item.rawCandidate, current) <= 1)
      .toList(growable: false);
  if (family.length < 2) {
    return const PositionalTaxIdTemporalRepairResult.none();
  }

  final targets = <String>{};
  for (final item in family) {
    final repaired = repairSingleEightToZeroTaiwanTaxId(item.rawCandidate);
    if (repaired != null) targets.add(repaired);
  }
  if (targets.length != 1) {
    return const PositionalTaxIdTemporalRepairResult.none();
  }
  final target = targets.single;
  if (family.any((item) => _hammingDistance(item.rawCandidate, target) > 2)) {
    return const PositionalTaxIdTemporalRepairResult.none();
  }

  return PositionalTaxIdTemporalRepairResult._(
    repairedValue: target,
    observations: family.length,
    rawCandidates: List<String>.unmodifiable(
      family.map((item) => item.rawCandidate),
    ),
    rule: positionalTaxIdSingleEightToZeroRule,
  );
}

String _normalizeInvoiceNumber(String value) =>
    value.replaceAll(RegExp(r'[^A-Z0-9]'), '').toUpperCase();

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

int _hammingDistance(String left, String right) {
  if (left.length != right.length) return 999;
  var differences = 0;
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) differences += 1;
  }
  return differences;
}
