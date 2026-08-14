import 'package:flutter/material.dart';

import 'apk_field_validation_checklist.dart';

class ApkFieldValidationChecklistCard extends StatelessWidget {
  const ApkFieldValidationChecklistCard({
    super.key,
    this.checklist = const ApkFieldValidationChecklist(),
  });

  static const Key cardKey = Key('apk_field_validation_checklist_card');
  static const Key summaryKey = Key('apk_field_validation_summary');

  final ApkFieldValidationChecklist checklist;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: cardKey,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.fact_check_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    ApkFieldValidationCopy.title,
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                _ValidationChip(label: checklist.canRelease ? '可進入驗證' : '阻擋中'),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              checklist.canRelease ? ApkFieldValidationCopy.releaseReady : ApkFieldValidationCopy.releaseBlocked,
              key: summaryKey,
            ),
            const SizedBox(height: 8),
            Text('通過：${checklist.passCount}，警告：${checklist.warningCount}，阻擋：${checklist.requiredFailCount}'),
            const SizedBox(height: 12),
            for (final item in checklist.items) _ValidationItemTile(item: item),
          ],
        ),
      ),
    );
  }
}

class _ValidationItemTile extends StatelessWidget {
  const _ValidationItemTile({required this.item});

  final ApkFieldValidationItem item;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(_statusIcon(item.status)),
      title: Text(item.title),
      subtitle: Text('${_severityLabel(item.severity)}｜${item.description}'),
      trailing: _ValidationChip(label: _statusLabel(item.status)),
    );
  }

  static IconData _statusIcon(ApkFieldValidationStatus status) {
    switch (status) {
      case ApkFieldValidationStatus.pass:
        return Icons.check_circle_outline;
      case ApkFieldValidationStatus.warning:
        return Icons.warning_amber_outlined;
      case ApkFieldValidationStatus.fail:
        return Icons.error_outline;
      case ApkFieldValidationStatus.notApplicable:
        return Icons.remove_circle_outline;
    }
  }
}

class _ValidationChip extends StatelessWidget {
  const _ValidationChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.secondary;
    return Chip(
      label: Text(label),
      side: BorderSide(color: color),
      labelStyle: TextStyle(color: color, fontWeight: FontWeight.w800),
    );
  }
}

String _statusLabel(ApkFieldValidationStatus status) {
  switch (status) {
    case ApkFieldValidationStatus.pass:
      return '通過';
    case ApkFieldValidationStatus.warning:
      return '警告';
    case ApkFieldValidationStatus.fail:
      return '失敗';
    case ApkFieldValidationStatus.notApplicable:
      return '不適用';
  }
}

String _severityLabel(ApkFieldValidationSeverity severity) {
  switch (severity) {
    case ApkFieldValidationSeverity.required:
      return '必要';
    case ApkFieldValidationSeverity.recommended:
      return '建議';
    case ApkFieldValidationSeverity.optional:
      return '選用';
  }
}
