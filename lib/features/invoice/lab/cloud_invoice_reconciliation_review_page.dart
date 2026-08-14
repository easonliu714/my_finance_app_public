import 'package:flutter/material.dart';

import 'cloud_invoice_reconciliation_models.dart';
import 'cloud_invoice_reconciliation_review_decision.dart';

class CloudInvoiceReconciliationReviewPage extends StatefulWidget {
  const CloudInvoiceReconciliationReviewPage({
    super.key,
    required this.controller,
    this.onDecision,
    this.onAddAccount,
    this.onCancel,
  });

  static const Key candidateSummaryKey = Key('reconciliation_candidate_summary');
  static const Key recommendationKey = Key('reconciliation_recommendation');
  static const Key matchListKey = Key('reconciliation_match_list');
  static const Key actionListKey = Key('reconciliation_action_list');
  static const Key merchantSectionKey = Key('reconciliation_merchant_section');
  static const Key accountSectionKey = Key('reconciliation_account_section');
  static const Key accountDropdownKey = Key('reconciliation_account_dropdown');
  static const Key addAccountKey = Key('reconciliation_add_account');
  static const Key replacementSectionKey = Key('reconciliation_replacement');
  static const Key replacementConfirmKey =
      Key('reconciliation_replacement_confirm');
  static const Key submitKey = Key('reconciliation_submit');
  static const Key blockedKey = Key('reconciliation_blocked');
  static const Key safetyKey = Key('reconciliation_safety');

  final CloudInvoiceReconciliationReviewController controller;
  final ValueChanged<CloudInvoiceReconciliationReviewDecision>? onDecision;
  final VoidCallback? onAddAccount;
  final VoidCallback? onCancel;

  @override
  State<CloudInvoiceReconciliationReviewPage> createState() =>
      _CloudInvoiceReconciliationReviewPageState();
}

class _CloudInvoiceReconciliationReviewPageState
    extends State<CloudInvoiceReconciliationReviewPage> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  @override
  void didUpdateWidget(CloudInvoiceReconciliationReviewPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.removeListener(_onChanged);
    widget.controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return Scaffold(
      appBar: AppBar(
        title: const Text('雲端發票帳目比對'),
        leading: widget.onCancel == null
            ? null
            : IconButton(
                onPressed: widget.onCancel,
                icon: const Icon(Icons.close),
                tooltip: '取消',
              ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _CandidateSummaryCard(controller: controller),
            const SizedBox(height: 12),
            _RecommendationCard(controller: controller),
            if (controller.plan.rankedMatches.isNotEmpty) ...[
              const SizedBox(height: 12),
              _MatchSection(controller: controller),
            ],
            const SizedBox(height: 12),
            _ActionSection(controller: controller),
            const SizedBox(height: 12),
            _MerchantSection(controller: controller),
            const SizedBox(height: 12),
            _AccountSection(
              controller: controller,
              onAddAccount: widget.onAddAccount,
            ),
            if (controller.requiresReplacementConfirmation) ...[
              const SizedBox(height: 12),
              _ReplacementSection(controller: controller),
            ],
            const SizedBox(height: 12),
            const _SafetyCard(),
            const SizedBox(height: 16),
            if (controller.isBlocked)
              const Card(
                key: CloudInvoiceReconciliationReviewPage.blockedKey,
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('此候選目前已被阻擋，不能產生帳目處置決策。'),
                ),
              ),
            FilledButton.icon(
              key: CloudInvoiceReconciliationReviewPage.submitKey,
              onPressed: controller.canSubmit && widget.onDecision != null
                  ? () => widget.onDecision!(controller.buildDecision())
                  : null,
              icon: const Icon(Icons.fact_check_outlined),
              label: const Text('產生覆核決策'),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _CandidateSummaryCard extends StatelessWidget {
  const _CandidateSummaryCard({required this.controller});

  final CloudInvoiceReconciliationReviewController controller;

  @override
  Widget build(BuildContext context) {
    final facts = controller.facts;
    final candidate = facts.candidate;
    final seller = candidate.sellerName.trim();
    final sellerIdentifier = candidate.sellerIdentifier.trim();
    return Card(
      key: CloudInvoiceReconciliationReviewPage.candidateSummaryKey,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '雲端發票資料',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 12),
            _FactRow(
              label: '發票號碼',
              value: candidate.invoiceNumber.trim().isEmpty
                  ? '未提供'
                  : candidate.invoiceNumber.trim(),
            ),
            _FactRow(
              label: '交易對象',
              value: seller.isEmpty ? '未提供' : seller,
            ),
            if (sellerIdentifier.isNotEmpty)
              _FactRow(label: '賣方統編', value: sellerIdentifier),
            _FactRow(
              label: '發票日期',
              value: _dateText(candidate.invoiceDate),
            ),
            _FactRow(
              label: '發票時間',
              value: facts.hasExactTime
                  ? _timeText(candidate.invoiceDate)
                  : '開立時間未提供',
            ),
            _FactRow(label: '金額', value: _numberText(candidate.totalAmount)),
            _FactRow(
              label: '幣別',
              value: facts.hasKnownCurrency
                  ? facts.currencyCode!.trim().toUpperCase()
                  : '幣別未提供',
            ),
            if (candidate.taxAmount != null)
              _FactRow(
                label: '稅額',
                value: _numberText(candidate.taxAmount!),
              ),
            if (candidate.lineItems.isNotEmpty)
              _FactRow(
                label: '品項',
                value: '${candidate.lineItems.length} 項',
              ),
          ],
        ),
      ),
    );
  }
}

