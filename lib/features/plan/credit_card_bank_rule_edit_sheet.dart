import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import 'credit_card_bank_rule_profile.dart';

Future<CreditCardBankRuleProfile?> showCreditCardBankRuleEditSheet({
  required BuildContext context,
  required CreditCardBankRuleProfile initialProfile,
  bool createNew = false,
}) async {
  final profileId = createNew ? const Uuid().v4() : initialProfile.id;
  final nameController = TextEditingController(text: createNew ? '${initialProfile.name} 副本' : initialProfile.name);
  final minimumRateController = TextEditingController(text: _percentText(initialProfile.minimumPaymentRate));
  final revolvingRateController = TextEditingController(text: _percentText(initialProfile.revolvingBalanceRate));
  final floorController = TextEditingController(text: _amountText(initialProfile.minimumPaymentFloor));
  final annualRateController = TextEditingController(text: _percentText(initialProfile.annualInterestRate));
  final cycleDaysController = TextEditingController(text: initialProfile.estimatedCycleDays.toString());
  final lateFeeTiersController = TextEditingController(text: encodeCreditCardLateFeeTiers(initialProfile.lateFeeTiers));
  final noteController = TextEditingController(text: initialProfile.note);
  var includeEstimatedFees = initialProfile.includeEstimatedFees;
  var verified = createNew ? false : initialProfile.isVerifiedAgainstStatement;

  try {
    return await showModalBottomSheet<CreditCardBankRuleProfile>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          final preview = initialProfile.copyWith(
            id: profileId,
            name: nameController.text.trim().isEmpty ? '未命名規則' : nameController.text.trim(),
            minimumPaymentRate: _parsePercent(minimumRateController.text, initialProfile.minimumPaymentRate),
            revolvingBalanceRate: _parsePercent(revolvingRateController.text, initialProfile.revolvingBalanceRate),
            minimumPaymentFloor: _parseAmount(floorController.text, initialProfile.minimumPaymentFloor),
            annualInterestRate: _parsePercent(annualRateController.text, initialProfile.annualInterestRate),
            estimatedCycleDays: _parseInt(cycleDaysController.text, initialProfile.estimatedCycleDays).clamp(0, 366).toInt(),
            lateFeeTiers: decodeCreditCardLateFeeTiers(lateFeeTiersController.text),
            includeEstimatedFees: includeEstimatedFees,
            note: noteController.text.trim(),
            isVerifiedAgainstStatement: verified,
          );
          return SafeArea(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(16, 8, 16, MediaQuery.of(context).viewInsets.bottom + 16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(createNew ? '新增銀行規則' : '編輯銀行規則', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text('規則參數僅供估算，不代表特定銀行條款。請用實際帳單快照校正結果驗證。', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.deepOrange, fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                TextField(controller: nameController, decoration: const InputDecoration(labelText: '規則名稱'), onChanged: (_) => setModalState(() {})),
                const SizedBox(height: 8),
                _RuleField(controller: minimumRateController, label: '最低應繳比例（%）', onChanged: () => setModalState(() {})),
                const SizedBox(height: 8),
                _RuleField(controller: revolvingRateController, label: '循環 / 前期餘額比例（%）', onChanged: () => setModalState(() {})),
                const SizedBox(height: 8),
                _RuleField(controller: floorController, label: '最低門檻（${initialProfile.currency.code}）', onChanged: () => setModalState(() {})),
                const SizedBox(height: 8),
                _RuleField(controller: annualRateController, label: '循環年利率（%）', onChanged: () => setModalState(() {})),
                const SizedBox(height: 8),
                _RuleField(controller: cycleDaysController, label: '估算週期天數', onChanged: () => setModalState(() {})),
                const SizedBox(height: 8),
                TextField(controller: lateFeeTiersController, decoration: const InputDecoration(labelText: '違約金級距', helperText: '格式：1:300,2:400,3:500'), onChanged: (_) => setModalState(() {})),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('包含估算費用'),
                  value: includeEstimatedFees,
                  onChanged: (value) => setModalState(() => includeEstimatedFees = value),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('已用實際帳單驗證'),
                  subtitle: const Text('僅作標記，不會自動代表銀行官方條款。'),
                  value: verified,
                  onChanged: (value) => setModalState(() => verified = value),
                ),
                TextField(controller: noteController, maxLines: 2, decoration: const InputDecoration(labelText: '備註 / 資料來源'), onChanged: (_) => setModalState(() {})),
                const SizedBox(height: 12),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  Chip(label: Text('最低應繳 ${_pct(preview.minimumPaymentRate)}')),
                  Chip(label: Text('循環年利率 ${_pct(preview.annualInterestRate)}')),
                  Chip(label: Text('週期 ${preview.estimatedCycleDays} 天')),
                  Chip(label: Text('違約金 ${preview.lateFeeTiers.length} 段')),
                ]),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(child: TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消'))),
                  const SizedBox(width: 8),
                  Expanded(child: FilledButton(onPressed: () => Navigator.of(context).pop(preview), child: const Text('保存'))),
                ]),
              ]),
            ),
          );
        },
      ),
    );
  } finally {
    nameController.dispose();
    minimumRateController.dispose();
    revolvingRateController.dispose();
    floorController.dispose();
    annualRateController.dispose();
    cycleDaysController.dispose();
    lateFeeTiersController.dispose();
    noteController.dispose();
  }
}

class _RuleField extends StatelessWidget {
  const _RuleField({required this.controller, required this.label, required this.onChanged});
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

double _parsePercent(String text, double fallback) {
  final value = double.tryParse(text.trim());
  if (value == null || value.isNaN || value.isInfinite) return fallback;
  return (value / 100).clamp(0, 1).toDouble();
}

double _parseAmount(String text, double fallback) {
  final value = double.tryParse(text.trim());
  if (value == null || value.isNaN || value.isInfinite) return fallback;
  return value.clamp(0, double.infinity).toDouble();
}

int _parseInt(String text, int fallback) => int.tryParse(text.trim()) ?? fallback;
String _percentText(double value) => (value * 100).toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
String _amountText(double value) => value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
String _pct(double value) => '${_percentText(value)}%';
