import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'existing_invoice_award_candidate_repository.dart';
import 'existing_invoice_award_general_batch_matcher.dart';
import 'invoice_award_official_acquisition.dart';
import 'invoice_award_official_dataset.dart';
import 'invoice_award_official_html_parser.dart';
import 'invoice_award_production_refresh_controller.dart';
import 'invoice_award_shared_preferences_lkg_repository.dart';

/// Production manual-refresh surface for the 115年07-08月 live-draw target.
///
/// Only official MOF bytes cross the network boundary. No invoice/accounting
/// identity is uploaded, and this surface has no formal-transaction authority.
class InvoiceAwardProductionPage extends StatefulWidget {
  const InvoiceAwardProductionPage({super.key});

  @override
  State<InvoiceAwardProductionPage> createState() =>
      _InvoiceAwardProductionPageState();
}

class _InvoiceAwardProductionPageState extends State<InvoiceAwardProductionPage> {
  static const _liveDrawPeriod = OfficialInvoiceAwardPeriod(
    rocYear: 115,
    startMonth: 7,
    endMonth: 8,
  );

  final http.Client _httpClient = http.Client();
  bool _refreshing = false;
  String _status = '尚未更新官方 115年07-08月 中獎資料';
  String _scanStatus = '尚未掃描既有正式交易';
  List<ExistingInvoiceAwardGeneralEvaluation> _evaluations =
      const <ExistingInvoiceAwardGeneralEvaluation>[];

  @override
  void dispose() {
    _httpClient.close();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() {
      _refreshing = true;
      _status = '正在向財政部官方來源更新…';
      _scanStatus = '等待官方資料驗證後掃描既有交易…';
    });

    try {
      final preferences = await SharedPreferences.getInstance();
      const validator = OfficialInvoiceAwardDatasetValidator();
      final volatileStore = InMemoryOfficialInvoiceAwardLastKnownGoodStore();
      final coordinator = OfficialInvoiceAwardAcquisitionCoordinator(
        parser: const MinistryOfFinanceGeneralAwardHtmlParser(),
        validator: validator,
        store: volatileStore,
      );
      final service = MinistryOfFinanceGeneralAwardHttpAcquisitionService(
        client: _httpClient,
        coordinator: coordinator,
      );
      final controller = InvoiceAwardProductionRefreshController(
        service: service,
        volatileStore: volatileStore,
        durableRepository: SharedPreferencesOfficialInvoiceAwardLkgRepository(
          preferences,
        ),
        validator: validator,
      );

      final result = await controller.refresh(_liveDrawPeriod);
      final dataset = result.dataset;
      var evaluations = const <ExistingInvoiceAwardGeneralEvaluation>[];
      String scanStatus;
      if (dataset != null) {
        final candidates =
            await ExistingInvoiceAwardCandidateRepository().listCandidates();
        evaluations = const ExistingInvoiceAwardGeneralBatchMatcher().evaluate(
          dataset: dataset,
          candidates: candidates,
        );
        final inPeriod = evaluations
            .where(
              (item) =>
                  item.status !=
                  ExistingInvoiceAwardGeneralEvaluationStatus.outOfPeriod,
            )
            .toList(growable: false);
        final winners = inPeriod.where((item) => item.isWinner).length;
        scanStatus =
            '既有交易候選 ${candidates.length} 筆；'
            '本期可判定 ${inPeriod.length} 筆；'
            '一般獎中獎 $winners 筆。';
      } else {
        scanStatus = '尚無已驗證官方資料，因此未執行既有交易對獎。';
      }

      if (!mounted) return;
      setState(() {
        _refreshing = false;
        _evaluations = evaluations;
        _scanStatus = scanStatus;
        if (result.isSuccess && dataset != null) {
          final fetched = dataset.provenance.fetchedAt.toLocal();
          _status =
              '官方資料已驗證：${dataset.period.id} · '
              '更新 ${fetched.year}-${fetched.month.toString().padLeft(2, '0')}-'
              '${fetched.day.toString().padLeft(2, '0')} '
              '${fetched.hour.toString().padLeft(2, '0')}:'
              '${fetched.minute.toString().padLeft(2, '0')}';
        } else if (dataset != null) {
          _status = '更新失敗；已保留並使用 ${dataset.period.id} 的最後已驗證資料。';
        } else {
          _status = '更新失敗，且目前沒有可用的已驗證官方資料。';
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _refreshing = false;
        _status = '更新失敗；未變更任何既有已驗證資料。';
        _scanStatus = '既有交易掃描未完成；請稍後重新執行授權更新。';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final visibleEvaluations = _evaluations
        .where(
          (item) =>
              item.status !=
              ExistingInvoiceAwardGeneralEvaluationStatus.outOfPeriod,
        )
        .toList(growable: false);

    return Scaffold(
      appBar: AppBar(title: const Text('統一發票中獎檢查')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              '115年07-08月開獎：2026-09-25。只向財政部官方來源取得中獎資料，不上傳發票或記帳內容。',
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _refreshing ? null : _refresh,
              icon: _refreshing
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
              label: Text(_refreshing ? '更新中…' : '授權更新並檢查既有交易'),
            ),
            const SizedBox(height: 16),
            Semantics(liveRegion: true, child: Text(_status)),
            const SizedBox(height: 8),
            Semantics(liveRegion: true, child: Text(_scanStatus)),
            if (visibleEvaluations.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                '既有交易一般獎結果',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              for (final evaluation in visibleEvaluations)
                _ExistingTransactionAwardTile(evaluation: evaluation),
            ],
            const SizedBox(height: 16),
            const Text(
              '雲端發票目前已先參與一般獎比對；雲端專屬獎仍由獨立官方資料路徑處理，完成前不會宣稱雲端專屬獎已確認。',
            ),
            const SizedBox(height: 12),
            const Text(
              '本 App 僅提供本機中獎比對與記帳輔助，不是兌獎、領獎或自動匯款平台。',
            ),
          ],
        ),
      ),
    );
  }
}

class _ExistingTransactionAwardTile extends StatelessWidget {
  const _ExistingTransactionAwardTile({required this.evaluation});

  final ExistingInvoiceAwardGeneralEvaluation evaluation;

  @override
  Widget build(BuildContext context) {
    final candidate = evaluation.candidate;
    final sourceLabel =
        candidate.identitySource == ExistingInvoiceAwardIdentitySource.cloudMetadata
            ? '雲端發票資料'
            : '發票辨識覆核';
    final amount = evaluation.grossAmount;
    final resultText = evaluation.isWinner
        ? '${evaluation.tierLabel} · NT\$${_formatAmount(amount)}'
        : evaluation.status == ExistingInvoiceAwardGeneralEvaluationStatus.invalid
            ? '資料不足，需人工確認'
            : '一般獎未中獎';

    return Card(
      child: ListTile(
        leading: Icon(
          evaluation.isWinner
              ? Icons.celebration_outlined
              : Icons.receipt_long_outlined,
        ),
        title: Text('${candidate.invoiceNumber} · $resultText'),
        subtitle: Text(
          '$sourceLabel · ${candidate.awardPeriod} · '
          '交易 ${candidate.transactionId}',
        ),
      ),
    );
  }
}

String _formatAmount(int value) {
  final digits = value.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}