class _RecommendationCard extends StatelessWidget {
  const _RecommendationCard({required this.controller});

  final CloudInvoiceReconciliationReviewController controller;

  @override
  Widget build(BuildContext context) {
    final plan = controller.plan;
    return Card(
      key: CloudInvoiceReconciliationReviewPage.recommendationKey,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '系統建議：${_outcomeLabel(plan.recommendedOutcome)}',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 8),
            for (final reason in plan.reasons)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('• $reason'),
              ),
          ],
        ),
      ),
    );
  }
}

class _MatchSection extends StatelessWidget {
  const _MatchSection({required this.controller});

  final CloudInvoiceReconciliationReviewController controller;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: CloudInvoiceReconciliationReviewPage.matchListKey,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '可能的既有帳目',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 4),
            const Text('模糊結果必須先選定一筆帳目，再決定補充、取代或保持分開。'),
            const SizedBox(height: 8),
            for (final match in controller.plan.rankedMatches)
              _MatchTile(
                match: match,
                selected: controller.selectedTransactionId ==
                    match.snapshot.transaction.id,
                onTap: () => controller.selectTransaction(
                  match.snapshot.transaction.id,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MatchTile extends StatelessWidget {
  const _MatchTile({
    required this.match,
    required this.selected,
    required this.onTap,
  });

  final CloudInvoiceTransactionMatch match;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final transaction = match.snapshot.transaction;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: InkWell(
        key: ValueKey<String>('match_${transaction.id}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(
              color: selected
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).dividerColor,
              width: selected ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        transaction.merchantName.trim().isEmpty
                            ? '未命名交易對象'
                            : transaction.merchantName,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        '${_dateText(transaction.occurredAt)} ${_timeText(transaction.occurredAt)}',
                      ),
                      Text(
                        '${transaction.currency.code} ${_numberText(transaction.amount)}｜${transaction.accountName}',
                      ),
                      Text(
                        '此候選建議：${_outcomeLabel(match.recommendedOutcome)}｜分數 ${match.score}',
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final signal in match.signals)
                            Chip(
                              visualDensity: VisualDensity.compact,
                              label: Text(_signalLabel(signal)),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionSection extends StatelessWidget {
  const _ActionSection({required this.controller});

  final CloudInvoiceReconciliationReviewController controller;

  @override
  Widget build(BuildContext context) {
    final actions = controller.availableActions.toList()
      ..sort((left, right) => left.index.compareTo(right.index));
    return Card(
      key: CloudInvoiceReconciliationReviewPage.actionListKey,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '選擇處置',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 8),
            if (actions.isEmpty)
              const Text('目前沒有可提交的處置。')
            else
              for (final action in actions)
                _ChoiceTile(
                  key: ValueKey<String>('action_${action.name}'),
                  selected: controller.selectedAction == action,
                  title: _outcomeLabel(action),
                  subtitle: action == controller.plan.recommendedOutcome
                      ? '系統建議'
                      : null,
                  onTap: () => controller.selectAction(action),
                ),
          ],
        ),
      ),
    );
  }
}

