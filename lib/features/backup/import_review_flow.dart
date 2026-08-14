import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import 'import_dry_run_report.dart';
import 'import_mapping_analysis_service.dart';
import 'import_mapping_conflict_report.dart';
import 'import_mapping_decision_editor.dart';
import 'import_mapping_decision_service.dart';
import 'readable_import_commit_service.dart';
import 'readable_import_service.dart';

class ImportReviewFlow extends StatefulWidget {
  const ImportReviewFlow({
    super.key,
    required this.dryRunResult,
    required this.mappingAnalysis,
    this.initialDecisions = const ImportMappingDecisionSet(),
    this.onDecisionChanged,
    this.database,
    this.commitService = const ReadableImportCommitService(),
  });

  final ReadableImportDryRunResult dryRunResult;
  final ImportMappingAnalysisResult mappingAnalysis;
  final ImportMappingDecisionSet initialDecisions;
  final ValueChanged<ImportMappingDecisionSet>? onDecisionChanged;
  final DatabaseExecutor? database;
  final ReadableImportCommitService commitService;

  @override
  State<ImportReviewFlow> createState() => _ImportReviewFlowState();
}

class _ImportReviewFlowState extends State<ImportReviewFlow> {
  final ImportMappingDecisionService _decisionService = const ImportMappingDecisionService();
  late ImportMappingDecisionSet _decisions;
  var _currentStep = 0;

  @override
  void initState() {
    super.initState();
    _decisions = widget.initialDecisions;
  }

  @override
  void didUpdateWidget(covariant ImportReviewFlow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialDecisions != widget.initialDecisions || oldWidget.mappingAnalysis != widget.mappingAnalysis || oldWidget.dryRunResult != widget.dryRunResult) {
      _decisions = widget.initialDecisions;
      _currentStep = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final validation = _decisionService.validate(analysis: widget.mappingAnalysis, decisions: _decisions);
    return NestedScrollView(
      headerSliverBuilder: (context, innerBoxIsScrolled) => <Widget>[
        SliverToBoxAdapter(child: _FlowHeader(validation: validation)),
        SliverPersistentHeader(
          pinned: true,
          delegate: _StepNavigationHeaderDelegate(
            extent: _currentStep < _StepNavigation.stepCount - 1 ? 128 : 72,
            child: _StepNavigation(
              currentStep: _currentStep,
              onStepSelected: (step) => setState(() => _currentStep = step),
            ),
          ),
        ),
      ],
      body: _buildCurrentStepContent(validation),
    );
  }

  Widget _buildCurrentStepContent(ImportMappingDecisionValidationResult validation) {
    switch (_currentStep) {
      case 0:
        return ImportDryRunReport(result: widget.dryRunResult);
      case 1:
        return ImportMappingConflictReport(result: widget.mappingAnalysis);
      case 2:
        return ImportMappingDecisionEditor(analysis: widget.mappingAnalysis, initialDecisions: _decisions, onChanged: _handleDecisionChanged);
      case 3:
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _ReviewSummary(
              dryRunResult: widget.dryRunResult,
              mappingAnalysis: widget.mappingAnalysis,
              decisions: _decisions,
              validation: validation,
              database: widget.database,
              commitService: widget.commitService,
            ),
          ],
        );
      default:
        return const SizedBox.shrink();
    }
  }

  void _handleDecisionChanged(ImportMappingDecisionSet decisions) {
    setState(() => _decisions = decisions);
    widget.onDecisionChanged?.call(decisions);
  }
}

class _FlowHeader extends StatelessWidget {
  const _FlowHeader({required this.validation});

  final ImportMappingDecisionValidationResult validation;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('匯入審核流程', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          const Text('本階段提供審核、確認閘門與 reviewed commit service；不會自動新增主檔，正式寫入仍需通過 validation 並明確勾選確認。'),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            Chip(label: Text(validation.canCommit ? '可繼續' : 'Blocked')),
            Chip(label: Text('阻擋 ${validation.blockingIssues.length}')),
            Chip(label: Text('未處理類別 ${validation.unresolvedCategories.length}')),
            Chip(label: Text('未處理商家 ${validation.unresolvedMerchants.length}')),
          ]),
        ]),
      ),
    );
  }
}

