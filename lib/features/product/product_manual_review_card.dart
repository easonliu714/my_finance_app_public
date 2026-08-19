import 'package:flutter/material.dart';

import 'product_recognition_candidate.dart';

class ProductManualReviewCard extends StatefulWidget {
  const ProductManualReviewCard({
    super.key,
    required this.candidate,
    required this.onReviewed,
  });

  static const Key productNameFieldKey = Key('product_review_product_name');
  static const Key quantityFieldKey = Key('product_review_quantity');
  static const Key unitPriceFieldKey = Key('product_review_unit_price');
  static const Key totalAmountFieldKey = Key('product_review_total_amount');
  static const Key categoryFieldKey = Key('product_review_category');
  static const Key merchantFieldKey = Key('product_review_merchant');
  static const Key confirmKey = Key('product_review_confirm');

  final ProductRecognitionCandidate candidate;
  final ValueChanged<ProductRecognitionCandidate> onReviewed;

  @override
  State<ProductManualReviewCard> createState() => _ProductManualReviewCardState();
}

class _ProductManualReviewCardState extends State<ProductManualReviewCard> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _productName;
  late final TextEditingController _quantity;
  late final TextEditingController _unitPrice;
  late final TextEditingController _totalAmount;
  late final TextEditingController _category;
  late final TextEditingController _merchant;
  bool _confirmed = false;

  @override
  void initState() {
    super.initState();
    _productName = TextEditingController();
    _quantity = TextEditingController();
    _unitPrice = TextEditingController();
    _totalAmount = TextEditingController();
    _category = TextEditingController();
    _merchant = TextEditingController();
    _loadCandidate(widget.candidate);
  }

  @override
  void didUpdateWidget(covariant ProductManualReviewCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.candidate, widget.candidate)) {
      _loadCandidate(widget.candidate);
      _confirmed = false;
    }
  }

  @override
  void dispose() {
    _productName.dispose();
    _quantity.dispose();
    _unitPrice.dispose();
    _totalAmount.dispose();
    _category.dispose();
    _merchant.dispose();
    super.dispose();
  }

  void _loadCandidate(ProductRecognitionCandidate candidate) {
    _productName.text = candidate.productName;
    _quantity.text = _number(candidate.quantity);
    _unitPrice.text = _number(candidate.unitPrice);
    _totalAmount.text = _number(candidate.totalAmount);
    _category.text = candidate.categorySuggestion;
    _merchant.text = candidate.merchantName;
  }

  @override
  Widget build(BuildContext context) {
    final candidate = widget.candidate;
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
                '所有欄位都可人工修正；空白代表不確認，不會因 AI 候選自動建立正式交易。',
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
                  helperText: candidate.resolvedAmountSource ==
                          ProductRecognitionAmountSource.derivedQuantityTimesUnitPrice
                      ? 'AI 未看到總價；數量 × 單價僅供參考，請人工確認後再填。'
                      : '只有你確認的金額才會保留為覆核值。',
                  border: const OutlineInputBorder(),
                ),
                validator: (value) => _validateNumber(
                  value,
                  positive: false,
                  label: '總金額',
                ),
              ),
              const SizedBox(height: 10),
              TextFormField(
                key: ProductManualReviewCard.categoryFieldKey,
                controller: _category,
                decoration: const InputDecoration(
                  labelText: '分類建議／人工分類',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextFormField(
                key: ProductManualReviewCard.merchantFieldKey,
                controller: _merchant,
                decoration: const InputDecoration(
                  labelText: '商家建議／人工商家',
                  border: OutlineInputBorder(),
                ),
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
                  '已套用人工覆核值；目前仍未建立正式交易。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _confirm() {
    if (_formKey.currentState?.validate() != true) return;
    final reviewed = ProductRecognitionCandidate(
      productName: _productName.text.trim(),
      quantity: _parse(_quantity.text),
      unitPrice: _parse(_unitPrice.text),
      totalAmount: _parse(_totalAmount.text),
      categorySuggestion: _category.text.trim(),
      merchantName: _merchant.text.trim(),
      recognizedText: widget.candidate.recognizedText,
      confidence: widget.candidate.confidence,
      warnings: widget.candidate.warnings,
    );
    setState(() => _confirmed = true);
    widget.onReviewed(reviewed);
  }

  static String? _validateNumber(
    String? raw, {
    required bool positive,
    required String label,
  }) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty) return null;
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
