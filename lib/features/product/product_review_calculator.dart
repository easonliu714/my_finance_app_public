import 'package:flutter/material.dart';

class ProductReviewCalculator {
  const ProductReviewCalculator._();

  static double? evaluateExpression(String expression) {
    try {
      final parser = _ExpressionParser(expression);
      final value = parser.parse();
      if (!value.isFinite) return null;
      return value;
    } catch (_) {
      return null;
    }
  }
}

Future<double?> showProductReviewCalculator(
  BuildContext context, {
  String initialValue = '',
}) {
  return showDialog<double>(
    context: context,
    builder: (context) => _ProductReviewCalculatorDialog(
      initialValue: initialValue,
    ),
  );
}

class _ProductReviewCalculatorDialog extends StatefulWidget {
  const _ProductReviewCalculatorDialog({required this.initialValue});

  final String initialValue;

  @override
  State<_ProductReviewCalculatorDialog> createState() =>
      _ProductReviewCalculatorDialogState();
}

class _ProductReviewCalculatorDialogState
    extends State<_ProductReviewCalculatorDialog> {
  late final TextEditingController _expression;
  double? _result;
  String? _error;

  @override
  void initState() {
    super.initState();
    _expression = TextEditingController(text: widget.initialValue.trim());
    _recalculate(silent: true);
  }

  @override
  void dispose() {
    _expression.dispose();
    super.dispose();
  }

  void _append(String value) {
    final selection = _expression.selection;
    final text = _expression.text;
    final start = selection.start < 0 ? text.length : selection.start;
    final end = selection.end < 0 ? text.length : selection.end;
    _expression.value = TextEditingValue(
      text: text.replaceRange(start, end, value),
      selection: TextSelection.collapsed(offset: start + value.length),
    );
    _recalculate(silent: true);
  }

  void _backspace() {
    final text = _expression.text;
    if (text.isEmpty) return;
    final selection = _expression.selection;
    final start = selection.start < 0 ? text.length : selection.start;
    final end = selection.end < 0 ? text.length : selection.end;
    if (start != end) {
      _expression.value = TextEditingValue(
        text: text.replaceRange(start, end, ''),
        selection: TextSelection.collapsed(offset: start),
      );
    } else if (start > 0) {
      _expression.value = TextEditingValue(
        text: text.replaceRange(start - 1, start, ''),
        selection: TextSelection.collapsed(offset: start - 1),
      );
    }
    _recalculate(silent: true);
  }

  void _clear() {
    _expression.clear();
    setState(() {
      _result = null;
      _error = null;
    });
  }

  void _recalculate({bool silent = false}) {
    final text = _expression.text.trim();
    if (text.isEmpty) {
      setState(() {
        _result = null;
        _error = null;
      });
      return;
    }
    final value = ProductReviewCalculator.evaluateExpression(text);
    setState(() {
      _result = value;
      _error = value == null && !silent ? '算式格式不正確，請重新確認。' : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    const keys = <String>[
      '7', '8', '9', '÷',
      '4', '5', '6', '×',
      '1', '2', '3', '−',
      '0', '.', '(', '+',
      ')', '⌫', 'C', '=',
    ];
    return AlertDialog(
      scrollable: true,
      title: const Text('計算總金額'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const Key('product_review_calculator_expression'),
              controller: _expression,
              keyboardType: TextInputType.text,
              decoration: const InputDecoration(
                labelText: '算式',
                hintText: '例如：(45 + 27) × 0.9',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => _recalculate(silent: true),
            ),
            const SizedBox(height: 8),
            Text(
              _result == null ? '結果：—' : '結果：${_number(_result!)}',
              key: const Key('product_review_calculator_result'),
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            if (_error != null) ...[
              const SizedBox(height: 4),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: 4,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
              childAspectRatio: 1.6,
              children: [
                for (final keyText in keys)
                  OutlinedButton(
                    onPressed: () {
                      switch (keyText) {
                        case '⌫':
                          _backspace();
                          return;
                        case 'C':
                          _clear();
                          return;
                        case '=':
                          _recalculate();
                          return;
                        default:
                          _append(keyText);
                          return;
                      }
                    },
                    child: Text(keyText),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              '可先加總多項商品，再乘折扣或扣除優惠；結果不會自動寫入，需按「帶入總金額」。',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const Key('product_review_calculator_apply'),
          onPressed: _result == null || _result! <= 0
              ? null
              : () => Navigator.of(context).pop(_result),
          child: const Text('帶入總金額'),
        ),
      ],
    );
  }

  static String _number(double value) {
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value
        .toStringAsFixed(4)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }
}

class _ExpressionParser {
  _ExpressionParser(String input)
      : _input = input
            .replaceAll('×', '*')
            .replaceAll('÷', '/')
            .replaceAll('−', '-')
            .replaceAll(RegExp(r'\s+'), '');

  final String _input;
  int _index = 0;

  double parse() {
    if (_input.isEmpty) throw const FormatException();
    final value = _parseExpression();
    if (_index != _input.length) throw const FormatException();
    return value;
  }

  double _parseExpression() {
    var value = _parseTerm();
    while (_match('+') || _match('-')) {
      final operator = _input[_index - 1];
      final right = _parseTerm();
      value = operator == '+' ? value + right : value - right;
    }
    return value;
  }

  double _parseTerm() {
    var value = _parseFactor();
    while (_match('*') || _match('/')) {
      final operator = _input[_index - 1];
      final right = _parseFactor();
      if (operator == '/' && right == 0) throw const FormatException();
      value = operator == '*' ? value * right : value / right;
    }
    return value;
  }

  double _parseFactor() {
    if (_match('+')) return _parseFactor();
    if (_match('-')) return -_parseFactor();
    if (_match('(')) {
      final value = _parseExpression();
      if (!_match(')')) throw const FormatException();
      return value;
    }
    return _parseNumber();
  }

  double _parseNumber() {
    final start = _index;
    var seenDot = false;
    while (_index < _input.length) {
      final code = _input.codeUnitAt(_index);
      if (code >= 48 && code <= 57) {
        _index += 1;
        continue;
      }
      if (_input[_index] == '.' && !seenDot) {
        seenDot = true;
        _index += 1;
        continue;
      }
      break;
    }
    if (start == _index) throw const FormatException();
    final value = double.tryParse(_input.substring(start, _index));
    if (value == null || !value.isFinite) throw const FormatException();
    return value;
  }

  bool _match(String token) {
    if (_index >= _input.length || _input[_index] != token) return false;
    _index += 1;
    return true;
  }
}