class _StepNavigationHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _StepNavigationHeaderDelegate({required this.child, required this.extent});

  final Widget child;
  final double extent;

  @override
  double get minExtent => extent;

  @override
  double get maxExtent => extent;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return SizedBox.expand(child: child);
  }

  @override
  bool shouldRebuild(covariant _StepNavigationHeaderDelegate oldDelegate) {
    return oldDelegate.child != child || oldDelegate.extent != extent;
  }
}

class _StepNavigation extends StatelessWidget {
  const _StepNavigation({required this.currentStep, required this.onStepSelected});

  final int currentStep;
  final ValueChanged<int> onStepSelected;

  static const int stepCount = 4;
  static const List<String> _labels = <String>[
    'Step 1｜Dry-run report',
    'Step 2｜Mapping / conflict report',
    'Step 3｜Mapping decision',
    'Step 4｜Review summary',
  ];

  @override
  Widget build(BuildContext context) {
    final nextStep = currentStep + 1;
    return Material(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            _StepButton(
              index: currentStep,
              currentStep: currentStep,
              label: '目前｜${_labels[currentStep]}',
              onStepSelected: onStepSelected,
            ),
            if (nextStep < _labels.length) ...[
              const SizedBox(height: 8),
              _StepButton(
                index: nextStep,
                currentStep: currentStep,
                label: '下一步｜${_labels[nextStep]}',
                onStepSelected: onStepSelected,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.index, required this.currentStep, required this.label, required this.onStepSelected});

  final int index;
  final int currentStep;
  final String label;
  final ValueChanged<int> onStepSelected;

  @override
  Widget build(BuildContext context) {
    final selected = index == currentStep;
    final child = Text(label);
    return selected ? FilledButton(onPressed: () => onStepSelected(index), child: child) : OutlinedButton(onPressed: () => onStepSelected(index), child: child);
  }
}

class _ReviewSummary extends StatelessWidget {
  const _ReviewSummary({required this.dryRunResult, required this.mappingAnalysis, required this.decisions, required this.validation, required this.database, required this.commitService});

  final ReadableImportDryRunResult dryRunResult;
  final ImportMappingAnalysisResult mappingAnalysis;
  final ImportMappingDecisionSet decisions;
  final ImportMappingDecisionValidationResult validation;
  final DatabaseExecutor? database;
  final ReadableImportCommitService commitService;

  @override
  Widget build(BuildContext context) {
    final blocked = !validation.canCommit;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('最終確認摘要', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(blocked ? '狀態：Blocked，仍有阻擋項目需要處理。' : '狀態：可繼續，可進入正式寫入前確認閘門。'),
              const SizedBox(height: 12),
              _SummaryLine(label: '匯入總列數', value: dryRunResult.totalRows),
              _SummaryLine(label: '可匯入列數', value: dryRunResult.readyToInsertRows),
              _SummaryLine(label: '錯誤列數', value: dryRunResult.invalidRows),
              _SummaryLine(label: '重複列數', value: dryRunResult.duplicateRows),
              _SummaryLine(label: '阻擋項目', value: validation.blockingIssues.length),
              _SummaryLine(label: '未處理類別', value: validation.unresolvedCategories.length),
              _SummaryLine(label: '未處理商家', value: validation.unresolvedMerchants.length),
              if (validation.blockingIssues.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('阻擋原因', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                for (final issue in validation.blockingIssues) Text('• ${issue.message}'),
              ],
            ]),
          ),
        ),
        const SizedBox(height: 12),
        _ExplicitConfirmationGate(
          dryRunResult: dryRunResult,
          mappingAnalysis: mappingAnalysis,
          decisions: decisions,
          validation: validation,
          database: database,
          commitService: commitService,
        ),
      ],
    );
  }
}

class _ExplicitConfirmationGate extends StatefulWidget {
  const _ExplicitConfirmationGate({required this.dryRunResult, required this.mappingAnalysis, required this.decisions, required this.validation, required this.database, required this.commitService});

  final ReadableImportDryRunResult dryRunResult;
  final ImportMappingAnalysisResult mappingAnalysis;
  final ImportMappingDecisionSet decisions;
  final ImportMappingDecisionValidationResult validation;
  final DatabaseExecutor? database;
  final ReadableImportCommitService commitService;

