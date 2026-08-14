import 'package:flutter/material.dart';

import 'import_mapping_analysis_service.dart';

class ImportMappingConflictReport extends StatelessWidget {
  const ImportMappingConflictReport({super.key, required this.result});

  final ImportMappingAnalysisResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('對應 / 衝突檢查報告', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                const Text('目前只顯示 mapping / conflict report，不會自動新增帳戶、類別或商家，也不會自動修改匯入列。'),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _SummaryChip(label: '缺失帳戶', value: result.summary.missingAccountCount, tone: _ReportTone.error),
                    _SummaryChip(label: '模糊帳戶', value: result.summary.ambiguousAccountCount, tone: _ReportTone.warning),
                    _SummaryChip(label: '類別候選', value: result.summary.unmappedCategoryCount),
                    _SummaryChip(label: '商家候選', value: result.summary.unmappedMerchantCount),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _SectionCard(
          title: '帳戶對應結果',
          emptyMessage: '沒有帳戶欄位需要檢查。',
          children: [for (final reference in result.accountReferences) _AccountReferenceTile(reference: reference)],
        ),
        const SizedBox(height: 12),
        _ValueListSection(title: '類別候選值', values: result.categories, emptyMessage: '沒有類別候選值。'),
        const SizedBox(height: 12),
        _ValueListSection(title: '商家候選值', values: result.merchants, emptyMessage: '沒有商家候選值。'),
      ],
    );
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({required this.label, required this.value, this.tone = _ReportTone.neutral});

  final String label;
  final int value;
  final _ReportTone tone;

  @override
  Widget build(BuildContext context) {
    final color = _toneColor(context, tone);
    return Chip(
      avatar: CircleAvatar(backgroundColor: color, foregroundColor: Colors.white, child: Text('$value')),
      label: Text(label),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.children, required this.emptyMessage});

  final String title;
  final List<Widget> children;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            if (children.isEmpty) Text(emptyMessage) else ...children,
          ],
        ),
      ),
    );
  }
}

class _AccountReferenceTile extends StatelessWidget {
  const _AccountReferenceTile({required this.reference});

  final ImportAccountReferenceAnalysis reference;

  @override
  Widget build(BuildContext context) {
    final tone = _toneForStatus(reference.status);
    final color = _toneColor(context, tone);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(_statusIcon(reference.status), color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${reference.fieldName}｜${reference.value}', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text(_statusText(reference.status), style: TextStyle(color: color, fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (reference.candidates.isEmpty)
              const Text('候選帳戶：無')
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final candidate in reference.candidates) Chip(label: Text('${candidate.displayName} (${candidate.id})')),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _ValueListSection extends StatelessWidget {
  const _ValueListSection({required this.title, required this.values, required this.emptyMessage});

  final String title;
  final List<String> values;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: title,
      emptyMessage: emptyMessage,
      children: values.isEmpty
          ? const <Widget>[]
          : <Widget>[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [for (final value in values) Chip(label: Text(value))],
              ),
            ],
    );
  }
}

_ReportTone _toneForStatus(ImportAccountMappingStatus status) {
  switch (status) {
    case ImportAccountMappingStatus.matched:
      return _ReportTone.success;
    case ImportAccountMappingStatus.missing:
      return _ReportTone.error;
    case ImportAccountMappingStatus.ambiguous:
      return _ReportTone.warning;
  }
}

IconData _statusIcon(ImportAccountMappingStatus status) {
  switch (status) {
    case ImportAccountMappingStatus.matched:
      return Icons.check_circle_outline;
    case ImportAccountMappingStatus.missing:
      return Icons.error_outline;
    case ImportAccountMappingStatus.ambiguous:
      return Icons.help_outline;
  }
}

String _statusText(ImportAccountMappingStatus status) {
  switch (status) {
    case ImportAccountMappingStatus.matched:
      return '已對應';
    case ImportAccountMappingStatus.missing:
      return '缺失';
    case ImportAccountMappingStatus.ambiguous:
      return '模糊';
  }
}

Color _toneColor(BuildContext context, _ReportTone tone) {
  final scheme = Theme.of(context).colorScheme;
  switch (tone) {
    case _ReportTone.error:
      return scheme.error;
    case _ReportTone.warning:
      return Colors.orange.shade700;
    case _ReportTone.success:
      return Colors.green.shade700;
    case _ReportTone.neutral:
      return scheme.primary;
  }
}

enum _ReportTone { neutral, success, warning, error }
