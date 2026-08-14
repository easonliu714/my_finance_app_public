import 'package:flutter/material.dart';

import 'readable_import_service.dart';

class ImportDryRunReport extends StatelessWidget {
  const ImportDryRunReport({super.key, required this.result});

  final ReadableImportDryRunResult result;

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
                Text('匯入預檢報告', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                const Text('目前只完成 dry-run 預檢，尚未寫入正式資料。此頁優先顯示人可讀交易內容，方便確認是否需要匯入。'),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _SummaryChip(label: '總列數', value: result.totalRows),
                    _SummaryChip(label: '有效', value: result.validRows),
                    _SummaryChip(label: '錯誤', value: result.invalidRows, tone: _ReportTone.error),
                    _SummaryChip(label: '重複', value: result.duplicateRows, tone: _ReportTone.warning),
                    _SummaryChip(label: '可匯入', value: result.readyToInsertRows, tone: _ReportTone.success),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (result.rows.isEmpty)
          const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('沒有可顯示的匯入列。')))
        else
          for (final row in result.rows) _ImportRowResultTile(row: row),
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

class _ImportRowResultTile extends StatelessWidget {
  const _ImportRowResultTile({required this.row});

  final ReadableImportRowResult row;

  @override
  Widget build(BuildContext context) {
    final tone = _toneForStatus(row.status);
    final color = _toneColor(context, tone);
    final title = '第 ${row.sourceRowIndex} 列｜${_statusText(row.status)}';
    final subtitle = '${_typeLabel(row.row['type'])}｜${_formatAmount(row.row['amount'])}｜${_value(row.row['occurred_at'])}｜${_primaryAccountText(row.row)}｜${_value(row.row['category'])}｜${_value(row.row['merchant_name'])}';
    return Card(
      child: ExpansionTile(
        leading: Icon(_statusIcon(row.status), color: color),
        title: Text(title, style: TextStyle(fontWeight: FontWeight.w800, color: color)),
        subtitle: Text(subtitle),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          _ReadableTransactionSummary(row: row),
          const SizedBox(height: 8),
          if (row.errors.isEmpty)
            const Align(alignment: Alignment.centerLeft, child: Text('無錯誤訊息'))
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('錯誤原因', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                for (final error in row.errors) Text('• $error'),
              ],
            ),
        ],
      ),
    );
  }
}

class _ReadableTransactionSummary extends StatelessWidget {
  const _ReadableTransactionSummary({required this.row});

  final ReadableImportRowResult row;

  @override
  Widget build(BuildContext context) {
    final data = row.row;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('交易內容', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        _FieldLine(label: '日期', value: _value(data['occurred_at'])),
        _FieldLine(label: '類型', value: _typeLabel(data['type'])),
        _FieldLine(label: '金額', value: _formatAmount(data['amount'])),
        _FieldLine(label: '帳戶', value: _value(data['account_name'])),
        _FieldLine(label: '轉出帳戶', value: _value(data['from_account_name'])),
        _FieldLine(label: '轉入帳戶', value: _value(data['to_account_name'])),
        _FieldLine(label: '類別', value: _value(data['category'])),
        _FieldLine(label: '商家', value: _value(data['merchant_name'])),
        _FieldLine(label: '備註', value: _value(data['note'])),
        _FieldLine(label: '識別碼', value: _value(data['id'])),
      ],
    );
  }
}

class _FieldLine extends StatelessWidget {
  const _FieldLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 76, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700))),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

_ReportTone _toneForStatus(ReadableImportRowStatus status) {
  switch (status) {
    case ReadableImportRowStatus.invalid:
      return _ReportTone.error;
    case ReadableImportRowStatus.duplicate:
      return _ReportTone.warning;
    case ReadableImportRowStatus.readyToInsert:
      return _ReportTone.success;
  }
}

IconData _statusIcon(ReadableImportRowStatus status) {
  switch (status) {
    case ReadableImportRowStatus.invalid:
      return Icons.error_outline;
    case ReadableImportRowStatus.duplicate:
      return Icons.copy_outlined;
    case ReadableImportRowStatus.readyToInsert:
      return Icons.check_circle_outline;
  }
}

String _statusText(ReadableImportRowStatus status) {
  switch (status) {
    case ReadableImportRowStatus.invalid:
      return '錯誤';
    case ReadableImportRowStatus.duplicate:
      return '重複';
    case ReadableImportRowStatus.readyToInsert:
      return '可匯入';
  }
}

String _typeLabel(Object? value) {
  final type = _value(value);
  switch (type) {
    case 'income':
      return '收入';
    case 'expense':
      return '支出';
    case 'transfer':
      return '轉帳';
    case 'loan':
      return '借貸';
    case '-':
      return '-';
    default:
      return type;
  }
}

String _primaryAccountText(Map<String, Object?> row) {
  final from = _value(row['from_account_name']);
  final to = _value(row['to_account_name']);
  final account = _value(row['account_name']);
  if (from != '-' || to != '-') return '$from → $to';
  return account;
}

String _formatAmount(Object? value) {
  final text = _value(value);
  if (text == '-') return text;
  final number = num.tryParse(text);
  if (number == null) return text;
  return number % 1 == 0 ? number.toInt().toString() : number.toString();
}

String _value(Object? value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? '-' : text;
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
