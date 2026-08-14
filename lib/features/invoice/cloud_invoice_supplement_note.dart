class CloudInvoiceSupplementNote {
  const CloudInvoiceSupplementNote._();

  static const startMarker = '[未列入發票明細補充]';
  static const endMarker = '[/未列入發票明細補充]';

  static final RegExp _blockPattern = RegExp(
    '${RegExp.escape(startMarker)}\\s*([\\s\\S]*?)\\s*${RegExp.escape(endMarker)}',
  );

  static String extract(String note) {
    final match = _blockPattern.firstMatch(note);
    return match?.group(1)?.trim() ?? '';
  }

  static String replace(String note, String supplement) {
    final base = note.replaceAll(_blockPattern, '').trim();
    final cleaned = supplement.trim();
    if (cleaned.isEmpty) return base;
    final block = '$startMarker\n$cleaned\n$endMarker';
    return base.isEmpty ? block : '$base\n\n$block';
  }
}
