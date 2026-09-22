import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

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
    });

    try {
      final preferences = await SharedPreferences.getInstance();
      final validator = const OfficialInvoiceAwardDatasetValidator();
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
      if (!mounted) return;
      final dataset = result.dataset;
      setState(() {
        _refreshing = false;
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
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('統一發票中獎檢查')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
                label: Text(_refreshing ? '更新中…' : '手動更新官方中獎資料'),
              ),
              const SizedBox(height: 16),
              Semantics(
                liveRegion: true,
                child: Text(_status),
              ),
              const SizedBox(height: 16),
              const Text(
                '本 App 僅提供本機中獎比對與記帳輔助，不是兌獎、領獎或自動匯款平台。',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
