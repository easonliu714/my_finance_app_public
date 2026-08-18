class InvoiceTotalEvidence {
  const InvoiceTotalEvidence({
    required this.value,
    required this.source,
    required this.priority,
    required this.lineIndex,
  });

  final double value;
  final String source;
  final int priority;
  final int lineIndex;
}

InvoiceTotalEvidence? resolveInvoiceTotalEvidence(List<String> rawLines) {
  if (rawLines.any(
    (line) => line.trim().startsWith('P4_18_5_TOTAL_DECISION_LOCK='),
  )) {
    return null;
  }

  final lines = rawLines
      .map((line) => line.replaceAll(RegExp(r'\s+'), ' ').trim())
      .where((line) => line.isNotEmpty)
      .toList(growable: false);
  final evidence = <InvoiceTotalEvidence>[];

  for (var index = 0; index < lines.length; index += 1) {
    final compact = lines[index].replaceAll(RegExp(r'\s+'), '').toUpperCase();
    final amount = _lastAmount(lines[index]);
    if (amount != null) {
      final classification = _classifyTotalLabel(compact);
      if (classification != null) {
        evidence.add(
          InvoiceTotalEvidence(
            value: amount,
            source: classification.$1,
            priority: classification.$2,
            lineIndex: index,
          ),
        );
      }
    }

    if (index == 0) continue;
    final previous = lines[index - 1]
        .replaceAll(RegExp(r'\s+'), '')
        .toUpperCase();
    final prefix = _splitTotalPrefix(previous, compact);
    if (prefix == null) continue;
    final reconstructed = '$prefix$compact';
    final reconstructedAmount = _lastAmount(reconstructed);
    if (reconstructedAmount == null) continue;
    final classification = _classifyTotalLabel(reconstructed);
    if (classification == null) continue;
    evidence.add(
      InvoiceTotalEvidence(
        value: reconstructedAmount,
        source: '${classification.$1}_split_reconstruction',
        priority: classification.$2,
        lineIndex: index,
      ),
    );
  }

  if (evidence.isEmpty) return null;
  evidence.sort((left, right) {
    final priority = right.priority.compareTo(left.priority);
    if (priority != 0) return priority;
    return right.lineIndex.compareTo(left.lineIndex);
  });
  return evidence.first;
}

(String, int)? _classifyTotalLabel(String compact) {
  if (compact.contains('總計') ||
      compact.contains('合計') ||
      compact.contains('總額') ||
      compact.contains('TOTAL') ||
      compact.contains('AMOUNTDUE')) {
    return ('total_label', 40);
  }
  if (compact.contains('小計')) return ('subtotal_label', 35);
  if (compact.contains('應付') || compact.contains('實付')) {
    return ('payable_label', 30);
  }
  if (RegExp(r'^(?:收現|現金|現)[:：]').hasMatch(compact)) {
    return ('cash_tender_label', 10);
  }
  return null;
}

String? _splitTotalPrefix(String previous, String current) {
  if (!current.startsWith('計')) return null;
  if (previous == '總' || previous == '合') return previous;
  if (previous.startsWith('小') && previous.length <= 2) return '小';
  return null;
}

double? _lastAmount(String value) {
  final matches = RegExp(
    r'(?:NT\$|TWD|\$)?([0-9]{1,3}(?:,[0-9]{3})*(?:\.[0-9]{1,2})?|[0-9]+(?:\.[0-9]{1,2})?)',
    caseSensitive: false,
  ).allMatches(value).toList(growable: false);
  if (matches.isEmpty) return null;
  final raw = matches.last.group(1)?.replaceAll(',', '') ?? '';
  final parsed = double.tryParse(raw);
  if (parsed == null || !parsed.isFinite || parsed < 0) return null;
  return parsed;
}