class _MerchantSection extends StatelessWidget {
  const _MerchantSection({required this.controller});

  final CloudInvoiceReconciliationReviewController controller;

  @override
  Widget build(BuildContext context) {
    final plan = controller.plan.merchantPlan;
    return Card(
      key: CloudInvoiceReconciliationReviewPage.merchantSectionKey,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '交易商家',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 8),
            switch (plan.status) {
              CloudInvoiceMerchantResolutionStatus.linkedExisting => Text(
                  '沿用既有商家：${plan.existingMerchant?.name ?? '未提供'}',
                ),
              CloudInvoiceMerchantResolutionStatus.unresolved =>
                const Text('商家資料不足，保持未連結；不會自動建立商家。'),
              CloudInvoiceMerchantResolutionStatus.createDraftProposed =>
                _MerchantProposal(controller: controller),
            },
          ],
        ),
      ),
    );
  }
}

class _MerchantProposal extends StatelessWidget {
  const _MerchantProposal({required this.controller});

  final CloudInvoiceReconciliationReviewController controller;

  @override
  Widget build(BuildContext context) {
    final proposal = controller.plan.merchantPlan.creationProposal!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('建議商家：${proposal.name}'),
        if (proposal.sellerIdentifier.isNotEmpty)
          Text('賣方統編：${proposal.sellerIdentifier}'),
        Text('來源發票：${proposal.sourceInvoiceNumber}'),
        const SizedBox(height: 8),
        const Text('建立商家必須明確確認；本頁只記錄決策，不會寫入資料庫。'),
        _ChoiceTile(
          key: const Key('merchant_create_choice'),
          selected: controller.merchantProposalChoice ==
              CloudInvoiceMerchantProposalChoice.createMerchant,
          title: '建立新商家',
          onTap: () => controller.chooseMerchantProposal(
            CloudInvoiceMerchantProposalChoice.createMerchant,
          ),
        ),
        _ChoiceTile(
          key: const Key('merchant_skip_choice'),
          selected: controller.merchantProposalChoice ==
              CloudInvoiceMerchantProposalChoice.skipMerchant,
          title: '暫不建立商家',
          onTap: () => controller.chooseMerchantProposal(
            CloudInvoiceMerchantProposalChoice.skipMerchant,
          ),
        ),
      ],
    );
  }
}

class _AccountSection extends StatelessWidget {
  const _AccountSection({
    required this.controller,
    required this.onAddAccount,
  });

  final CloudInvoiceReconciliationReviewController controller;
  final VoidCallback? onAddAccount;

  @override
  Widget build(BuildContext context) {
    final action = controller.selectedAction;
    final selectedMatch = controller.selectedMatch;
    final resolvedMatch = selectedMatch ??
        (controller.plan.rankedMatches.length == 1
            ? controller.plan.rankedMatches.single
            : null);
    final usesExisting = action ==
            CloudInvoiceReconciliationOutcome.exactDuplicate ||
        action == CloudInvoiceReconciliationOutcome.enrichExisting ||
        action == CloudInvoiceReconciliationOutcome.replaceExisting;

    return Card(
      key: CloudInvoiceReconciliationReviewPage.accountSectionKey,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '交易帳戶',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 8),
            if (usesExisting && resolvedMatch != null)
              Text('保留既有帳戶：${resolvedMatch.snapshot.transaction.accountName}')
            else if (action == CloudInvoiceReconciliationOutcome.createNewDraft)
              _NewDraftAccountSelector(
                controller: controller,
                onAddAccount: onAddAccount,
              )
            else
              const Text('選擇處置後，這裡會顯示保留帳戶或新草稿帳戶選項。'),
          ],
        ),
      ),
    );
  }
}

