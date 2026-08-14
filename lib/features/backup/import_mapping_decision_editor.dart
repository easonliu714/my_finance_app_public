import 'package:flutter/material.dart';

import 'import_mapping_analysis_service.dart';
import 'import_mapping_decision_service.dart';

class ImportMappingDecisionEditor extends StatefulWidget {
  const ImportMappingDecisionEditor({super.key, required this.analysis, this.initialDecisions = const ImportMappingDecisionSet(), this.onChanged});

  final ImportMappingAnalysisResult analysis;
  final ImportMappingDecisionSet initialDecisions;
  final ValueChanged<ImportMappingDecisionSet>? onChanged;

  @override
  State<ImportMappingDecisionEditor> createState() => _ImportMappingDecisionEditorState();
}

class _ImportMappingDecisionEditorState extends State<ImportMappingDecisionEditor> {
  final ImportMappingDecisionService _decisionService = const ImportMappingDecisionService();
  final Map<String, ImportAccountMappingDecision> _accountDecisions = <String, ImportAccountMappingDecision>{};
  final Map<String, TextEditingController> _categoryControllers = <String, TextEditingController>{};
  final Map<String, TextEditingController> _merchantControllers = <String, TextEditingController>{};

  @override
  void initState() {
    super.initState();
    _syncFromInitialDecisions();
  }

  @override
  void didUpdateWidget(covariant ImportMappingDecisionEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.analysis != widget.analysis || oldWidget.initialDecisions != widget.initialDecisions) {
      _disposeControllers();
      _accountDecisions.clear();
      _categoryControllers.clear();
      _merchantControllers.clear();
      _syncFromInitialDecisions();
    }
  }

  @override
  void dispose() {
    _disposeControllers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final decisions = _buildDecisionSet();
    final validation = _decisionService.validate(analysis: widget.analysis, decisions: decisions);
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('匯入對應決策', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              const Text('本階段只產生 mapping decision，不會正式寫入 transactions，也不會自動新增帳戶、類別或商家。'),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: [
                Chip(label: Text(validation.canCommit ? '可進入後續確認' : '仍有阻擋項目')),
                Chip(label: Text('阻擋 ${validation.blockingIssues.length}')),
                Chip(label: Text('未處理類別 ${validation.unresolvedCategories.length}')),
                Chip(label: Text('未處理商家 ${validation.unresolvedMerchants.length}')),
              ]),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        _SectionCard(
          title: '帳戶對應',
          emptyMessage: '沒有帳戶欄位需要決策。',
          children: [for (final reference in widget.analysis.accountReferences) _buildAccountReferenceCard(reference)],
        ),
        const SizedBox(height: 12),
        _SectionCard(
          title: '類別對應',
          emptyMessage: '沒有類別候選值。',
          children: [for (final category in widget.analysis.categories) _buildCategoryField(category)],
        ),
        const SizedBox(height: 12),
        _SectionCard(
          title: '商家對應',
          emptyMessage: '沒有商家候選值。',
          children: [for (final merchant in widget.analysis.merchants) _buildMerchantField(merchant)],
        ),
      ],
    );
  }

  Widget _buildAccountReferenceCard(ImportAccountReferenceAnalysis reference) {
    final decision = _accountDecisions[_accountKey(reference.fieldName, reference.value)];
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${reference.fieldName}｜${reference.value}', style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('狀態：${_statusText(reference.status)}'),
          const SizedBox(height: 8),
          if (reference.candidates.isEmpty)
            const Text('無候選帳戶，需後續新增或人工處理。')
          else
            for (final candidate in reference.candidates)
              _AccountCandidateTile(
                key: ValueKey<String>('account-${reference.fieldName}-${reference.value}-${candidate.id}'),
                candidate: candidate,
                selected: decision?.selectedAccountId == candidate.id,
                onTap: () => _selectAccount(reference, candidate),
              ),
        ]),
      ),
    );
  }

  Widget _buildCategoryField(String category) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        key: ValueKey<String>('category-$category'),
        controller: _categoryControllers[category],
        decoration: InputDecoration(labelText: '類別：$category', hintText: '輸入對應後類別', border: const OutlineInputBorder()),
        onChanged: (_) => _handleTextMappingChanged(),
      ),
    );
  }

  Widget _buildMerchantField(String merchant) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        key: ValueKey<String>('merchant-$merchant'),
        controller: _merchantControllers[merchant],
        decoration: InputDecoration(labelText: '商家：$merchant', hintText: '輸入對應後商家', border: const OutlineInputBorder()),
        onChanged: (_) => _handleTextMappingChanged(),
      ),
    );
  }

  void _syncFromInitialDecisions() {
    for (final decision in widget.initialDecisions.accountDecisions) {
      _accountDecisions[_accountKey(decision.fieldName, decision.importedValue)] = decision;
    }
    for (final category in widget.analysis.categories) {
      final decision = widget.initialDecisions.categoryDecisionFor(category);
      _categoryControllers[category] = TextEditingController(text: decision?.mappedCategory ?? '');
    }
    for (final merchant in widget.analysis.merchants) {
      final decision = widget.initialDecisions.merchantDecisionFor(merchant);
      _merchantControllers[merchant] = TextEditingController(text: decision?.mappedMerchant ?? '');
    }
  }

  void _selectAccount(ImportAccountReferenceAnalysis reference, ImportAccountCandidate candidate) {
    setState(() {
      _accountDecisions[_accountKey(reference.fieldName, reference.value)] = ImportAccountMappingDecision(fieldName: reference.fieldName, importedValue: reference.value, selectedAccountId: candidate.id, selectedDisplayName: candidate.displayName);
    });
    _emitChanged();
  }

  void _handleTextMappingChanged() {
    setState(() {});
    _emitChanged();
  }

  void _emitChanged() => widget.onChanged?.call(_buildDecisionSet());

  ImportMappingDecisionSet _buildDecisionSet() {
    final categoryDecisions = <ImportCategoryMappingDecision>[];
    for (final entry in _categoryControllers.entries) {
      final mapped = entry.value.text.trim();
      if (mapped.isNotEmpty) categoryDecisions.add(ImportCategoryMappingDecision(importedCategory: entry.key, mappedCategory: mapped));
    }
    final merchantDecisions = <ImportMerchantMappingDecision>[];
    for (final entry in _merchantControllers.entries) {
      final mapped = entry.value.text.trim();
      if (mapped.isNotEmpty) merchantDecisions.add(ImportMerchantMappingDecision(importedMerchant: entry.key, mappedMerchant: mapped));
    }
    return ImportMappingDecisionSet(accountDecisions: _accountDecisions.values.toList(), categoryDecisions: categoryDecisions, merchantDecisions: merchantDecisions);
  }

  void _disposeControllers() {
    for (final controller in _categoryControllers.values) {
      controller.dispose();
    }
    for (final controller in _merchantControllers.values) {
      controller.dispose();
    }
  }

  String _accountKey(String fieldName, String importedValue) => '$fieldName::$importedValue';
}

class _AccountCandidateTile extends StatelessWidget {
  const _AccountCandidateTile({super.key, required this.candidate, required this.selected, required this.onTap});

  final ImportAccountCandidate candidate;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(selected ? Icons.radio_button_checked : Icons.radio_button_unchecked, color: selected ? colorScheme.primary : null),
      title: Text(candidate.displayName),
      subtitle: Text(candidate.id),
      onTap: onTap,
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
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          if (children.isEmpty) Text(emptyMessage) else ...children,
        ]),
      ),
    );
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
