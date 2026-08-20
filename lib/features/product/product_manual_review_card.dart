import 'package:flutter/material.dart';

import 'product_recognition_candidate.dart';
import 'product_transaction_handoff.dart';

class ProductManualReviewCard extends StatefulWidget {
  const ProductManualReviewCard({
    super.key,
    required this.candidate,
    required this.categoryOptions,
    required this.merchantOptions,
    required this.accountOptions,
    required this.onReviewed,
    this.onReviewInvalidated,
    this.onAddCategory,
    this.onAddMerchant,
  });

  static const Key productNameFieldKey = Key('product_review_product_name');
  static const Key quantityFieldKey = Key('product_review_quantity');
  static const Key unitPriceFieldKey = Key('product_review_unit_price');
  static const Key totalAmountFieldKey = Key('product_review_total_amount');
  static const Key restoreAutoTotalKey = Key('product_review_restore_auto_total');
  static const Key categoryFieldKey = Key('product_review_category');
  static const Key addCategoryKey = Key('product_review_add_category');
  static const Key merchantFieldKey = Key('product_review_merchant');
  static const Key addMerchantKey = Key('product_review_add_merchant');
  static const Key accountFieldKey = Key('product_review_account');
  static const Key confirmKey = Key('product_review_confirm');

  final ProductRecognitionCandidate candidate;
  final List<String> categoryOptions;
  final List<String> merchantOptions;
  final List<String> accountOptions;
  final ValueChanged<ProductTransactionDraftSeed> onReviewed;
  final VoidCallback? onReviewInvalidated;
  final Future<String?> Function(String name)? onAddCategory;
  final Future<String?> Function(String name)? onAddMerchant;

  @override
  State<ProductManualReviewCard> createState() => _ProductManualReviewCardState();
}

