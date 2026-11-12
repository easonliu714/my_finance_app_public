import 'package:material_ui/material_ui.dart';

/// Standalone Lab-only PDF candidate search; never a prize or ledger verdict.
enum LabSearchVerdict { matched, notMatched, hold }

class LabSearchResult {
  static const period = '115-07-08';
  static const tier = 'cloud-500';
  static const mode = 'DIAGNOSTIC_ONLY';
  static const expectedPageCount = 87000;
  static const sourceSha256 =
      'f50d0dcebc7497c51ce2eea9da9525232e638fdc4103decc6a8e0a1c1dac5571';

  const LabSearchResult._({
    required this.verdict,
    required this.candidate,
    required this.pagesRead,
    required this.pageCount,
    required this.elapsedMs,
    required this.matchedPage,
    required this.reason,
  });

  final LabSearchVerdict verdict;
  final String candidate;
  final int pagesRead;
  final int pageCount;
  final int elapsedMs;
  final int matchedPage;
  final String reason;

  static LabSearchResult hold({
    required String candidate,
    String reason = 'UNKNOWN_OR_INCOMPLETE',
  }) => LabSearchResult._(
    verdict: LabSearchVerdict.hold,
    candidate: candidate,
    pagesRead: 0,
    pageCount: 0,
    elapsedMs: 0,
    matchedPage: 0,
    reason: reason,
  );

  /// A complete native snapshot is still only a *single-PDF* search result.
  /// Unknown/mismatched metadata is fail-closed, never interpreted as NOT_WIN.
  static LabSearchResult fromProbe({
    required String candidate,
    required Map<String, dynamic> probe,
  }) {
    if (!RegExp(r'^[A-Z]{2}[0-9]{8}$').hasMatch(candidate)) {
      return hold(candidate: candidate, reason: 'CANDIDATE_INVALID');
    }
    if (probe['status'] != 'complete') {
      return hold(candidate: candidate, reason: 'NATIVE_NOT_COMPLETE');
    }
    if (probe['candidate'] != candidate) {
      return hold(candidate: candidate, reason: 'CANDIDATE_MISMATCH');
    }
    if (probe.containsKey('tier') && probe['tier'] != tier) {
      return hold(candidate: candidate, reason: 'OTHER_TIER');
    }
    if (probe.containsKey('period') && probe['period'] != period) {
      return hold(candidate: candidate, reason: 'OTHER_PERIOD');
    }
    if (probe.containsKey('pdf_sha256') &&
        probe['pdf_sha256'] != sourceSha256) {
      return hold(candidate: candidate, reason: 'SOURCE_MISMATCH');
    }
    final matched = probe['matched'];
    final page = probe['matched_page'];
    final read = probe['pages_read'];
    final count = probe['page_count'];
    final elapsed = probe['elapsed_ms'];
    if (matched is! bool ||
        page is! int ||
        read is! int ||
        count is! int ||
        elapsed is! int ||
        count != expectedPageCount ||
        read <= 0 ||
        read > count ||
        elapsed < 0 ||
        (matched ? page < 1 || page > count : page != 0)) {
      return hold(candidate: candidate, reason: 'NATIVE_RESULT_INVALID');
    }
    return LabSearchResult._(
      verdict: matched ? LabSearchVerdict.matched : LabSearchVerdict.notMatched,
      candidate: candidate,
      pagesRead: read,
      pageCount: count,
      elapsedMs: elapsed,
      matchedPage: page,
      reason: 'NONE',
    );
  }

  String get statusLabel {
    switch (verdict) {
      case LabSearchVerdict.matched:
        return '診斷搜尋：找到候選號碼（非正式判定）';
      case LabSearchVerdict.notMatched:
        return '診斷搜尋：此指定 PDF 未找到（非正式未中獎判定）';
      case LabSearchVerdict.hold:
        return '診斷搜尋：HOLD';
    }
  }

  String get explanation {
    switch (verdict) {
      case LabSearchVerdict.matched:
        return '此指定官方 PDF 中找到候選號碼，頁碼：'
            '$matchedPage；尚非正式中獎或過帳。';
      case LabSearchVerdict.notMatched:
        return '在此指定雲端專屬500元 PDF 的搜尋中未找到；'
            '不可推論其他獎別，也不能做正式未中獎判定。';
      case LabSearchVerdict.hold:
        return 'HOLD：失敗、逾時或結果不完整；禁止任何正式判定。原因：$reason';
    }
  }
}

class LabSearchResultCard extends StatelessWidget {
  const LabSearchResultCard({super.key, required this.result});

  final LabSearchResult result;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const ValueKey<String>('lab-search-result'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(result.statusLabel,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(result.explanation),
            const SizedBox(height: 8),
            Text('mode=${LabSearchResult.mode}\n'
                'period=${LabSearchResult.period} tier=${LabSearchResult.tier}\n'
                'source SHA-256 (locally pinned)=${LabSearchResult.sourceSha256}\n'
                'candidate=${result.candidate}\n'
                'pages_read=${result.pagesRead} / page_count=${result.pageCount}'
                ' (二分搜尋取樣，非全頁驗證)\n'
                'elapsed_ms=${result.elapsedMs}'),
            const SizedBox(height: 4),
            const Text('僅供獨立診斷；不查其他獎別、不產生正式 NOT_WIN、不寫入帳本。'),
          ],
        ),
      ),
    );
  }
}
