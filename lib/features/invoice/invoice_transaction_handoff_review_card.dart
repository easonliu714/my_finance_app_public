import 'package:flutter/material.dart';

import 'gemini/gemini_invoice_review.dart';
import 'invoice_merchant_master_binding_service.dart';
import 'invoice_period_policy.dart';
import 'invoice_review_authority_contract.dart';
import 'invoice_review_authority_runtime_adapter.dart';
import 'invoice_review_field_source_switch.dart';
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
    this.aiCandidate,
    this.contract = const InvoiceTransactionHandoffContract(),
    this.authorityAdapter = const InvoiceReviewAuthorityRuntimeAdapter(),
    this.merchantBindingService = const InvoiceMerchantMasterBindingService(),
  });

  static const Key confirmKey = Key('invoice_transaction_handoff_confirm');
  static const Key handoffKey = Key('invoice_transaction_handoff_open_draft');
  static const Key reconfirmKey = Key('invoice_transaction_handoff_reconfirm');
  static const Key disclaimerKey = Key('invoice_transaction_handoff_disclaimer');
  static const Key errorKey = Key('invoice_transaction_handoff_error');
  static const Key lineItemSourceSwitchKey =
      Key('invoice_transaction_handoff_line_item_source_switch');
  static const Key bindMerchantKey =
      Key('invoice_transaction_handoff_bind_merchant');
  static const Key merchantBindingStatusKey =
      Key('invoice_transaction_handoff_merchant_binding_status');

  static Key fieldKey(InvoiceReviewFieldKey key) =>
      Key('invoice_transaction_handoff_field_${key.name}');

  static Key authorityKey(InvoiceReviewFieldKey key) =>
      Key('invoice_transaction_handoff_authority_${key.name}');

  static Key sourceSwitchKey(InvoiceReviewFieldKey key) =>
      Key('invoice_transaction_handoff_source_${key.name}');

  static Key pickerKey(InvoiceReviewFieldKey key) =>
      Key('invoice_transaction_handoff_picker_${key.name}');

  final InvoiceReviewFormViewModel initialReview;
  final ValueChanged<InvoiceTransactionHandoffDraft> onOpenDraft;
  final bool aiComparisonRequired;
  final bool aiComparisonAcknowledged;
  final int comparisonRevision;
  final GeminiInvoiceReviewCandidate? aiCandidate;
  final InvoiceTransactionHandoffContract contract;
  final InvoiceReviewAuthorityRuntimeAdapter authorityAdapter;
  final InvoiceMerchantMasterBindingService merchantBindingService;

  @override
  State<InvoiceTransactionHandoffReviewCard> createState() =>
      _InvoiceTransactionHandoffReviewCardState();
}