class _ProductManualReviewCardState extends State<ProductManualReviewCard> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _productName;
  late final TextEditingController _quantity;
  late final TextEditingController _unitPrice;
  late final TextEditingController _totalAmount;
  bool _confirmed = false;
  bool _totalManualOverride = false;
  String? _selectedCategory;
  String? _selectedMerchant;
  String? _selectedAccount;

  @override
  void initState() {
    super.initState();
    _productName = TextEditingController();
    _quantity = TextEditingController();
    _unitPrice = TextEditingController();
    _totalAmount = TextEditingController();
    _loadCandidate(widget.candidate);
  }

  @override
  void didUpdateWidget(covariant ProductManualReviewCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.candidate, widget.candidate)) {
      _loadCandidate(widget.candidate);
      _confirmed = false;
      return;
    }
    if (_selectedCategory == null &&
        widget.categoryOptions.contains(widget.candidate.categorySuggestion)) {
      _selectedCategory = widget.candidate.categorySuggestion;
    }
    if ((_selectedMerchant == null || _selectedMerchant == '不使用商家') &&
        widget.merchantOptions.contains(widget.candidate.merchantName)) {
      _selectedMerchant = widget.candidate.merchantName;
    }
    if (_selectedAccount != null &&
        !widget.accountOptions.contains(_selectedAccount)) {
      final wasConfirmed = _confirmed;
      _selectedAccount = null;
      _confirmed = false;
      if (wasConfirmed) widget.onReviewInvalidated?.call();
    }
  }

  @override
  void dispose() {
    _productName.dispose();
    _quantity.dispose();
    _unitPrice.dispose();
    _totalAmount.dispose();
    super.dispose();
  }

  void _loadCandidate(ProductRecognitionCandidate candidate) {
    _productName.text = candidate.productName;
    _quantity.text = _number(candidate.quantity);
    _unitPrice.text = _number(candidate.unitPrice);
    _selectedCategory = widget.categoryOptions.contains(candidate.categorySuggestion)
        ? candidate.categorySuggestion
        : null;
    _selectedMerchant = widget.merchantOptions.contains(candidate.merchantName)
        ? candidate.merchantName
        : widget.merchantOptions.contains('不使用商家')
            ? '不使用商家'
            : null;
    _selectedAccount = null;

    final autoTotal = _calculatedTotal();
    if (autoTotal != null) {
      _totalManualOverride = false;
      _totalAmount.text = _number(autoTotal);
    } else {
      _totalManualOverride = candidate.totalAmount != null;
      _totalAmount.text = _number(candidate.totalAmount);
    }
  }

  @override
  Widget build(BuildContext context) {
    final candidate = widget.candidate;
    final autoTotal = _calculatedTotal();
    final aiTotal = candidate.totalAmount;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.fact_check_outlined),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'AI 商品候選 · 人工覆核',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'AI 只提供初始候選。類別、商家與扣款帳戶都由正式資料來源選擇；確認後仍不會直接建立交易。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 14),
              TextFormField(
                key: ProductManualReviewCard.productNameFieldKey,
                controller: _productName,
                decoration: const InputDecoration(
                  labelText: '商品名稱',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => _invalidateConfirmedReview(),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      key: ProductManualReviewCard.quantityFieldKey,
                      controller: _quantity,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: '數量',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => _recalculateTotalIfAutomatic(),
                      validator: (value) => _validateNumber(
                        value,
                        positive: true,
                        label: '數量',
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      key: ProductManualReviewCard.unitPriceFieldKey,
                      controller: _unitPrice,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: '單價',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => _recalculateTotalIfAutomatic(),
                      validator: (value) => _validateNumber(
                        value,
                        positive: false,
                        label: '單價',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextFormField(
                key: ProductManualReviewCard.totalAmountFieldKey,
                controller: _totalAmount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: '總金額',
                  helperText: _totalHelperText(
                    autoTotal: autoTotal,
                    aiTotal: aiTotal,
                  ),
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) {
                  _invalidateConfirmedReview();
                  if (!_totalManualOverride) {
                    setState(() => _totalManualOverride = true);
                  }
                },
                validator: (value) => _validateNumber(
                  value,
                  positive: true,
                  label: '總金額',
                ),
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  key: ProductManualReviewCard.restoreAutoTotalKey,
                  onPressed: _calculatedTotal() == null ? null : _restoreAutoTotal,
                  icon: const Icon(Icons.calculate_outlined),
                  label: const Text('恢復自動計算'),
                ),
              ),
              DropdownButtonFormField<String>(
                key: ProductManualReviewCard.categoryFieldKey,
                // `value` is intentionally retained for a controlled dropdown:
                // initialValue would not follow explicit add/review state updates.
                // ignore: deprecated_member_use
                value: widget.categoryOptions.contains(_selectedCategory)
                    ? _selectedCategory
                    : null,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: '消費類別',
                  helperText: _categoryHelperText(candidate),
                  border: const OutlineInputBorder(),
                ),
                items: [
                  for (final category in widget.categoryOptions)
                    DropdownMenuItem(value: category, child: Text(category)),
                ],
                onChanged: (value) {
                  _invalidateConfirmedReview();
                  setState(() => _selectedCategory = value);
                },
                validator: (value) => value == null || value.trim().isEmpty
                    ? '請選擇消費類別'
                    : null,
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  key: ProductManualReviewCard.addCategoryKey,
                  onPressed: widget.onAddCategory == null ? null : _addCategory,
                  icon: const Icon(Icons.add),
                  label: const Text('新增類別'),
                ),
              ),
              DropdownButtonFormField<String>(
                key: ProductManualReviewCard.merchantFieldKey,
                // See category dropdown: this must remain controlled on rebuild.
                // ignore: deprecated_member_use
                value: widget.merchantOptions.contains(_selectedMerchant)
                    ? _selectedMerchant
                    : null,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: '消費商家',
                  helperText: _merchantHelperText(candidate),
                  border: const OutlineInputBorder(),
                ),
                items: [
                  for (final merchant in widget.merchantOptions)
                    DropdownMenuItem(value: merchant, child: Text(merchant)),
                ],
                onChanged: (value) {
                  _invalidateConfirmedReview();
                  setState(() => _selectedMerchant = value);
                },
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  key: ProductManualReviewCard.addMerchantKey,
                  onPressed: widget.onAddMerchant == null ? null : _addMerchant,
                  icon: const Icon(Icons.add_business_outlined),
                  label: const Text('新增商家'),
                ),
              ),
              DropdownButtonFormField<String>(
                key: ProductManualReviewCard.accountFieldKey,
                // Account selection is also controlled by formal master refreshes.
                // ignore: deprecated_member_use
                value: widget.accountOptions.contains(_selectedAccount)
                    ? _selectedAccount
                    : null,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: '消費扣款帳戶 *',
                  helperText: '只列出目前有效帳戶；AI 不會猜測付款帳戶。',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final account in widget.accountOptions)
                    DropdownMenuItem(value: account, child: Text(account)),
                ],
                onChanged: (value) {
                  _invalidateConfirmedReview();
                  setState(() => _selectedAccount = value);
                },
                validator: (value) => value == null || value.trim().isEmpty
                    ? '請選擇消費扣款帳戶'
                    : null,
              ),
              if (candidate.warnings.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  'AI 注意事項：${candidate.warnings.join('、')}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: ProductManualReviewCard.confirmKey,
                  onPressed: _confirm,
                  icon: Icon(_confirmed ? Icons.check_circle : Icons.edit_note),
                  label: Text(_confirmed ? '已確認人工覆核' : '確認人工覆核'),
                ),
              ),
              if (_confirmed) ...[
                const SizedBox(height: 8),
                Text(
                  '已採用人工覆核值；目前只是一份交易草稿，尚未建立正式交易。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _invalidateConfirmedReview() {
    if (!_confirmed) return;
    setState(() => _confirmed = false);
    widget.onReviewInvalidated?.call();
  }

  void _recalculateTotalIfAutomatic() {
    _invalidateConfirmedReview();
    if (_totalManualOverride) return;
    final total = _calculatedTotal();
    setState(() {
      _totalAmount.text = total == null ? '' : _number(total);
    });
  }

  void _restoreAutoTotal() {
    final total = _calculatedTotal();
    if (total == null) return;
    _invalidateConfirmedReview();
    setState(() {
      _totalManualOverride = false;
      _totalAmount.text = _number(total);
    });
  }

  double? _calculatedTotal() {
    final quantity = _parse(_quantity.text);
    final unitPrice = _parse(_unitPrice.text);
    if (quantity == null || quantity <= 0 || unitPrice == null || unitPrice < 0) {
      return null;
    }
    return quantity * unitPrice;
  }

  String _totalHelperText({required double? autoTotal, required double? aiTotal}) {
    if (_totalManualOverride) {
      final reference = autoTotal == null ? '' : '；參考計算 ${_number(autoTotal)}';
      return '人工修改模式$reference';
    }
    if (autoTotal != null) {
      final ai = aiTotal != null && aiTotal != autoTotal
          ? '；AI 辨識總額 ${_number(aiTotal)}'
          : '';
      return '自動：數量 × 單價 = ${_number(autoTotal)}$ai';
    }
    return aiTotal == null ? '請輸入數量與單價，或直接人工輸入總額。' : 'AI 辨識總額：${_number(aiTotal)}';
  }

  String? _categoryHelperText(ProductRecognitionCandidate candidate) {
    final suggestion = candidate.categorySuggestion.trim();
    if (suggestion.isEmpty) return '請從正式支出類別中選擇。';
    if (widget.categoryOptions.contains(suggestion)) return 'AI 建議已匹配現有類別：$suggestion';
    return 'AI 建議：$suggestion（目前尚未建立，請改選或明確新增）';
  }

  String? _merchantHelperText(ProductRecognitionCandidate candidate) {
    final suggestion = candidate.merchantName.trim();
    if (suggestion.isEmpty) return '可選現有商家，或使用「不使用商家」。';
    if (widget.merchantOptions.contains(suggestion)) return 'AI 建議已匹配現有商家：$suggestion';
    return 'AI 建議：$suggestion（目前尚未建立，請改選或明確新增）';
  }

  Future<void> _addCategory() async {
    final name = await _askForName('新增消費類別', '類別名稱');
    if (name == null || widget.onAddCategory == null) return;
    final added = await widget.onAddCategory!(name);
    if (!mounted || added == null || added.trim().isEmpty) return;
    _invalidateConfirmedReview();
    setState(() => _selectedCategory = added);
  }

  Future<void> _addMerchant() async {
    final name = await _askForName('新增消費商家', '商家名稱');
    if (name == null || widget.onAddMerchant == null) return;
    final added = await widget.onAddMerchant!(name);
    if (!mounted || added == null || added.trim().isEmpty) return;
    _invalidateConfirmedReview();
    setState(() => _selectedMerchant = added);
  }

  Future<String?> _askForName(String title, String label) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: label),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isNotEmpty) Navigator.of(context).pop(value);
            },
            child: const Text('新增'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  void _confirm() {
    if (_formKey.currentState?.validate() != true) return;
    final quantity = _parse(_quantity.text);
    final unitPrice = _parse(_unitPrice.text);
    final amount = _parse(_totalAmount.text);
    final noteParts = <String>[];
    final productName = _productName.text.trim();
    if (productName.isNotEmpty) noteParts.add('商品：$productName');
    if (quantity != null) noteParts.add('數量：${_number(quantity)}');
    if (unitPrice != null) noteParts.add('單價：${_number(unitPrice)}');
    noteParts.add(
      _totalManualOverride
          ? '總額來源：人工修改'
          : '總額來源：數量×單價自動計算',
    );
    if (widget.candidate.warnings.isNotEmpty) {
      noteParts.add('AI 警告：${widget.candidate.warnings.join('；')}');
    }

    final reviewed = ProductTransactionDraftSeed(
      productName: productName,
      quantity: quantity,
      unitPrice: unitPrice,
      amount: amount,
      totalMode: _totalManualOverride
          ? ProductReviewTotalMode.manualOverride
          : ProductReviewTotalMode.automatic,
      category: _selectedCategory?.trim() ?? '',
      merchant: _selectedMerchant?.trim() ?? '',
      accountName: _selectedAccount?.trim() ?? '',
      note: noteParts.join('\n'),
      reviewedByUser: true,
    );
    if (!reviewed.isReadyForTransactionEntry) return;
    setState(() => _confirmed = true);
    widget.onReviewed(reviewed);
  }

  static String? _validateNumber(
    String? raw, {
    required bool positive,
    required String label,
  }) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty) return positive ? '$label不可空白' : null;
    final parsed = double.tryParse(value);
    if (parsed == null || !parsed.isFinite) return '$label格式不正確';
    if (positive && parsed <= 0) return '$label必須大於 0';
    if (!positive && parsed < 0) return '$label不可小於 0';
    return null;
  }

  static double? _parse(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return null;
    return double.tryParse(value);
  }

  static String _number(double? value) {
    if (value == null) return '';
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value
        .toStringAsFixed(4)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }
}
