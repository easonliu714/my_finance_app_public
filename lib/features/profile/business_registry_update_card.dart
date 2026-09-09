import 'package:flutter/material.dart';

import '../../app_build_metadata.dart';

import '../merchant/business_registry_pack.dart';
import '../merchant/business_registry_repository.dart';

class BusinessRegistryUpdateCard extends StatelessWidget {
  const BusinessRegistryUpdateCard({
    super.key,
    required this.snapshot,
    required this.loading,
    required this.updating,
    required this.distributionConfigured,
    required this.statusMessage,
    required this.onRefresh,
    this.onLookupOfficialDetail,
  });

  static const Key refreshKey = Key('business_registry_update_refresh');
  static const Key appVersionKey = Key('business_registry_app_version');
  static const Key versionKey = Key('business_registry_update_version');
  static const Key dataDateKey = Key('business_registry_update_data_date');
  static const Key coverageKey = Key('business_registry_update_coverage');
  static const Key statusKey = Key('business_registry_update_status');

  final BusinessRegistrySnapshotInfo? snapshot;
  final bool loading;
  final bool updating;
  final bool distributionConfigured;
  final String statusMessage;
  final VoidCallback? onRefresh;
  final Future<BusinessRegistryOfficialDetailLookupResult> Function(String)?
      onLookupOfficialDetail;

  @override
  Widget build(BuildContext context) {
    final installed = snapshot;
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(
                  Icons.business_outlined,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        '公司行號資料',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        '官方登記資料只用於賣方統編的本機佐證，不會覆寫正式商家名稱或發票原文。',
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (loading)
              const LinearProgressIndicator()
            else ...<Widget>[
              _InfoRow(
                label: 'App 版本',
                value: AppBuildMetadata.appVersion,
                valueKey: appVersionKey,
              ),
              _InfoRow(
                label: '已安裝版本',
                value: installed?.version ?? '尚未安裝',
                valueKey: versionKey,
              ),
              _InfoRow(
                label: '官方資料日期',
                value: installed?.sourceDataDate.isNotEmpty == true
                    ? installed!.sourceDataDate
                    : '—',
                valueKey: dataDateKey,
              ),
              _InfoRow(
                label: '涵蓋範圍',
                value: _coverageLabel(installed?.coverage ?? ''),
                valueKey: coverageKey,
              ),
              if (installed != null) ...<Widget>[
                const SizedBox(height: 4),
                Text(
                  '來源：${installed.sourceDataset}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ],
            if (statusMessage.trim().isNotEmpty) ...<Widget>[
              const SizedBox(height: 10),
              Text(
                statusMessage,
                key: statusKey,
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (!distributionConfigured) ...<Widget>[
              const SizedBox(height: 10),
              Text(
                '此建置尚未設定公司行號資料發布端點；目前已安裝的本機資料仍可離線查詢。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 14),
            FilledButton.tonalIcon(
              key: refreshKey,
              onPressed: updating || !distributionConfigured ? null : onRefresh,
              icon: updating
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync_outlined),
              label: Text(updating ? '正在更新公司行號資料…' : '更新公司行號資料'),
            ),
            const SizedBox(height: 8),
            const Text(
              '更新會先下載到暫存檔並驗證版本、大小與 SHA-256；完整驗證成功後才原子切換。失敗時保留上一版資料，且不影響發票覆核。',
            ),
            const SizedBox(height: 16),
            BusinessRegistryOfficialDetailLookupPanel(
              enabled: installed != null,
              onLookup: onLookupOfficialDetail,
            ),
          ],
        ),
      ),
    );
  }

  static String _coverageLabel(String coverage) {
    switch (coverage) {
      case BusinessRegistryPack.nationwideCoverage:
        return '全台公司／商業／分公司';
      case BusinessRegistryPack.validationSubsetCoverage:
        return '實機驗證子集';
      case '':
        return '—';
      default:
        return coverage;
    }
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    required this.valueKey,
  });

  final String label;
  final String value;
  final Key valueKey;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 112,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
          Expanded(child: Text(value, key: valueKey)),
        ],
      ),
    );
  }
}

