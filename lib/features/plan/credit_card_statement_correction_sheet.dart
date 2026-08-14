import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'credit_card_statement_event.dart';

Future<CreditCardStatementEvent?> showCreditCardStatementCorrectionSheet({
  required BuildContext context,
  required CreditCardStatementEvent event,
}) async {
  final totalController = TextEditingController(text: _amountText(event.totalBalance));
  final minimumController = TextEditingController(text: _amountText(event.minimumPayment));
  final paidController = TextEditingController(text: _amountText(event.paidAmount));
  final unpaidController = TextEditingController(text: _amountText(event.unpaidBalance));
  final interestController = TextEditingController(text: _amountText(event.estimatedRevolvingInterest));
  final lateFeeController = TextEditingController(text: _amountText(event.estimatedLateFee));
  final noteController = TextEditingController(text: event.note);

  try {
    return await showModalBottomSheet<CreditCardStatementEvent>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          final total = _parseAmount(totalController.text, event.totalBalance);
          final minimum = _parseAmount(minimumController.text, event.minimumPayment);
          final paid = _parseAmount(paidController.text, event.paidAmount);
          final unpaid = _parseAmount(unpaidController.text, (total - paid).clamp(0, double.infinity).toDouble());
          final interest = _parseAmount(interestController.text, event.estimatedRevolvingInterest);
          final lateFee = _parseAmount(lateFeeController.text, event.estimatedLateFee);
          final corrected = event.copyWith(
            totalBalance: event.currency.roundAmount(total),
            minimumPayment: event.currency.roundAmount(minimum),
            paidAmount: event.currency.roundAmount(paid),
            unpaidBalance: event.currency.roundAmount(unpaid),
            estimatedRevolvingInterest: event.currency.roundAmount(interest),
            estimatedLateFee: event.currency.roundAmount(lateFee),
            note: noteController.text.trim().isEmpty ? '依銀行帳單手動校正' : noteController.text.trim(),
            updatedAt: DateTime.now(),
          );
          return SafeArea(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(16, 8, 16, MediaQuery.of(context).viewInsets.bottom + 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('校正信用卡帳單快照', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Text('${event.cardName}｜${DateFormat('yyyy/MM/dd').format(event.statementDate)} 帳單｜${DateFormat('yyyy/MM/dd').format(event.dueDate)} 到期', style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 8),
                  Text('此處只校正帳單快照，不會建立交易、不會改變帳戶餘額。實際繳款仍請使用信用卡繳款流程。', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.deepOrange, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  _AmountField(controller: totalController, label: '總應繳（${event.currency.code}）', onChanged: () => setModalState(() {})),
                  const SizedBox(height: 8),
                  _AmountField(controller: minimumController, label: '最低應繳（${event.currency.code}）', onChanged: () => setModalState(() {})),
                  const SizedBox(height: 8),
                  _AmountField(controller: paidController, label: '已繳金額（${event.currency.code}）', onChanged: () => setModalState(() {})),
                  const SizedBox(height: 8),
                  _AmountField(controller: unpaidController, label: '未繳金額（${event.currency.code}）', onChanged: () => setModalState(() {})),
                  const SizedBox(height: 8),
                  _AmountField(controller: interestController, label: '循環利息估算 / 帳單利息（${event.currency.code}）', onChanged: () => setModalState(() {})),
                  const SizedBox(height: 8),
                  _AmountField(controller: lateFeeController, label: '違約金 / 費用（${event.currency.code}）', onChanged: () => setModalState(() {})),
                  const SizedBox(height: 8),
                  TextField(controller: noteController, maxLines: 2, decoration: const InputDecoration(labelText: '備註 / 校正來源')),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Chip(label: Text('校正後未繳：${_money(corrected.unpaidBalance)} ${event.currency.code}')),
                      Chip(label: Text(corrected.isBelowMinimum ? '低於最低應繳' : '未低於最低應繳')),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(child: TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消'))),
                      const SizedBox(width: 8),
                      Expanded(child: FilledButton(onPressed: () => Navigator.of(context).pop(corrected), child: const Text('保存校正'))),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  } finally {
    totalController.dispose();
    minimumController.dispose();
    paidController.dispose();
    unpaidController.dispose();
    interestController.dispose();
    lateFeeController.dispose();
    noteController.dispose();
  }
}

class _AmountField extends StatelessWidget {
  const _AmountField({required this.controller, required this.label, required this.onChanged});
  final TextEditingController controller;
  final String label;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: label),
      onChanged: (_) => onChanged(),
    );
  }
}

double _parseAmount(String text, double fallback) {
  final value = double.tryParse(text.trim());
  if (value == null || value.isNaN || value.isInfinite) return fallback;
  return value.clamp(0, double.infinity).toDouble();
}

String _money(double value) => NumberFormat('#,##0.##').format(value);
String _amountText(double value) => value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