class _InvoiceTransactionHandoffReviewCardState
    extends State<InvoiceTransactionHandoffReviewCard> {
  late InvoiceReviewFormViewModel _review;
  final Map<InvoiceReviewFieldKey, TextEditingController> _controllers =
      <InvoiceReviewFieldKey, TextEditingController>{};
  final Map<InvoiceReviewFieldKey, String> _localFieldValues =
      <InvoiceReviewFieldKey, String>{};
  final Set<InvoiceReviewFieldKey> _explicitlyCorrectedFields =
      <InvoiceReviewFieldKey>{};
  final Set<InvoiceReviewFieldKey> _explicitlyAiSelectedFields =
      <InvoiceReviewFieldKey>{};
  List<InvoiceReviewLineItemViewModel> _localLineItems =
      const <InvoiceReviewLineItemViewModel>[];
  bool _aiLineItemsSelected = false;
  bool _confirmed = false;
  bool _authorityConfirmed = false;
  bool _needsReconfirm = false;
  bool _edited = false;
  bool _merchantBindingBusy = false;
  bool _periodDerivedFromDate = false;
  String _formalMerchantName = '';
  String _merchantBindingStatus = '';
  String _error = '';

  GeminiInvoiceReviewCandidate? get _effectiveAiCandidate =>
      widget.aiCandidate ??
      (widget.aiComparisonRequired
          ? GeminiInvoiceReviewCandidate.latestParsedCandidate
          : null);

  @override
  void initState() {
    super.initState();
    _review = _derivePeriodIfBlank(widget.initialReview);
    _captureLocalBaseline(_review);
    _syncControllers(_review);
  }

  @override
  void didUpdateWidget(covariant InvoiceTransactionHandoffReviewCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_edited && oldWidget.initialReview != widget.initialReview) {
      _review = _derivePeriodIfBlank(widget.initialReview);
      _explicitlyCorrectedFields.clear();
      _explicitlyAiSelectedFields.clear();
      _aiLineItemsSelected = false;
      _authorityConfirmed = false;
      _formalMerchantName = '';
      _merchantBindingStatus = '';
      _captureLocalBaseline(_review);
      _syncControllers(_review);
    }

    final comparisonChanged =
        oldWidget.comparisonRevision != widget.comparisonRevision ||
        (!oldWidget.aiComparisonRequired && widget.aiComparisonRequired) ||
        (oldWidget.aiComparisonAcknowledged &&
            !widget.aiComparisonAcknowledged);
    if (comparisonChanged) {
      _refreshSelectedAiValues();
      _invalidateConfirmation();
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ai = _effectiveAiCandidate;
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
              '每個欄位可直接選擇本機 OCR／QR 或 AI 候選；日期、時間與發票期別可用右側標準選擇器快速輸入。商家主檔必須另外明確新增／綁定，最後按「保存」前不會建立正式交易。',
            ),
            const SizedBox(height: 12),
            for (final field in _review.fields) ...<Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Expanded(
                    child: TextFormField(
                      key: InvoiceTransactionHandoffReviewCard.fieldKey(
                        field.key,
                      ),
                      controller: _controllers[field.key],
                      enabled: field.editable,
                      readOnly: _isStructuredPickerField(field.key),
                      showCursor: !_isStructuredPickerField(field.key),
                      keyboardType:
                          field.key == InvoiceReviewFieldKey.totalAmount
                              ? const TextInputType.numberWithOptions(
                                  decimal: true,
                                )
                              : null,
                      decoration: InputDecoration(
                        labelText:
                            '${field.label}${field.requiredForReview ? ' *' : ''}',
                        helperText: _helperText(field),
                        border: const OutlineInputBorder(),
                        suffixIcon: _isStructuredPickerField(field.key)
                            ? IconButton(
                                key: InvoiceTransactionHandoffReviewCard
                                    .pickerKey(field.key),
                                tooltip: _pickerTooltip(field.key),
                                onPressed: () => _pickStructuredField(field.key),
                                icon: Icon(_pickerIcon(field.key)),
                              )
                            : null,
                      ),
                      onTap: _isStructuredPickerField(field.key)
                          ? () => _pickStructuredField(field.key)
                          : null,
                      onChanged: (value) => _updateField(field.key, value),
                    ),
                  ),
                  if (_canSwitchField(field.key, ai)) ...<Widget>[
                    const SizedBox(width: 8),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: KeyedSubtree(
                        key: InvoiceTransactionHandoffReviewCard.sourceSwitchKey(
                          field.key,
                        ),
                        child: InvoiceReviewFieldSourceSwitch(
                          selection: _sourceSelectionFor(field.key),
                          localLabel: _localSourceLabel(field),
                          aiEnabled: _aiValueFor(field.key, ai).isNotEmpty,
                          onSelected: (selection) =>
                              _selectFieldSource(field.key, selection),
                        ),
                      ),
                    ),
                  ],
                ],
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
            if (_hasAnyLineItems(ai)) ...<Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      '品項明細',
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                  if (_aiLineItems(ai).isNotEmpty)
                    KeyedSubtree(
                      key: InvoiceTransactionHandoffReviewCard
                          .lineItemSourceSwitchKey,
                      child: InvoiceReviewFieldSourceSwitch(
                        selection: _aiLineItemsSelected
                            ? InvoiceReviewFieldSourceSelection.ai
                            : InvoiceReviewFieldSourceSelection.local,
                        localLabel: _localLineItemSourceLabel,
                        onSelected: _selectLineItemSource,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              for (final item in _review.lineItems)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(item.name),
                  subtitle: item.confidenceLabel.trim().isEmpty
                      ? null
                      : Text(item.confidenceLabel.trim()),
                  trailing: item.amountText.trim().isEmpty
                      ? null
                      : Text(item.amountText.trim()),
                ),
              const SizedBox(height: 8),
            ],
            _merchantBindingSection(),
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
                    ? _hasExplicitAiSelection
                        ? 'AI 第二意見已由你核對，並已透過欄位開關明確採用部分 AI 結果。'
                        : 'AI 第二意見已由你核對。'
                    : _hasExplicitAiSelection
                        ? '已選擇部分 AI 欄位；仍需勾選「我已核對本機與 AI 結果」後才能確認。'
                        : '目前已有 AI 第二意見；請先勾選「我已核對本機與 AI 結果」。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (_needsReconfirm) ...<Widget>[
              const SizedBox(height: 8),
              const ListTile(
                key: InvoiceTransactionHandoffReviewCard.reconfirmKey,
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.warning_amber_outlined),
                title: Text('覆核內容或辨識來源已變更，請重新確認'),
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

  Widget _merchantBindingSection() {
    final merchant =
        _review.fieldFor(InvoiceReviewFieldKey.sellerName)?.value.trim() ?? '';
    final taxId =
        _review.fieldFor(InvoiceReviewFieldKey.sellerTaxId)?.value.trim() ?? '';
    if (merchant.isEmpty && taxId.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                _formalMerchantName.isEmpty
                    ? '正式商家尚未綁定'
                    : '正式商家：$_formalMerchantName',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text('候選商家：${merchant.isEmpty ? '未辨識' : merchant}｜賣方統編：${taxId.isEmpty ? '未辨識' : taxId}'),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: InvoiceTransactionHandoffReviewCard.bindMerchantKey,
                onPressed: _merchantBindingBusy || merchant.isEmpty || taxId.isEmpty
                    ? null
                    : _bindMerchantMaster,
                icon: _merchantBindingBusy
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.storefront_outlined),
                label: Text(
                  _formalMerchantName.isEmpty
                      ? '新增／綁定正式商家'
                      : '重新確認商家綁定',
                ),
              ),
              if (_merchantBindingStatus.isNotEmpty)
                Text(
                  _merchantBindingStatus,
                  key: InvoiceTransactionHandoffReviewCard
                      .merchantBindingStatusKey,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ),
        ),
      ),
    );
  }

  String? _helperText(InvoiceReviewFieldViewModel field) {
    final parts = <String>[
      if (field.confidenceLabel.trim().isNotEmpty)
        '辨識信心：${field.confidenceLabel.trim()}',
      if (field.key == InvoiceReviewFieldKey.invoicePeriod &&
          _periodDerivedFromDate)
        '由發票日期自動推算；全年只有 6 個雙月份選項，可點右側調整',
      ...field.warnings.where((item) => item.trim().isNotEmpty),
    ];
    return parts.isEmpty ? null : parts.join('；');
  }

  String _authorityLabel(InvoiceReviewFieldViewModel field) {
    return widget.authorityAdapter.displayLabelForField(
      field,
      explicitlyCorrected: _explicitlyCorrectedFields.contains(field.key),
      explicitlyAiSelected:
          _explicitlyAiSelectedFields.contains(field.key),
      explicitlyConfirmed: _authorityConfirmed &&
          InvoiceReviewAuthorityRuntimeAdapter.transactionCoreFields
              .contains(field.key),
      explicitMasterSelected:
          _formalMerchantName.isNotEmpty &&
          field.key == InvoiceReviewFieldKey.sellerName,
    );
  }

  InvoiceReviewFormViewModel _derivePeriodIfBlank(
    InvoiceReviewFormViewModel model,
  ) {
    final period = model.fieldFor(InvoiceReviewFieldKey.invoicePeriod);
    final date = model.fieldFor(InvoiceReviewFieldKey.invoiceDate)?.value ?? '';
    if (period == null || period.value.trim().isNotEmpty) {
      _periodDerivedFromDate = false;
      return model;
    }
    final derived = deriveInvoicePeriodFromDateText(date);
    if (derived.isEmpty) {
      _periodDerivedFromDate = false;
      return model;
    }
    _periodDerivedFromDate = true;
    return model.updateField(InvoiceReviewFieldKey.invoicePeriod, derived);
  }

  bool _isStructuredPickerField(InvoiceReviewFieldKey key) =>
      key == InvoiceReviewFieldKey.invoiceDate ||
      key == InvoiceReviewFieldKey.invoiceTime ||
      key == InvoiceReviewFieldKey.invoicePeriod;

  IconData _pickerIcon(InvoiceReviewFieldKey key) {
    switch (key) {
      case InvoiceReviewFieldKey.invoiceDate:
        return Icons.calendar_month_outlined;
      case InvoiceReviewFieldKey.invoiceTime:
        return Icons.schedule_outlined;
      case InvoiceReviewFieldKey.invoicePeriod:
        return Icons.date_range_outlined;
      default:
        return Icons.edit_outlined;
    }
  }

  String _pickerTooltip(InvoiceReviewFieldKey key) {
    switch (key) {
      case InvoiceReviewFieldKey.invoiceDate:
        return '選擇發票日期';
      case InvoiceReviewFieldKey.invoiceTime:
        return '選擇交易時間';
      case InvoiceReviewFieldKey.invoicePeriod:
        return '選擇發票期別';
      default:
        return '選擇';
    }
  }

  Future<void> _pickStructuredField(InvoiceReviewFieldKey key) async {
    switch (key) {
      case InvoiceReviewFieldKey.invoiceDate:
        await _pickDate();
        return;
      case InvoiceReviewFieldKey.invoiceTime:
        await _pickTime();
        return;
      case InvoiceReviewFieldKey.invoicePeriod:
        await _pickInvoicePeriod();
        return;
      default:
        return;
    }
  }

  Future<void> _pickDate() async {
    final raw = _review.fieldFor(InvoiceReviewFieldKey.invoiceDate)?.value ?? '';
    final now = DateTime.now();
    final parsed = parseInvoiceReviewDate(raw);
    final initial = parsed == null || parsed.isAfter(now) ? now : parsed;
    final selected = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000, 1, 1),
      lastDate: now,
      helpText: '選擇發票日期',
    );
    if (selected == null || !mounted) return;
    final dateText = '${selected.year.toString().padLeft(4, '0')}-'
        '${selected.month.toString().padLeft(2, '0')}-'
        '${selected.day.toString().padLeft(2, '0')}';
    final periodText = formatInvoicePeriodForDate(selected);
    setState(() {
      _review = _review
          .updateField(InvoiceReviewFieldKey.invoiceDate, dateText)
          .updateField(InvoiceReviewFieldKey.invoicePeriod, periodText);
      _controllers[InvoiceReviewFieldKey.invoiceDate]?.text = dateText;
      _controllers[InvoiceReviewFieldKey.invoicePeriod]?.text = periodText;
      _explicitlyCorrectedFields.add(InvoiceReviewFieldKey.invoiceDate);
      _explicitlyAiSelectedFields
        ..remove(InvoiceReviewFieldKey.invoiceDate)
        ..remove(InvoiceReviewFieldKey.invoicePeriod);
      _periodDerivedFromDate = true;
      _authorityConfirmed = false;
      _edited = true;
      _error = '';
    });
    _invalidateConfirmation();
  }

  Future<void> _pickTime() async {
    final raw = _review.fieldFor(InvoiceReviewFieldKey.invoiceTime)?.value ?? '';
    final normalized = raw
        .trim()
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll('：', ':');
    final match = RegExp(r'^([01]?\d|2[0-3]):([0-5]\d)').firstMatch(normalized);
    final initial = match == null
        ? TimeOfDay.now()
        : TimeOfDay(
            hour: int.parse(match.group(1)!),
            minute: int.parse(match.group(2)!),
          );
    final selected = await showTimePicker(
      context: context,
      initialTime: initial,
      helpText: '選擇交易時間',
    );
    if (selected == null || !mounted) return;
    final value = '${selected.hour.toString().padLeft(2, '0')}:'
        '${selected.minute.toString().padLeft(2, '0')}:00';
    _applyStructuredManualValue(InvoiceReviewFieldKey.invoiceTime, value);
  }

  Future<void> _pickInvoicePeriod() async {
    final rawDate =
        _review.fieldFor(InvoiceReviewFieldKey.invoiceDate)?.value ?? '';
    final date = parseInvoiceReviewDate(rawDate) ?? DateTime.now();
    final options = invoicePeriodOptionsForGregorianYear(date.year);
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.75,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Text(
                  '選擇發票期別（${date.year - 1911} 年）',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: <Widget>[
                    for (final option in options)
                      ListTile(
                        title: Text(option),
                        trailing: option ==
                                (_review
                                        .fieldFor(
                                          InvoiceReviewFieldKey.invoicePeriod,
                                        )
                                        ?.value ??
                                    '')
                            ? const Icon(Icons.check)
                            : null,
                        onTap: () => Navigator.of(context).pop(option),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (selected == null || !mounted) return;
    _periodDerivedFromDate = false;
    _applyStructuredManualValue(InvoiceReviewFieldKey.invoicePeriod, selected);
  }

  void _applyStructuredManualValue(InvoiceReviewFieldKey key, String value) {
    setState(() {
      _review = _review.updateField(key, value);
      _controllers[key]?.text = value;
      _explicitlyCorrectedFields.add(key);
      _explicitlyAiSelectedFields.remove(key);
      _authorityConfirmed = false;
      _edited = true;
      _error = '';
      _invalidateMerchantBindingIfNeeded(key);
    });
    _invalidateConfirmation();
  }

  void _captureLocalBaseline(InvoiceReviewFormViewModel model) {
    _localFieldValues
      ..clear()
      ..addEntries(model.fields.map((field) => MapEntry(field.key, field.value)));
    _localLineItems = List<InvoiceReviewLineItemViewModel>.unmodifiable(
      model.lineItems,
    );
  }

  void _syncControllers(InvoiceReviewFormViewModel model) {
    final active = model.fields.map((field) => field.key).toSet();
    for (final key in _controllers.keys.toList()) {
      if (!active.contains(key)) {
        _controllers.remove(key)?.dispose();
      }
    }
    for (final field in model.fields) {
      final controller = _controllers.putIfAbsent(
        field.key,
        () => TextEditingController(),
      );
      if (controller.text != field.value) controller.text = field.value;
    }
  }

  bool _canSwitchField(
    InvoiceReviewFieldKey key,
    GeminiInvoiceReviewCandidate? ai,
  ) => widget.aiComparisonRequired && _aiValueFor(key, ai).isNotEmpty;

  InvoiceReviewFieldSourceSelection _sourceSelectionFor(
    InvoiceReviewFieldKey key,
  ) {
    if (_explicitlyCorrectedFields.contains(key)) {
      return InvoiceReviewFieldSourceSelection.manual;
    }
    if (_explicitlyAiSelectedFields.contains(key)) {
      return InvoiceReviewFieldSourceSelection.ai;
    }
    return InvoiceReviewFieldSourceSelection.local;
  }

  String _localSourceLabel(InvoiceReviewFieldViewModel field) =>
      field.confidenceLabel.toUpperCase().contains('QR') ? 'QR' : 'OCR';

  String get _localLineItemSourceLabel => _localLineItems.any(
        (item) => item.confidenceLabel.toUpperCase().contains('QR'),
      )
      ? 'QR'
      : 'OCR';

  void _selectFieldSource(
    InvoiceReviewFieldKey key,
    InvoiceReviewFieldSourceSelection selection,
  ) {
    if (selection == InvoiceReviewFieldSourceSelection.manual) return;
    final next = selection == InvoiceReviewFieldSourceSelection.ai
        ? _aiValueFor(key, _effectiveAiCandidate)
        : _localFieldValues[key] ?? '';
    if (selection == InvoiceReviewFieldSourceSelection.ai && next.isEmpty) {
      return;
    }
    setState(() {
      _review = _review.updateField(key, next);
      _controllers[key]?.text = next;
      _explicitlyCorrectedFields.remove(key);
      if (selection == InvoiceReviewFieldSourceSelection.ai) {
        _explicitlyAiSelectedFields.add(key);
      } else {
        _explicitlyAiSelectedFields.remove(key);
      }
      if (key == InvoiceReviewFieldKey.invoiceDate && _periodDerivedFromDate) {
        _syncDerivedPeriodFromCurrentDate();
      } else if (key == InvoiceReviewFieldKey.invoicePeriod) {
        _periodDerivedFromDate = false;
      }
      _edited = true;
      _error = '';
      _invalidateMerchantBindingIfNeeded(key);
    });
    _invalidateConfirmation();
  }

  void _selectLineItemSource(InvoiceReviewFieldSourceSelection selection) {
    if (selection == InvoiceReviewFieldSourceSelection.manual) return;
    final aiItems = _aiLineItems(_effectiveAiCandidate);
    if (selection == InvoiceReviewFieldSourceSelection.ai && aiItems.isEmpty) {
      return;
    }
    setState(() {
      _aiLineItemsSelected = selection == InvoiceReviewFieldSourceSelection.ai;
      _review = _copyReviewWithLineItems(
        _aiLineItemsSelected ? aiItems : _localLineItems,
      );
      _edited = true;
      _error = '';
    });
    _invalidateConfirmation();
  }

  void _updateField(InvoiceReviewFieldKey key, String value) {
    setState(() {
      _review = _review.updateField(key, value);
      _explicitlyCorrectedFields.add(key);
      _explicitlyAiSelectedFields.remove(key);
      if (key == InvoiceReviewFieldKey.invoicePeriod) {
        _periodDerivedFromDate = false;
      }
      _authorityConfirmed = false;
      _edited = true;
      _error = '';
      _invalidateMerchantBindingIfNeeded(key);
    });
    _invalidateConfirmation();
  }

  void _syncDerivedPeriodFromCurrentDate() {
    if (!_periodDerivedFromDate) return;
    final rawDate =
        _review.fieldFor(InvoiceReviewFieldKey.invoiceDate)?.value ?? '';
    final derived = deriveInvoicePeriodFromDateText(rawDate);
    if (derived.isEmpty) return;
    _review = _review.updateField(InvoiceReviewFieldKey.invoicePeriod, derived);
    _controllers[InvoiceReviewFieldKey.invoicePeriod]?.text = derived;
    _explicitlyCorrectedFields.remove(InvoiceReviewFieldKey.invoicePeriod);
    _explicitlyAiSelectedFields.remove(InvoiceReviewFieldKey.invoicePeriod);
  }

  void _invalidateMerchantBindingIfNeeded(InvoiceReviewFieldKey key) {
    if (key != InvoiceReviewFieldKey.sellerName &&
        key != InvoiceReviewFieldKey.sellerTaxId) {
      return;
    }
    _formalMerchantName = '';
    _merchantBindingStatus = '商家名稱或統編已變更，請重新確認正式商家綁定。';
  }

  void _refreshSelectedAiValues() {
    final ai = _effectiveAiCandidate;
    if (ai == null) return;
    for (final key in _explicitlyAiSelectedFields.toList()) {
      final value = _aiValueFor(key, ai);
      if (value.isEmpty) {
        _explicitlyAiSelectedFields.remove(key);
        continue;
      }
      _review = _review.updateField(key, value);
      _controllers[key]?.text = value;
      _invalidateMerchantBindingIfNeeded(key);
    }
    _syncDerivedPeriodFromCurrentDate();
    if (_aiLineItemsSelected) {
      final items = _aiLineItems(ai);
      if (items.isEmpty) {
        _aiLineItemsSelected = false;
        _review = _copyReviewWithLineItems(_localLineItems);
      } else {
        _review = _copyReviewWithLineItems(items);
      }
    }
  }

  bool get _hasExplicitAiSelection =>
      _explicitlyAiSelectedFields.isNotEmpty || _aiLineItemsSelected;

  bool _hasAnyLineItems(GeminiInvoiceReviewCandidate? ai) =>
      _review.lineItems.isNotEmpty || _aiLineItems(ai).isNotEmpty;

  String _aiValueFor(
    InvoiceReviewFieldKey key,
    GeminiInvoiceReviewCandidate? candidate,
  ) {
    if (candidate == null) return '';
    switch (key) {
      case InvoiceReviewFieldKey.invoiceNumber:
        return candidate.invoiceNumber.trim();
      case InvoiceReviewFieldKey.invoiceDate:
        return candidate.invoiceDate.trim();
      case InvoiceReviewFieldKey.invoiceTime:
        return candidate.invoiceTime.trim();
      case InvoiceReviewFieldKey.sellerTaxId:
        return candidate.sellerTaxId.trim();
      case InvoiceReviewFieldKey.sellerName:
        return candidate.merchantName.trim();
      case InvoiceReviewFieldKey.totalAmount:
        return _formatNumber(candidate.totalAmount);
      case InvoiceReviewFieldKey.invoicePeriod:
        return candidate.invoicePeriod.trim();
      case InvoiceReviewFieldKey.randomCode:
        return candidate.randomCode.trim();
    }
  }

  List<InvoiceReviewLineItemViewModel> _aiLineItems(
    GeminiInvoiceReviewCandidate? candidate,
  ) {
    if (candidate == null) return const <InvoiceReviewLineItemViewModel>[];
    return candidate.lineItems
        .map(
          (item) {
            final amount = item.amount ??
                (item.quantity != null && item.unitPrice != null
                    ? item.quantity! * item.unitPrice!
                    : null);
            return InvoiceReviewLineItemViewModel(
              name: item.name.trim(),
              amountText: _formatNumber(amount),
              confidenceLabel: 'AI 明細（使用者明確採用）',
            );
          },
        )
        .where((item) => !item.isBlank)
        .toList(growable: false);
  }

  static String _formatNumber(double? value) {
    if (value == null || !value.isFinite) return '';
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value
        .toStringAsFixed(2)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  InvoiceReviewFormViewModel _copyReviewWithLineItems(
    List<InvoiceReviewLineItemViewModel> lineItems,
  ) {
    return InvoiceReviewFormViewModel(
      title: _review.title,
      routeReason: _review.routeReason,
      disclaimer: _review.disclaimer,
      fields: _review.fields,
      lineItems: List<InvoiceReviewLineItemViewModel>.unmodifiable(lineItems),
      warnings: _review.warnings,
      availableOverrides: _review.availableOverrides,
      canOpenReview: _review.canOpenReview,
      requiresAcknowledgement: _review.requiresAcknowledgement,
      disclaimerAcknowledged: _review.disclaimerAcknowledged,
    );
  }

  bool get _sellerTaxIdIsTrustedQrAuthority {
    final field = _review.fieldFor(InvoiceReviewFieldKey.sellerTaxId);
    if (field == null ||
        !field.confidenceLabel.toUpperCase().contains('QR') ||
        _explicitlyCorrectedFields.contains(InvoiceReviewFieldKey.sellerTaxId) ||
        _explicitlyAiSelectedFields.contains(InvoiceReviewFieldKey.sellerTaxId)) {
      return false;
    }
    return field.value.trim().isNotEmpty;
  }

  Future<void> _bindMerchantMaster() async {
    final merchant =
        _review.fieldFor(InvoiceReviewFieldKey.sellerName)?.value.trim() ?? '';
    final taxId =
        _review.fieldFor(InvoiceReviewFieldKey.sellerTaxId)?.value.trim() ?? '';
    final trustedQr = _sellerTaxIdIsTrustedQrAuthority;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新增／綁定正式商家'),
        content: Text(
          '商家：$merchant\n賣方統編：$taxId\n來源：${trustedQr ? 'QR 原始資料' : '人工／OCR／AI 覆核'}\n\n這會寫入商家主檔並建立統編綁定，但不會建立交易。',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('確認綁定'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _merchantBindingBusy = true;
      _error = '';
    });
    try {
      final result = await widget.merchantBindingService.bind(
        merchantName: merchant,
        sellerTaxId: taxId,
        trustedQrSellerIdentifier: trustedQr,
      );
      if (!mounted) return;
      setState(() {
        if (result.isSuccess && result.merchant != null) {
          _formalMerchantName = result.merchant!.displayName;
          _merchantBindingStatus = result.message;
          _needsReconfirm = true;
          _confirmed = false;
          _authorityConfirmed = false;
        } else {
          _formalMerchantName = '';
          _merchantBindingStatus = result.message;
          _error = result.message;
        }
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _formalMerchantName = '';
          _merchantBindingStatus = '商家綁定失敗，未寫入交易。';
          _error = '商家綁定失敗：${error.runtimeType}';
        });
      }
    } finally {
      if (mounted) setState(() => _merchantBindingBusy = false);
    }
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
      explicitlyAiSelectedFields: _explicitlyAiSelectedFields,
      explicitCoreConfirmation: true,
    );
    if (!authorityDecision.isReady) {
      setState(() => _error = _authorityError(authorityDecision));
      return;
    }

    final draft = widget.contract.build(
      review: _review,
      reviewConfirmed: true,
      formalMerchantName: _formalMerchantName,
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
      explicitlyAiSelectedFields: _explicitlyAiSelectedFields,
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
      formalMerchantName: _formalMerchantName,
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
