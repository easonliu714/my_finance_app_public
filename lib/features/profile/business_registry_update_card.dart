import 'package:flutter/material.dart';

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
  });

  static const Key refreshKey = Key('business_registry_update_refresh');
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
