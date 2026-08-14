import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../account/account_record.dart';
import 'credit_card_bank_rule_edit_sheet.dart';
import 'credit_card_bank_rule_profile.dart';
import 'credit_card_bank_rule_providers.dart';

class CreditCardBankRuleParameterCard extends ConsumerWidget {
  const CreditCardBankRuleParameterCard({super.key, required this.currency, required this.creditCards});

  final CurrencyCode currency;
  final List<AccountRecord> creditCards;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final defaultProfile = CreditCardBankRuleProfile.defaultEstimate(currency);
    final profilesValue = ref.watch(creditCardBankRuleProfilesProvider);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const CircleAvatar(child: Icon(Icons.tune_outlined)),
            const SizedBox(width: 12),
            Expanded(child: Text('信用卡銀行規則參數', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
            Chip(label: Text(defaultProfile.isVerifiedAgainstStatement ? '已校正' : '估算用')),
          ]),
          const SizedBox(height: 8),
          Text('此區屬於低頻設定。可建立自訂估算規則並指派給信用卡；目前仍以估算為主，實際金額請以銀行帳單與帳單快照校正為準。', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.deepOrange, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          _RuleProfilePreview(profile: defaultProfile),
          const SizedBox(height: 12),
          profilesValue.when(
            loading: () => const LinearProgressIndicator(),
            error: (error, stackTrace) => Text('讀取銀行規則失敗：$error', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.error)),
            data: (profiles) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text('自訂規則', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800))),
                OutlinedButton.icon(
                  onPressed: () async {
                    final created = await showCreditCardBankRuleEditSheet(context: context, initialProfile: defaultProfile, createNew: true);
                    if (created == null) return;
                    await ref.read(creditCardBankRuleProfilesProvider.notifier).save(created);
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('新增規則'),
                ),
              ]),
              const SizedBox(height: 8),
              if (profiles.isEmpty)
                Text('尚未建立自訂銀行規則。可先從預設估算規則複製，再依帳單校正。', style: Theme.of(context).textTheme.bodySmall)
              else
                for (final profile in profiles) _CustomRuleTile(profile: profile),
              const SizedBox(height: 12),
              if (creditCards.isNotEmpty) ...[
                Text('信用卡規則指派', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                for (final card in creditCards) _CardRuleAssignmentRow(card: card, profiles: profiles),
              ],
            ]),
          ),
        ]),
      ),
    );
  }
}

class _RuleProfilePreview extends StatelessWidget {
  const _RuleProfilePreview({required this.profile});
  final CreditCardBankRuleProfile profile;

  @override
  Widget build(BuildContext context) {
    return Wrap(spacing: 8, runSpacing: 8, children: [
      _RuleChip(label: '最低應繳比例', value: _percent(profile.minimumPaymentRate)),
      _RuleChip(label: '循環/前期比例', value: _percent(profile.revolvingBalanceRate)),
      _RuleChip(label: '最低門檻', value: '${_money(profile.minimumPaymentFloor)} ${profile.currency.code}'),
      _RuleChip(label: '年利率', value: _percent(profile.annualInterestRate)),
      _RuleChip(label: '估算週期', value: '${profile.estimatedCycleDays} 天'),
      _RuleChip(label: '違約金級距', value: profile.lateFeeTiers.isEmpty ? '未設定' : '${profile.lateFeeTiers.length} 段'),
    ]);
  }
}

class _CustomRuleTile extends ConsumerWidget {
  const _CustomRuleTile({required this.profile});
  final CreditCardBankRuleProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(profile.name, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800))),
            Chip(label: Text(profile.isVerifiedAgainstStatement ? '已用帳單驗證' : '估算用')),
          ]),
          const SizedBox(height: 6),
          _RuleProfilePreview(profile: profile),
          if (profile.note.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(profile.note, style: Theme.of(context).textTheme.bodySmall),
          ],
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.end, children: [
            OutlinedButton.icon(
              onPressed: () async {
                final created = await showCreditCardBankRuleEditSheet(context: context, initialProfile: profile, createNew: true);
                if (created == null) return;
                await ref.read(creditCardBankRuleProfilesProvider.notifier).save(created);
              },
              icon: const Icon(Icons.copy_outlined),
              label: const Text('複製'),
            ),
            OutlinedButton.icon(
              onPressed: () async {
                final updated = await showCreditCardBankRuleEditSheet(context: context, initialProfile: profile);
                if (updated == null) return;
                await ref.read(creditCardBankRuleProfilesProvider.notifier).save(updated);
              },
              icon: const Icon(Icons.edit_outlined),
              label: const Text('編輯'),
            ),
            OutlinedButton.icon(
              onPressed: () async {
                final confirmed = await _confirmDeleteRule(context, profile);
                if (!confirmed) return;
                await ref.read(creditCardBankRuleProfilesProvider.notifier).delete(profile.id);
              },
              icon: const Icon(Icons.delete_outline),
              label: const Text('刪除'),
            ),
          ]),
        ]),
      ),
    );
  }
}

class _CardRuleAssignmentRow extends ConsumerWidget {
  const _CardRuleAssignmentRow({required this.card, required this.profiles});
  final AccountRecord card;
  final List<CreditCardBankRuleProfile> profiles;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assignment = ref.watch(creditCardBankRuleAssignmentProvider(card.id));
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: assignment.when(
        loading: () => const LinearProgressIndicator(),
        error: (error, stackTrace) => Text('${card.displayName} 規則讀取失敗：$error', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.error)),
        data: (selectedId) {
          final selectedProfileExists = selectedId != null && profiles.any((profile) => profile.id == selectedId);
          final safeSelectedId = selectedProfileExists ? selectedId : null;
          return DropdownButtonFormField<String?>(
            initialValue: safeSelectedId,
            decoration: InputDecoration(labelText: card.displayName),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('使用系統預設估算規則')),
              for (final profile in profiles) DropdownMenuItem<String?>(value: profile.id, child: Text(profile.name)),
            ],
            onChanged: (value) async {
              await ref.read(creditCardBankRuleAssignmentProvider(card.id).notifier).assign(value);
            },
          );
        },
      ),
    );
  }
}

class _RuleChip extends StatelessWidget {
  const _RuleChip({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Chip(label: Text('$label：$value'));
}

Future<bool> _confirmDeleteRule(BuildContext context, CreditCardBankRuleProfile profile) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('刪除銀行規則？'),
      content: Text('將刪除「${profile.name}」。已指派此規則的信用卡會回到系統預設估算規則。'),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('刪除')),
      ],
    ),
  );
  return result ?? false;
}

String _money(double value) => NumberFormat('#,##0.##').format(value);
String _percent(double value) => NumberFormat('0.##%').format(value);