class _NewDraftAccountSelector extends StatelessWidget {
  const _NewDraftAccountSelector({
    required this.controller,
    required this.onAddAccount,
  });

  final CloudInvoiceReconciliationReviewController controller;
  final VoidCallback? onAddAccount;

  @override
  Widget build(BuildContext context) {
    final accountPlan = controller.plan.accountPlan;
    if (accountPlan.requiresNewAccount) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('必須先新增帳戶，才能建立新草稿。'),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: CloudInvoiceReconciliationReviewPage.addAccountKey,
            onPressed: onAddAccount,
            icon: const Icon(Icons.add),
            label: const Text('新增帳戶'),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('請明確選擇既有帳戶；建議帳戶不會自動選定。'),
        const SizedBox(height: 8),
        InputDecorator(
          decoration: const InputDecoration(
            labelText: '帳戶',
            border: OutlineInputBorder(),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              key: CloudInvoiceReconciliationReviewPage.accountDropdownKey,
              isExpanded: true,
              value: controller.selectedAccountId,
              hint: const Text('請選擇帳戶'),
              items: [
                for (final option in accountPlan.options)
                  DropdownMenuItem<String>(
                    value: option.account.id,
                    enabled: option.currencyCompatible,
                    child: Text(
                      _accountOptionLabel(
                        option,
                        accountPlan.suggestedAccountId,
                      ),
                    ),
                  ),
              ],
              onChanged: controller.selectAccount,
            ),
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: CloudInvoiceReconciliationReviewPage.addAccountKey,
          onPressed: onAddAccount,
          icon: const Icon(Icons.add),
          label: const Text('新增帳戶'),
        ),
      ],
    );
  }
}

class _ReplacementSection extends StatelessWidget {
  const _ReplacementSection({required this.controller});

  final CloudInvoiceReconciliationReviewController controller;