  @override
  State<_ExplicitConfirmationGate> createState() => _ExplicitConfirmationGateState();
}

class _ExplicitConfirmationGateState extends State<_ExplicitConfirmationGate> {
  var _confirmed = false;
  var _isCommitting = false;
  String? _message;
  ReadableImportCommitResult? _commitResult;

  bool get _canConfirm => widget.validation.canCommit && widget.dryRunResult.readyToInsertRows > 0 && widget.database != null;
  bool get _canPressImport => _canConfirm && _confirmed && !_isCommitting;

  @override
  void didUpdateWidget(covariant _ExplicitConfirmationGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_canConfirm && (_confirmed || _message != null || _commitResult != null)) {
      _confirmed = false;
      _message = null;
      _commitResult = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reason = _blockedReason();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('正式寫入前確認閘門', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          const Text('正式寫入會在 validation 通過且使用者明確勾選後，將 ready-to-insert rows 寫入 transactions。invalid / duplicate rows 不會寫入。'),
          const SizedBox(height: 12),
          _SummaryLine(label: '將寫入列數', value: widget.dryRunResult.readyToInsertRows),
          _SummaryLine(label: '不寫入錯誤列', value: widget.dryRunResult.invalidRows),
          _SummaryLine(label: '不寫入重複列', value: widget.dryRunResult.duplicateRows),
          _SummaryLine(label: '仍需處理阻擋項目', value: widget.validation.blockingIssues.length),
          _SummaryLine(label: '未處理類別', value: widget.validation.unresolvedCategories.length),
          _SummaryLine(label: '未處理商家', value: widget.validation.unresolvedMerchants.length),
          const SizedBox(height: 8),
          if (!_canConfirm) Text(reason, style: TextStyle(color: theme.colorScheme.error, fontWeight: FontWeight.w700)),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _confirmed,
            onChanged: _canConfirm ? (value) => setState(() => _confirmed = value ?? false) : null,
            title: const Text('我已確認 dry-run、mapping decision 與摘要；同意將可匯入資料寫入 transactions。'),
            subtitle: const Text('系統會再次執行 validation guard，並跳過 invalid / duplicate rows。'),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: _canPressImport ? _commit : null,
              icon: _isCommitting ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.verified_user_outlined),
              label: Text(_isCommitting ? '匯入中...' : '確認匯入'),
            ),
          ),
          if (_message != null) ...[
            const SizedBox(height: 12),
            Text(_message!, style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
          if (_commitResult != null) ...[
            const SizedBox(height: 12),
            _SummaryLine(label: '已寫入列數', value: _commitResult!.insertedRows),
            _SummaryLine(label: '已跳過列數', value: _commitResult!.skippedRows),
            _SummaryLine(label: 'commit 時重複列數', value: _commitResult!.duplicateAtCommitRows),
            _SummaryLine(label: '寫入失敗列數', value: _commitResult!.failedRows),
          ],
        ]),
      ),
    );
  }

  Future<void> _commit() async {
    final db = widget.database;
    if (db == null) return;
    setState(() {
      _isCommitting = true;
      _message = null;
      _commitResult = null;
    });
    try {
      final result = await widget.commitService.commitReviewedTransactions(
        db,
        dryRunResult: widget.dryRunResult,
        mappingAnalysis: widget.mappingAnalysis,
        decisions: widget.decisions,
        confirmed: _confirmed,
      );
      setState(() {
        _commitResult = result;
        _message = result.blockingIssues.isEmpty ? '匯入完成。' : '匯入未執行：仍有阻擋項目。';
      });
    } catch (error) {
      setState(() => _message = '匯入失敗：$error');
    } finally {
      if (mounted) setState(() => _isCommitting = false);
    }
  }

  String _blockedReason() {
    if (!widget.validation.canCommit) return '確認閘門尚未開啟：仍有阻擋項目需要處理。';
    if (widget.dryRunResult.readyToInsertRows <= 0) return '確認閘門尚未開啟：沒有可匯入列數。';
    if (widget.database == null) return '確認閘門尚未開啟：目前沒有可寫入的資料庫 context。';
    return '';
  }
}

class _SummaryLine extends StatelessWidget {
  const _SummaryLine({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(label), Text('$value', style: const TextStyle(fontWeight: FontWeight.w800))]),
    );
  }
}
