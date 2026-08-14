import 'package:flutter/material.dart';

import 'invoice_review_form_view_model.dart';
import 'invoice_review_submission_gate.dart';

class InvoiceReviewFormCard extends StatefulWidget {
  const InvoiceReviewFormCard({
    super.key,
    required this.initialModel,
    this.onChanged,
    this.onContinue,
  });

  static const Key acknowledgementKey =
      Key('invoice_review_acknowledgement');
  static const Key continueKey = Key('invoice_review_continue');
  static const Key blockedKey = Key('invoice_review_blocked');
  static const Key missingKey = Key('invoice_review_missing');

  static Key fieldKey(InvoiceReviewFieldKey key) =>
      Key('invoice_review_field_${key.name}');

  final InvoiceReviewFormViewModel initialModel;
  final ValueChanged<InvoiceReviewFormViewModel>? onChanged;
  final ValueChanged<InvoiceReviewFormViewModel>? onContinue;

  @override
  State<InvoiceReviewFormCard> createState() =>
      _InvoiceReviewFormCardState();
}

class _InvoiceReviewFormCardState extends State<InvoiceReviewFormCard> {
  late InvoiceReviewFormViewModel _model;
  final Map<InvoiceReviewFieldKey, TextEditingController> _controllers =
      <InvoiceReviewFieldKey, TextEditingController>{};

  @override
  void initState() {
    super.initState();
    _model = widget.initialModel;
    for (final field in _model.fields) {
      _controllers[field.key] = TextEditingController(text: field.value);
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _changeField(InvoiceReviewFieldKey key, String value) {
    setState(() => _model = _model.updateField(key, value));
    widget.onChanged?.call(_model);
  }

  void _acknowledge(bool value) {
    setState(() => _model = _model.acknowledgeDisclaimer(value));
    widget.onChanged?.call(_model);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              _model.title,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(_model.routeReason),
            if (_model.warnings.isNotEmpty) ...<Widget>[
              const SizedBox(height: 12),
              for (final warning in _model.warnings)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Icon(Icons.warning_amber_rounded, size: 18),
                      const SizedBox(width: 6),
                      Expanded(child: Text(warning)),
                    ],
                  ),
                ),
            ],
            const SizedBox(height: 12),
            if (!_model.canOpenReview)
              const Text(
                '\u6b64\u8fa8\u8b58\u7d50\u679c\u5c1a\u4e0d\u80fd\u9032\u5165\u8cc7\u6599\u8986\u6838\uff0c\u8acb\u91cd\u65b0\u62cd\u651d\u3001\u6307\u5b9a QR \u6216\u6539\u7528\u624b\u52d5\u8f38\u5165\u3002',
                key: InvoiceReviewFormCard.blockedKey,
              )
            else ...<Widget>[
              for (final field in _model.fields) ...<Widget>[
                TextField(
                  key: InvoiceReviewFormCard.fieldKey(field.key),
                  controller: _controllers[field.key],
                  enabled: field.editable,
                  keyboardType: field.key == InvoiceReviewFieldKey.totalAmount
                      ? const TextInputType.numberWithOptions(decimal: true)
                      : TextInputType.text,
                  onChanged: (value) => _changeField(field.key, value),
                  decoration: InputDecoration(
                    labelText: field.requiredForReview
                        ? '${field.label}\uff08\u5fc5\u586b\uff09'
                        : field.label,
                    helperText: field.confidenceLabel.isEmpty
                        ? null
                        : '\u8fa8\u8b58\u4fe1\u5fc3\u5ea6\uff1a${field.confidenceLabel}',
                    errorText: field.isBlank && field.requiredForReview
                        ? '\u6b64\u6b04\u4f4d\u70ba\u8986\u6838\u5fc5\u586b'
                        : field.warnings.firstOrNull,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              if (_model.lineItems.isNotEmpty) ...<Widget>[
                Text(
                  '\u8fa8\u8b58\u54c1\u9805',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                for (final item in _model.lineItems)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(item.name),
                    subtitle: item.confidenceLabel.isEmpty
                        ? null
                        : Text('\u4fe1\u5fc3\u5ea6\uff1a${item.confidenceLabel}'),
                    trailing: Text(item.amountText),
                  ),
              ],
              if (_model.missingRequiredFieldCount > 0)
                Text(
                  '\u5c1a\u6709 ${_model.missingRequiredFieldCount} \u500b\u5fc5\u586b\u6b04\u4f4d\u672a\u5b8c\u6210\u3002',
                  key: InvoiceReviewFormCard.missingKey,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              CheckboxListTile(
                key: InvoiceReviewFormCard.acknowledgementKey,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _model.disclaimerAcknowledged,
                onChanged: _model.requiresAcknowledgement
                    ? (value) => _acknowledge(value ?? false)
                    : null,
                title: Text(_model.disclaimer),
                subtitle: const Text(
                  '\u52fe\u9078\u53ea\u4ee3\u8868\u5b8c\u6210\u8cc7\u6599\u8986\u6838\uff0c\u4e0d\u6703\u76f4\u63a5\u5efa\u7acb\u6b63\u5f0f\u4ea4\u6613\u3002',
                ),
              ),
              FilledButton.icon(
                key: InvoiceReviewFormCard.continueKey,
                onPressed: _model.canSubmitReviewSafely &&
                        widget.onContinue != null
                    ? () => widget.onContinue!(_model)
                    : null,
                icon: const Icon(Icons.fact_check_outlined),
                label: const Text('\u78ba\u8a8d\u8986\u6838\u8cc7\u6599'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