  @override
  Widget build(BuildContext context) {
    final differences = _effectiveDifferences(controller);
    return Card(
      key: CloudInvoiceReconciliationReviewPage.replacementSectionKey,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '取代既有帳目確認',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 6),
            const Text('取代不會在本階段執行；以下差異只用於產生人工覆核決策。'),
            const SizedBox(height: 8),
            for (final difference in differences)
              _DifferenceRow(difference: difference),
            const SizedBox(height: 8),
            CheckboxListTile(
              key: CloudInvoiceReconciliationReviewPage.replacementConfirmKey,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: controller.replacementConfirmed,
              onChanged: (value) =>
                  controller.setReplacementConfirmed(value ?? false),
              title: const Text('我已逐欄確認差異，仍要提出取代決策'),
              subtitle: const Text('此確認不會直接修改或刪除任何帳目。'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DifferenceRow extends StatelessWidget {
  const _DifferenceRow({required this.difference});

  final CloudInvoiceFieldDifference difference;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(
          color: difference.isMaterialConflict
              ? Theme.of(context).colorScheme.error
              : Theme.of(context).dividerColor,
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _fieldLabel(difference.field),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          Text('既有：${difference.existingValue ?? '未提供'}'),
          Text('雲端：${difference.candidateValue ?? '未提供'}'),
          if (difference.isMaterialConflict)
            const Text('重要衝突', style: TextStyle(fontWeight: FontWeight.w700)),
          if (difference.isSafeEnrichment)
            const Text('可補充欄位', style: TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _SafetyCard extends StatelessWidget {
  const _SafetyCard();

  @override
  Widget build(BuildContext context) {
    return const Card(
      key: CloudInvoiceReconciliationReviewPage.safetyKey,
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          '本頁只產生記憶體內覆核決策，不會自動建立正式交易、商家、帳戶，也不會取代或刪除既有帳目。',
        ),
      ),
    );
  }
}

class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    super.key,
    required this.selected,
    required this.title,
    required this.onTap,
    this.subtitle,
  });

  final bool selected;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FactRow extends StatelessWidget {
  const _FactRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 88, child: Text(label)),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

List<CloudInvoiceFieldDifference> _effectiveDifferences(
  CloudInvoiceReconciliationReviewController controller,
) {
  final match = controller.selectedMatch ??
      (controller.plan.rankedMatches.length == 1
          ? controller.plan.rankedMatches.single
          : null);
  if (match == null) return controller.plan.fieldDifferences;
  final transaction = match.snapshot.transaction;
  final candidate = controller.facts.candidate;
  final knownCurrency = controller.facts.currencyCode;
  return <CloudInvoiceFieldDifference>[
    CloudInvoiceFieldDifference(
      field: CloudInvoiceReconciliationField.invoiceNumber,
      existingValue: match.snapshot.invoiceNumber,
      candidateValue: candidate.invoiceNumber,
      isMaterialConflict: _different(
        match.snapshot.invoiceNumber,
        candidate.invoiceNumber,
      ),
      isSafeEnrichment: _missing(match.snapshot.invoiceNumber),
    ),
    CloudInvoiceFieldDifference(
      field: CloudInvoiceReconciliationField.sellerIdentifier,
      existingValue: match.snapshot.sellerIdentifier,
      candidateValue: candidate.sellerIdentifier,
      isMaterialConflict: _different(
        match.snapshot.sellerIdentifier,
        candidate.sellerIdentifier,
      ),
      isSafeEnrichment: _missing(match.snapshot.sellerIdentifier),
    ),
    CloudInvoiceFieldDifference(
      field: CloudInvoiceReconciliationField.merchantName,
      existingValue: transaction.merchantName,
      candidateValue: candidate.sellerName,
      isMaterialConflict: _different(
        transaction.merchantName,
        candidate.sellerName,
      ),
      isSafeEnrichment: _missing(transaction.merchantName),
    ),
    CloudInvoiceFieldDifference(
      field: CloudInvoiceReconciliationField.amount,
      existingValue: _numberText(transaction.amount),
      candidateValue: _numberText(candidate.totalAmount),
      isMaterialConflict:
          (transaction.amount - candidate.totalAmount).abs() > 0.01,
      isSafeEnrichment: false,
    ),
    CloudInvoiceFieldDifference(
      field: CloudInvoiceReconciliationField.transactionDate,
      existingValue: _dateText(transaction.occurredAt),
      candidateValue: _dateText(candidate.invoiceDate),
      isMaterialConflict:
          _dateText(transaction.occurredAt) != _dateText(candidate.invoiceDate),
      isSafeEnrichment: false,
    ),
    CloudInvoiceFieldDifference(
      field: CloudInvoiceReconciliationField.exactTime,
      existingValue: _timeText(transaction.occurredAt),
      candidateValue: controller.facts.hasExactTime
          ? _timeText(candidate.invoiceDate)
          : null,
      isMaterialConflict: false,
      isSafeEnrichment: controller.facts.hasExactTime,
    ),
    CloudInvoiceFieldDifference(
      field: CloudInvoiceReconciliationField.currency,
      existingValue: transaction.currency.code,
      candidateValue: knownCurrency,
      isMaterialConflict: knownCurrency != null &&
          transaction.currency.code.toUpperCase() !=
              knownCurrency.trim().toUpperCase(),
      isSafeEnrichment: false,
    ),
    CloudInvoiceFieldDifference(
      field: CloudInvoiceReconciliationField.taxAmount,
      existingValue: null,
      candidateValue: candidate.taxAmount == null
          ? null
          : _numberText(candidate.taxAmount!),
      isMaterialConflict: false,
      isSafeEnrichment: candidate.taxAmount != null,
    ),
    CloudInvoiceFieldDifference(
      field: CloudInvoiceReconciliationField.lineItems,
      existingValue: null,
      candidateValue: candidate.lineItems.isEmpty
          ? null
          : '${candidate.lineItems.length} 項',
      isMaterialConflict: false,
      isSafeEnrichment: candidate.lineItems.isNotEmpty,
    ),
    CloudInvoiceFieldDifference(
      field: CloudInvoiceReconciliationField.account,
      existingValue: transaction.accountName,
      candidateValue: controller.facts.paymentHint.accountName,
      isMaterialConflict: _different(
        transaction.accountName,
        controller.facts.paymentHint.accountName,
      ),
      isSafeEnrichment: false,
    ),
  ];
}

String _outcomeLabel(CloudInvoiceReconciliationOutcome outcome) {
  return switch (outcome) {
    CloudInvoiceReconciliationOutcome.exactDuplicate => '確認為重複',
    CloudInvoiceReconciliationOutcome.enrichExisting => '補充既有帳目',
    CloudInvoiceReconciliationOutcome.replaceExisting => '取代既有帳目',
    CloudInvoiceReconciliationOutcome.createNewDraft => '建立新草稿',
    CloudInvoiceReconciliationOutcome.keepSeparate => '保持分開',
    CloudInvoiceReconciliationOutcome.ambiguous => '需要人工判定',
    CloudInvoiceReconciliationOutcome.blocked => '已阻擋',
  };
}

String _signalLabel(CloudInvoiceMatchSignal signal) {
  return switch (signal) {
    CloudInvoiceMatchSignal.sameCalendarDate => '同日',
    CloudInvoiceMatchSignal.exactAmount => '同額',
    CloudInvoiceMatchSignal.invoiceIdentity => '發票身分一致',
    CloudInvoiceMatchSignal.merchantExact => '商家一致',
    CloudInvoiceMatchSignal.merchantSimilar => '商家相似',
    CloudInvoiceMatchSignal.accountNameMatch => '帳戶一致',
    CloudInvoiceMatchSignal.accountTypeMatch => '帳戶類型一致',
    CloudInvoiceMatchSignal.paymentMethodMatch => '交易方式一致',
    CloudInvoiceMatchSignal.amountConflict => '金額衝突',
    CloudInvoiceMatchSignal.merchantConflict => '商家衝突',
    CloudInvoiceMatchSignal.currencyConflict => '幣別衝突',
  };
}

String _fieldLabel(CloudInvoiceReconciliationField field) {
  return switch (field) {
    CloudInvoiceReconciliationField.invoiceNumber => '發票號碼',
    CloudInvoiceReconciliationField.sellerIdentifier => '賣方統編',
    CloudInvoiceReconciliationField.merchantName => '交易商家',
    CloudInvoiceReconciliationField.amount => '金額',
    CloudInvoiceReconciliationField.transactionDate => '交易日期',
    CloudInvoiceReconciliationField.exactTime => '交易時間',
    CloudInvoiceReconciliationField.currency => '幣別',
    CloudInvoiceReconciliationField.taxAmount => '稅額',
    CloudInvoiceReconciliationField.lineItems => '品項',
    CloudInvoiceReconciliationField.account => '帳戶',
  };
}

String _accountOptionLabel(
  CloudInvoiceAccountSelectionOption option,
  String? suggestedAccountId,
) {
  final labels = <String>[option.account.displayName];
  if (option.account.id == suggestedAccountId) labels.add('建議');
  if (!option.currencyCompatible) labels.add('幣別不相容');
  return labels.join('｜');
}

String _dateText(DateTime value) {
  String twoDigits(int input) => input.toString().padLeft(2, '0');
  return '${value.year}-${twoDigits(value.month)}-${twoDigits(value.day)}';
}

String _timeText(DateTime value) {
  String twoDigits(int input) => input.toString().padLeft(2, '0');
  return '${twoDigits(value.hour)}:${twoDigits(value.minute)}:${twoDigits(value.second)}';
}

String _numberText(double value) {
  final fixed = value.toStringAsFixed(2);
  return fixed.replaceFirst(RegExp(r'\.00$'), '');
}

bool _missing(String? value) => value == null || value.trim().isEmpty;

bool _different(String? left, String? right) {
  if (_missing(left) || _missing(right)) return false;
  return left!.trim().toLowerCase() != right!.trim().toLowerCase();
}