class BusinessRegistryOfficialDetailLookupPanel extends StatefulWidget {
  const BusinessRegistryOfficialDetailLookupPanel({
    super.key,
    required this.enabled,
    this.onLookup,
  });

  static const Key sellerFieldKey =
      Key('business_registry_official_detail_seller');
  static const Key lookupKey =
      Key('business_registry_official_detail_lookup');
  static const Key resultKey =
      Key('business_registry_official_detail_result');

  final bool enabled;
  final Future<BusinessRegistryOfficialDetailLookupResult> Function(String)?
      onLookup;

  @override
  State<BusinessRegistryOfficialDetailLookupPanel> createState() =>
      _BusinessRegistryOfficialDetailLookupPanelState();
}

class _BusinessRegistryOfficialDetailLookupPanelState
    extends State<BusinessRegistryOfficialDetailLookupPanel> {
  final TextEditingController _controller = TextEditingController();
  BusinessRegistryOfficialDetailLookupResult? _result;
  var _busy = false;
  var _message = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _lookup() async {
    if (_busy) return;
    final callback = widget.onLookup;
    final seller = _controller.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (seller.length != 8) {
      setState(() {
        _result = null;
        _message = '請輸入 8 碼統一編號。';
      });
      return;
    }
    if (!widget.enabled || callback == null) {
      setState(() {
        _result = null;
        _message = '請先下載並安裝官方統編資料。';
      });
      return;
    }
    setState(() {
      _busy = true;
      _message = '';
    });
    try {
      final result = await callback(seller);
      if (!mounted) return;
      setState(() {
        _result = result;
        _message = switch (result.status) {
          BusinessRegistryOfficialDetailLookupStatus.hit => '',
          BusinessRegistryOfficialDetailLookupStatus.notFound =>
            '目前已安裝的官方資料沒有此統編。',
          BusinessRegistryOfficialDetailLookupStatus.detailUnavailable =>
            '目前安裝版本只有核心統編／名稱；請更新至包含完整官方欄位的資料包。',
          BusinessRegistryOfficialDetailLookupStatus.noInstalledRegistry =>
            '請先下載並安裝官方統編資料。',
          BusinessRegistryOfficialDetailLookupStatus.invalidSellerIdentifier =>
            '請輸入 8 碼統一編號。',
        };
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _result = null;
        _message = '本機官方資料查詢失敗；不影響記帳與發票覆核。';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return ExpansionTile(
      initiallyExpanded: false,
      tilePadding: EdgeInsets.zero,
      childrenPadding: EdgeInsets.zero,
      title: const Text(
        '用統編查詢完整官方資料',
        style: TextStyle(fontWeight: FontWeight.w800),
      ),
      subtitle: const Text(
        '只查目前已安裝的 Registry cache；完整官方欄位不會寫入記帳明細。',
      ),
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: TextField(
                key: BusinessRegistryOfficialDetailLookupPanel.sellerFieldKey,
                controller: _controller,
                enabled: !_busy,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: '統一編號',
                  hintText: '例如 31655572',
                ),
                onSubmitted: (_) => _lookup(),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonalIcon(
              key: BusinessRegistryOfficialDetailLookupPanel.lookupKey,
              onPressed: _busy ? null : _lookup,
              icon: _busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.search),
              label: const Text('查詢'),
            ),
          ],
        ),
        if (_message.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(_message),
          ),
        ],
        if (result?.isHit == true) ...<Widget>[
          const SizedBox(height: 12),
          Container(
            key: BusinessRegistryOfficialDetailLookupPanel.resultKey,
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '官方資料日期：${result!.sourceDataDate.isEmpty ? '—' : result.sourceDataDate}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                for (final field in BusinessRegistryEntity.officialFieldOrder)
                  _InfoRow(
                    label: field,
                    value: (result.fields[field] ?? '').trim().isEmpty
                        ? '—'
                        : result.fields[field]!.trim(),
                    valueKey: Key('business_registry_official_detail_$field'),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
