import 'package:flutter/material.dart';

import 'invoice_review_authority_contract.dart';
import 'invoice_review_authority_runtime_adapter.dart';
import 'invoice_review_form_view_model.dart';
import 'invoice_transaction_handoff_contract.dart';

class InvoiceTransactionHandoffReviewCard extends StatefulWidget {
  const InvoiceTransactionHandoffReviewCard({
    super.key,
    required this.initialReview,
    required this.onOpenDraft,
    this.aiComparisonRequired = false,
    this.aiComparisonAcknowledged = false,
    this.comparisonRevision = 0,
    this.contract = const InvoiceTransactionHandoffContract(),
    this.authorityAdapter = const InvoiceReviewAuthorityRuntimeAdapter(),
  });

  static const Key confirmKey = Key('invoice_transaction_handoff_confirm');
  static const Key handoffKey = Key('invoice_transaction_handoff_open_draft');
  static const Key reconfirmKey = Key('invoice_transaction_handoff_reconfirm');
  static const Key disclaimerKey = Key('invoice_transaction_handoff_disclaimer');
  static const Key errorKey = Key('invoice_transaction_handoff_error');

  static Key fieldKey(InvoiceReviewFieldKey key) =>
      Key('invoice_transaction_handoff_field_${key.name}');

  static Key authorityKey(InvoiceReviewFieldKey key) =>
      Key('invoice_transaction_handoff_authority_${key.name}');

  final InvoiceReviewFormViewModel initialReview;
  final ValueChanged<InvoiceTransactionHandoffDraft> onOpenDraft;
  final bool aiComparisonRequired;
  final bool aiComparisonAcknowledged;
  final int comparisonRevision;
  final InvoiceTransactionHandoffContract contract;
  final InvoiceReviewAuthorityRuntimeAdapter authorityAdapter;

  @override
  State<InvoiceTransactionHandoffReviewCard> createState() =>
      _InvoiceTransactionHandoffReviewCardState();
}

class _InvoiceTransactionHandoffReviewCardState
    extends State<InvoiceTransactionHandoffReviewCard> {
  late InvoiceReviewFormViewModel _review;
  final Set<InvoiceReviewFieldKey> _explicitlyCorrectedFields =
      <InvoiceReviewFieldKey>{};
  bool _confirmed = false;
  bool _authorityConfirmed = false;
  bool _needsReconfirm = false;
  bool _edited = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _review = widget.initialReview;
  }

  @override
  void didUpdateWidget(covariant InvoiceTransactionHandoffReviewCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_edited && oldWidget.initialReview != widget.initialReview) {
      _review = widget.initialReview;
      _explicitlyCorrectedFields.clear();
      _authorityConfirmed = false;
    }
    final comparisonChanged =
        oldWidget.comparisonRevision != widget.comparisonRevision ||
        (!oldWidget.aiComparisonRequired && widget.aiComparisonRequired) ||
        (oldWidget.aiComparisonAcknowledged &&
            !widget.aiComparisonAcknowledged);
    if (comparisonChanged) {
      _invalidateConfirmation();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              '人工確認後帶入新增記帳',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            const Text(
              '請先確認或修正辨識欄位。此步驟只形成可編輯交易草稿；付款帳戶、消費類別與正式商家仍須在新增記帳頁明確選擇，最後按「保存」前不會寫入交易。',
            ),
            const SizedBox(height: 12),
            for (final field in _review.fields) ...<Widget>[
              TextFormField(
                key: InvoiceTransactionHandoffReviewCard.fieldKey(field.key),
                initialValue: field.value,
                enabled: field.editable,
                keyboardType: field.key == InvoiceReviewFieldKey.totalAmount
                    ? const TextInputType.numberWithOptions(decimal: true)
                    : null,
                decoration: InputDecoration(
                  labelText:
                      '${field.label}${field.requiredForReview ? ' *' : ''}',
                  helperText: _helperText(field),
                  border: const OutlineInputBorder(),
                ),
                onChanged: (value) => _updateField(field.key, value),
              ),
              if (_authorityLabel(field).isNotEmpty) ...<Widget>[
                const SizedBox(height: 4),
                Text(
                  _authorityLabel(field),
                  key: InvoiceTransactionHandoffReviewCard.authorityKey(
                    field.key,
                  ),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 10),
            ],
            if (_review.requiresAcknowledgement) ...<Widget>[
              CheckboxListTile(
                key: InvoiceTransactionHandoffReviewCard.disclaimerKey,
                contentPadding: EdgeInsets.zero,
                value: _review.disclaimerAcknowledged,
                onChanged: (value) {
                  setState(() {
                    _review = _review.acknowledgeDisclaimer(value == true);
                    _edited = true;
                    _error = '';
                  });
                  _invalidateConfirmation();
                },
                title: const Text('我已確認辨識欄位，並了解目前仍只是覆核草稿'),
              ),
            ],
            if (widget.aiComparisonRequired) ...<Widget>[
              const SizedBox(height: 4),
              Text(
                widget.aiComparisonAcknowledged
                    ? 'AI 第二意見已由你核對。'
                    : '目前已有 AI 第二意見；請先勾選上方「我已核對本機與 AI 結果」。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (_needsReconfirm) ...<Widget>[
              const SizedBox(height: 8),
              const ListTile(
                key: InvoiceTransactionHandoffReviewCard.reconfirmKey,
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.warning_amber_outlined),
                title: Text('覆核內容或第二意見已變更，請重新確認'),
                subtitle: Text('先前的交易草稿 handoff authority 已失效。'),
              ),
            ],
            if (_error.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                _error,
                key: InvoiceTransactionHandoffReviewCard.errorKey,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 10),
            FilledButton.icon(
              key: InvoiceTransactionHandoffReviewCard.confirmKey,
              onPressed: _confirmReview,
              icon: Icon(
                _confirmed ? Icons.check_circle : Icons.fact_check_outlined,
              ),
              label: Text(_confirmed ? '已確認發票覆核' : '確認發票覆核'),
            ),
            if (_confirmed) ...<Widget>[
              const SizedBox(height: 10),
              FilledButton.tonalIcon(
                key: InvoiceTransactionHandoffReviewCard.handoffKey,
                onPressed: _openDraft,
                icon: const Icon(Icons.edit_note_outlined),
                label: const Text('帶入新增記帳'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String? _helperText(InvoiceReviewFieldViewModel field) {
    final parts = <String>[
      if (field.confidenceLabel.trim().isNotEmpty)
        '辨識信心：${field.confidenceLabel.trim()}',
      ...field.warnings.where((item) => item.trim().isNotEmpty),
    ];
    return parts.isEmpty ? null : parts.join('；');
  }

  String _authorityLabel(InvoiceReviewFieldViewModel field) {
    return widget.authorityAdapter.displayLabelForField(
      field,
      explicitlyCorrected: _explicitlyCorrectedFields.contains(field.key),
      explicitlyConfirmed: _authorityConfirmed &&
          InvoiceReviewAuthorityRuntimeAdapter.transactionCoreFields
              .contains(field.key),
    );
  }

  void _updateField(InvoiceReviewFieldKey key, String value) {
    setState(() {
      _review = _review.updateField(key, value);
      _explicitlyCorrectedFields.add(key);
      _authorityConfirmed = false;
      _edited = true;
      _error = '';
    });
    _invalidateConfirmation();
  }

  void _invalidateConfirmation() {
    if (!_confirmed && !_needsReconfirm && !_authorityConfirmed) return;
    setState(() {
      _confirmed = false;
      _authorityConfirmed = false;
      _needsReconfirm = true;
    });
  }

  void _confirmReview() {
    final missing = _review.fields
        .where((field) => field.requiredForReview && field.isBlank)
        .map((field) => field.label)
        .toList(growable: false);
    if (missing.isNotEmpty) {
      setState(() => _error = '請先補齊必要欄位：${missing.join('、')}');
      return;
    }
    if (!_review.canSubmitForReview) {
      setState(() => _error = '請先完成辨識覆核確認。');
      return;
    }
    if (widget.aiComparisonRequired && !widget.aiComparisonAcknowledged) {
      setState(() => _error = '請先核對本機與 AI 結果，再確認發票覆核。');
      return;
    }

    final authorityDecision = widget.authorityAdapter.evaluateTransactionDraft(
      review: _review,
      explicitlyCorrectedFields: _explicitlyCorrectedFields,
      explicitCoreConfirmation: true,
    );
    if (!authorityDecision.isReady) {
      setState(() => _error = _authorityError(authorityDecision));
      return;
    }

    final draft = widget.contract.build(
      review: _review,
      reviewConfirmed: true,
    );
    if (!draft.canOpenTransactionDraft) {
      setState(() => _error = _coreError(draft));
      return;
    }

    setState(() {
      _confirmed = true;
      _authorityConfirmed = true;
      _needsReconfirm = false;
      _error = '';
    });
  }

  String _authorityError(InvoiceReviewAuthorityDecision decision) {
    final field = widget.authorityAdapter.labelForKind(decision.blockingField);
    switch (decision.reasonCode) {
      case InvoiceReviewAuthorityReasonCode.fieldMissing:
        return '$field 缺少可確認的來源證據。';
      case InvoiceReviewAuthorityReasonCode.fieldConflict:
        return '$field 證據互相衝突，請先明確修正後再確認。';
      case InvoiceReviewAuthorityReasonCode.fieldNotAuthoritative:
        return '$field 目前只有補充證據，請人工確認或修正。';
      case InvoiceReviewAuthorityReasonCode.duplicateFieldAuthority:
        return '$field 同時存在多個正式權威，請先解除衝突。';
      case InvoiceReviewAuthorityReasonCode.ready:
        return '發票覆核 authority 已就緒。';
    }
  }

  String _coreError(InvoiceTransactionHandoffDraft draft) {
    if (draft.warnings.contains('INVOICE_NUMBER_REQUIRED')) {
      return '請確認發票號碼後再帶入記帳。';
    }
    if (draft.warnings.contains('TOTAL_AMOUNT_REQUIRED_OR_INVALID')) {
      return '請輸入大於 0 的發票總金額。';
    }
    if (draft.warnings.contains('INVOICE_DATE_TIME_REQUIRED_OR_INVALID')) {
      return '請確認有效的發票日期與時間。';
    }
    return '發票覆核尚未符合交易草稿 handoff 條件。';
  }

  void _openDraft() {
    if (!_confirmed || _needsReconfirm || !_authorityConfirmed) return;
    final authorityDecision = widget.authorityAdapter.evaluateTransactionDraft(
      review: _review,
      explicitlyCorrectedFields: _explicitlyCorrectedFields,
      explicitCoreConfirmation: _authorityConfirmed,
    );
    if (!authorityDecision.isReady) {
      setState(() {
        _confirmed = false;
        _authorityConfirmed = false;
        _needsReconfirm = true;
        _error = _authorityError(authorityDecision);
      });
      return;
    }

    final draft = widget.contract.build(
      review: _review,
      reviewConfirmed: true,
    );
    if (!draft.canOpenTransactionDraft) {
      setState(() {
        _confirmed = false;
        _authorityConfirmed = false;
        _needsReconfirm = true;
        _error = _coreError(draft);
      });
      return;
    }
    widget.onOpenDraft(draft);
  }
}
