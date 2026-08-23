import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../account/account_repository.dart';
import '../category/expense_category_repository.dart';
import '../category/expense_category_schema.dart';
import '../merchant/canonical_merchant_repository.dart';
import '../transaction/transaction_entry_page.dart';
import '../transaction/transaction_type.dart';
import 'voice_speech_recognition.dart';
import 'voice_transaction_parser.dart';

class VoiceTransactionEntryPage extends StatefulWidget {
  const VoiceTransactionEntryPage({
    super.key,
    this.parser = const VoiceTransactionParser(),
    this.speechPort,
    this.categoryOptionsOverride,
    this.merchantOptionsOverride,
    this.accountOptionsOverride,
  });

  static const String routeName = 'voice-transaction-entry';
  static const String routePath = '/transaction/voice';

  static const Key transcriptFieldKey = Key('voice_transaction_transcript');
  static const Key exampleKey = Key('voice_transaction_example');
  static const Key microphoneKey = Key('voice_transaction_microphone');
  static const Key parseKey = Key('voice_transaction_parse');
  static const Key candidateKey = Key('voice_transaction_candidate');
  static const Key amountKey = Key('voice_transaction_amount');
  static const Key categoryKey = Key('voice_transaction_category');
  static const Key merchantKey = Key('voice_transaction_merchant');
  static const Key accountKey = Key('voice_transaction_account');
  static const Key confirmKey = Key('voice_transaction_confirm');
  static const Key reconfirmKey = Key('voice_transaction_reconfirm_required');
  static const Key handoffKey = Key('voice_transaction_handoff');

  static const String exampleTranscript =
      '我在OK便利商店用一卡通支付72元，買了1杯大熱拿、一個花生吐司';

  static String mergeLiveTranscript(String current, String incoming) {
    final left = current.trim();
    final right = incoming.trim();
    if (left.isEmpty) return right;
    if (right.isEmpty) return left;
    if (left == right) return left;

    final normalizedLeft = _normalizeSpeechText(left);
    final normalizedRight = _normalizeSpeechText(right);
    if (normalizedLeft.isEmpty) return right;
    if (normalizedRight.isEmpty) return left;
    if (normalizedLeft == normalizedRight) {
      return right.length >= left.length ? right : left;
    }
    if (normalizedRight.startsWith(normalizedLeft)) return right;
    if (normalizedLeft.startsWith(normalizedRight)) return left;

    final boundary = _lastSpeechBoundary(left);
    if (boundary >= 0 && boundary + 1 < left.length) {
      final prefix = left.substring(0, boundary + 1);
      final tail = left.substring(boundary + 1).trim();
      final normalizedTail = _normalizeSpeechText(tail);
      if (normalizedTail.length >= 2 &&
          normalizedRight.startsWith(normalizedTail)) {
        return '$prefix$right';
      }
      if (normalizedTail.length >= 2 &&
          normalizedTail.startsWith(normalizedRight)) {
        return left;
      }
    }

    final lengthDelta = (normalizedLeft.length - normalizedRight.length).abs();
    if (lengthDelta <= 3) {
      final distance = _editDistance(normalizedLeft, normalizedRight);
      final maxLength = normalizedLeft.length > normalizedRight.length
          ? normalizedLeft.length
          : normalizedRight.length;
      if (distance <= 2 || (maxLength >= 8 && distance * 4 <= maxLength)) {
        return right;
      }
    }

    if (RegExp(r'[，、。；;,.!?！？]$').hasMatch(left)) {
      return '$left$right';
    }
    return '$left，$right';
  }

  static String _normalizeSpeechText(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[\s，、。；;,.!?！？：:]'), '');
  }

  static int _lastSpeechBoundary(String value) {
    var result = -1;
    for (final token in const ['，', '、', '。', '；', ';', ',', '.', '!', '?', '！', '？']) {
      final index = value.lastIndexOf(token);
      if (index > result) result = index;
    }
    return result;
  }

  static int _editDistance(String left, String right) {
    if (left == right) return 0;
    if (left.isEmpty) return right.length;
    if (right.isEmpty) return left.length;

    var previous = List<int>.generate(right.length + 1, (index) => index);
    for (var i = 1; i <= left.length; i += 1) {
      final current = List<int>.filled(right.length + 1, 0);
      current[0] = i;
      for (var j = 1; j <= right.length; j += 1) {
        final substitutionCost =
            left.codeUnitAt(i - 1) == right.codeUnitAt(j - 1) ? 0 : 1;
        final deletion = previous[j] + 1;
        final insertion = current[j - 1] + 1;
        final substitution = previous[j - 1] + substitutionCost;
        var best = deletion < insertion ? deletion : insertion;
        if (substitution < best) best = substitution;
        current[j] = best;
      }
      previous = current;
    }
    return previous[right.length];
  }

  final VoiceTransactionParser parser;
  final VoiceSpeechRecognitionPort? speechPort;
  final List<String>? categoryOptionsOverride;
  final List<String>? merchantOptionsOverride;
  final List<String>? accountOptionsOverride;

  @override
  State<VoiceTransactionEntryPage> createState() =>
      _VoiceTransactionEntryPageState();
}

class _VoiceTransactionEntryPageState extends State<VoiceTransactionEntryPage> {
  final _reviewFormKey = GlobalKey<FormState>();
  late final TextEditingController _transcriptController;
  late final TextEditingController _amountController;
  late final VoiceSpeechRecognitionPort _speechPort;

  VoiceTransactionParseCandidate? _candidate;
  bool _referenceDataBusy = false;
  bool _speechBusy = false;
  bool _speechListening = false;
  bool _reviewConfirmed = false;
  bool _reviewNeedsReconfirm = false;
  String _speechMessage = '可直接輸入文字；只有按下麥克風時才會啟動系統語音辨識。';
  String? _selectedCategory;
  String? _selectedMerchant;
  String? _selectedAccount;
  List<String> _categoryOptions = const <String>[];
  List<String> _merchantOptions = const <String>['不使用商家'];
  List<String> _accountOptions = const <String>[];

  @override
  void initState() {
    super.initState();
    _transcriptController = TextEditingController();
    _amountController = TextEditingController();
    _speechPort = widget.speechPort ?? PlatformVoiceSpeechRecognitionPort();
    _loadReferenceData();
  }

  @override
  void dispose() {
    unawaited(_speechPort.cancel());
    _transcriptController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final candidate = _candidate;
    return Scaffold(
      appBar: AppBar(title: const Text('語音／文字快速記帳')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.record_voice_over_outlined),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '先確認文字，再解析成記帳草稿',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '語音辨識只在你按下麥克風後啟動；不做背景聆聽，也不保存原始錄音。你可以隨時改用文字輸入。',
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: VoiceTransactionEntryPage.transcriptFieldKey,
                    controller: _transcriptController,
                    minLines: 3,
                    maxLines: 6,
                    textInputAction: TextInputAction.newline,
                    decoration: const InputDecoration(
                      labelText: '交易描述',
                      hintText: VoiceTransactionEntryPage.exampleTranscript,
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => _invalidateParsedState(),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        key: VoiceTransactionEntryPage.exampleKey,
                        onPressed: _speechBusy ? null : _applyExample,
                        icon: const Icon(Icons.lightbulb_outline),
                        label: const Text('套用範例'),
                      ),
                      FilledButton.tonalIcon(
                        key: VoiceTransactionEntryPage.microphoneKey,
                        onPressed: _speechBusy ? null : _toggleSpeech,
                        icon: Icon(
                          _speechListening ? Icons.stop_circle_outlined : Icons.mic_none_outlined,
                        ),
                        label: Text(_speechListening ? '停止聆聽' : '語音輸入'),
                      ),
                      FilledButton.icon(
                        key: VoiceTransactionEntryPage.parseKey,
                        onPressed: _referenceDataBusy || _speechBusy
                            ? null
                            : _parseTranscript,
                        icon: const Icon(Icons.auto_fix_high_outlined),
                        label: const Text('解析交易'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _speechMessage,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (_referenceDataBusy) ...[
                    const SizedBox(height: 8),
                    const LinearProgressIndicator(),
                  ],
                ],
              ),
            ),
          ),
          if (candidate != null) ...[
            const SizedBox(height: 14),
            _CandidateCard(candidate: candidate),
            const SizedBox(height: 14),
            _buildReviewCard(candidate),
          ],
        ],
      ),
    );
  }

  Widget _buildReviewCard(VoiceTransactionParseCandidate candidate) {
    final intentReady = candidate.intent == VoiceTransactionIntent.expense;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _reviewFormKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '人工覆核',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              const Text(
                '解析器不會建立商家、帳戶或交易。請從正式資料中選擇必要欄位；確認後仍只形成交易草稿。',
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: VoiceTransactionEntryPage.amountKey,
                controller: _amountController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: '總金額 *',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => _invalidateConfirmedReview(),
                validator: (raw) {
                  final value = double.tryParse(raw?.trim() ?? '');
                  if (value == null || !value.isFinite || value <= 0) {
                    return '請輸入大於 0 的總金額';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                key: VoiceTransactionEntryPage.categoryKey,
                // ignore: deprecated_member_use
                value: _categoryOptions.contains(_selectedCategory)
                    ? _selectedCategory
                    : null,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: '消費類別 *',
                  helperText: '語句不明確時不猜類別，請由你選擇。',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final value in _categoryOptions)
                    DropdownMenuItem(value: value, child: Text(value)),
                ],
                onChanged: (value) {
                  _invalidateConfirmedReview();
                  setState(() => _selectedCategory = value);
                },
                validator: (value) => value == null || value.trim().isEmpty
                    ? '請選擇消費類別'
                    : null,
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                key: VoiceTransactionEntryPage.merchantKey,
                // ignore: deprecated_member_use
                value: _merchantOptions.contains(_selectedMerchant)
                    ? _selectedMerchant
                    : null,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: '消費商家 *',
                  helperText: _merchantHelperText(candidate),
                  border: const OutlineInputBorder(),
                ),
                items: [
                  for (final value in _merchantOptions)
                    DropdownMenuItem(value: value, child: Text(value)),
                ],
                onChanged: (value) {
                  _invalidateConfirmedReview();
                  setState(() => _selectedMerchant = value);
                },
                validator: (value) => value == null || value.trim().isEmpty
                    ? '請選擇現有商家或「不使用商家」'
                    : null,
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                key: VoiceTransactionEntryPage.accountKey,
                // ignore: deprecated_member_use
                value: _accountOptions.contains(_selectedAccount)
                    ? _selectedAccount
                    : null,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: '消費扣款帳戶 *',
                  helperText: _accountHelperText(candidate),
                  border: const OutlineInputBorder(),
                ),
                items: [
                  for (final value in _accountOptions)
                    DropdownMenuItem(value: value, child: Text(value)),
                ],
                onChanged: (value) {
                  _invalidateConfirmedReview();
                  setState(() => _selectedAccount = value);
                },
                validator: (value) => value == null || value.trim().isEmpty
                    ? '請選擇目前有效的扣款帳戶'
                    : null,
              ),
              if (!intentReady) ...[
                const SizedBox(height: 10),
                const Text(
                  '目前無法確認這是一筆支出；請修改交易描述後重新解析。',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
              if (_reviewNeedsReconfirm) ...[
                const SizedBox(height: 10),
                const ListTile(
                  key: VoiceTransactionEntryPage.reconfirmKey,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.warning_amber_outlined),
                  title: Text('覆核內容已變更，請重新確認'),
                  subtitle: Text('先前的交易草稿已失效；重新確認前不可帶入新增記帳。'),
                ),
              ],
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: VoiceTransactionEntryPage.confirmKey,
                  onPressed: intentReady ? _confirmReview : null,
                  icon: Icon(
                    _reviewConfirmed ? Icons.check_circle : Icons.fact_check_outlined,
                  ),
                  label: Text(
                    _reviewConfirmed ? '已確認人工覆核' : '確認人工覆核',
                  ),
                ),
              ),
              if (_reviewConfirmed) ...[
                const SizedBox(height: 10),
                const Text('目前仍是交易草稿；尚未建立任何正式交易。'),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    key: VoiceTransactionEntryPage.handoffKey,
                    onPressed: _openTransactionEntry,
                    icon: const Icon(Icons.edit_note_outlined),
                    label: const Text('帶入新增記帳'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _loadReferenceData() async {
    if (widget.categoryOptionsOverride != null ||
        widget.merchantOptionsOverride != null ||
        widget.accountOptionsOverride != null) {
      setState(() {
        _categoryOptions = _normalize(
          widget.categoryOptionsOverride ?? canonicalDefaultExpenseCategories,
        );
        _merchantOptions = _normalize(<String>[
          '不使用商家',
          ...?widget.merchantOptionsOverride,
        ]);
        _accountOptions = _normalize(widget.accountOptionsOverride ?? const <String>[]);
      });
      return;
    }

    setState(() => _referenceDataBusy = true);
    try {
      final categories = await ExpenseCategoryRepository.instance.listActive();
      final merchants = await CanonicalMerchantRepository.instance.listMerchants();
      final accounts = await AccountRepository.instance.listAccounts();
      if (!mounted) return;
      setState(() {
        _categoryOptions = _normalize(<String>[
          ...canonicalDefaultExpenseCategories,
          ...categories.map((item) => item.name),
        ]);
        _merchantOptions = _normalize(<String>[
          '不使用商家',
          ...merchants.map((item) => item.displayName),
        ]);
        _accountOptions = _normalize(
          accounts.where((item) => !item.isArchived).map((item) => item.displayName),
        );
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _categoryOptions = _normalize(canonicalDefaultExpenseCategories);
        _merchantOptions = const <String>['不使用商家'];
        _accountOptions = const <String>[];
        _speechMessage = '正式資料讀取失敗；帳戶保持空白，因此目前不能確認交易草稿。';
      });
    } finally {
      if (mounted) setState(() => _referenceDataBusy = false);
    }
  }

  void _applyExample() {
    _transcriptController.text = VoiceTransactionEntryPage.exampleTranscript;
    _transcriptController.selection = TextSelection.collapsed(
      offset: _transcriptController.text.length,
    );
    _invalidateParsedState();
  }

  Future<void> _toggleSpeech() async {
    if (_speechListening || _speechPort.isListening) {
      setState(() => _speechBusy = true);
      await _speechPort.stop();
      if (!mounted) return;
      setState(() {
        _speechBusy = false;
        _speechListening = false;
        _speechMessage = '已停止語音輸入；請確認文字內容後再解析。';
      });
      return;
    }

    setState(() {
      _speechBusy = true;
      _speechMessage = '正在啟動系統語音辨識…';
    });
    final result = await _speechPort.start(
      onResult: _handleSpeechResult,
      onStatus: _handleSpeechStatus,
      onError: _handleSpeechError,
    );
    if (!mounted) return;
    setState(() {
      _speechBusy = false;
      _speechListening = result.started;
      _speechMessage = result.started
          ? '正在聆聽；停止後可先修正文字，再按「解析交易」。'
          : result.message;
    });
  }

  void _handleSpeechResult(String words, bool isFinal) {
    if (!mounted || words.trim().isEmpty) return;
    setState(() {
      final merged = VoiceTransactionEntryPage.mergeLiveTranscript(
        _transcriptController.text,
        words,
      );
      _transcriptController.text = merged;
      _transcriptController.selection = TextSelection.collapsed(
        offset: _transcriptController.text.length,
      );
      _invalidateParsedState(setStateRequired: false);
      if (isFinal) {
        _speechMessage = '語音辨識完成；請先確認或修改文字，再解析交易。';
      }
    });
  }

  void _handleSpeechStatus(String status) {
    if (!mounted) return;
    final normalized = status.toLowerCase();
    final listening = normalized.contains('listening');
    final finished = normalized.contains('done') ||
        normalized.contains('notlistening') ||
        normalized.contains('not listening');
    setState(() {
      if (listening) _speechListening = true;
      if (finished) _speechListening = false;
    });
  }

  void _handleSpeechError(String message) {
    if (!mounted) return;
    setState(() {
      _speechBusy = false;
      _speechListening = false;
      _speechMessage = message;
    });
  }

  Future<void> _parseTranscript() async {
    if (_speechListening || _speechPort.isListening) {
      await _speechPort.stop();
      if (!mounted) return;
    }
    final candidate = widget.parser.parse(_transcriptController.text);
    final matchedMerchant = VoiceTransactionReferenceMatcher.matchUnique(
      candidate.merchantCandidate,
      _merchantOptions.where((item) => item != '不使用商家'),
    );
    final matchedAccount = VoiceTransactionReferenceMatcher.matchUnique(
      candidate.accountCandidate,
      _accountOptions,
    );
    setState(() {
      _candidate = candidate;
      _amountController.text = _number(candidate.amount);
      _selectedCategory = null;
      _selectedMerchant = matchedMerchant;
      _selectedAccount = matchedAccount;
      _reviewConfirmed = false;
      _reviewNeedsReconfirm = false;
      _speechListening = false;
    });
  }

  void _invalidateParsedState({bool setStateRequired = true}) {
    void change() {
      _candidate = null;
      _amountController.clear();
      _selectedCategory = null;
      _selectedMerchant = null;
      _selectedAccount = null;
      _reviewConfirmed = false;
      _reviewNeedsReconfirm = false;
    }

    if (setStateRequired) {
      setState(change);
    } else {
      change();
    }
  }

  void _invalidateConfirmedReview() {
    if (!_reviewConfirmed && !_reviewNeedsReconfirm) return;
    setState(() {
      _reviewConfirmed = false;
      _reviewNeedsReconfirm = true;
    });
  }

  void _confirmReview() {
    final candidate = _candidate;
    if (candidate == null || candidate.intent != VoiceTransactionIntent.expense) return;
    if (_reviewFormKey.currentState?.validate() != true) return;
    setState(() {
      _reviewConfirmed = true;
      _reviewNeedsReconfirm = false;
    });
  }

  void _openTransactionEntry() {
    final candidate = _candidate;
    final amount = double.tryParse(_amountController.text.trim());
    final category = _selectedCategory?.trim() ?? '';
    final merchant = _selectedMerchant?.trim() ?? '';
    final account = _selectedAccount?.trim() ?? '';
    if (!_reviewConfirmed ||
        _reviewNeedsReconfirm ||
        candidate == null ||
        candidate.intent != VoiceTransactionIntent.expense ||
        amount == null ||
        !amount.isFinite ||
        amount <= 0 ||
        category.isEmpty ||
        merchant.isEmpty ||
        account.isEmpty) {
      return;
    }

    context.pushNamed(
      TransactionEntryPage.routeName,
      extra: TransactionEntrySeed(
        initialType: TransactionType.expense,
        accountName: account,
        amount: amount,
        category: category,
        merchantName: merchant,
        note: _buildSafeNote(candidate),
      ),
    );
  }

  String _merchantHelperText(VoiceTransactionParseCandidate candidate) {
    final raw = candidate.merchantCandidate.trim();
    if (raw.isEmpty) return '未辨識商家；請選現有商家或明確選擇「不使用商家」。';
    final matched = VoiceTransactionReferenceMatcher.matchUnique(
      raw,
      _merchantOptions.where((item) => item != '不使用商家'),
    );
    return matched == null
        ? '辨識候選：$raw；沒有唯一正式商家匹配，請人工選擇。'
        : '辨識候選已唯一匹配正式商家：$matched';
  }

  String _accountHelperText(VoiceTransactionParseCandidate candidate) {
    final raw = candidate.accountCandidate.trim();
    if (raw.isEmpty) return '未辨識付款方式；請從目前有效帳戶中選擇。';
    final matched = VoiceTransactionReferenceMatcher.matchUnique(raw, _accountOptions);
    return matched == null
        ? '辨識候選：$raw；沒有唯一有效帳戶匹配，請人工選擇。'
        : '辨識候選已唯一匹配有效帳戶：$matched';
  }

  static String _buildSafeNote(VoiceTransactionParseCandidate candidate) {
    final parts = <String>['來源：語音／文字快速記帳'];
    if (candidate.items.isNotEmpty) {
      parts.add(
        '商品：${candidate.items.map((item) {
          final quantity = item.quantity == null ? '' : ' × ${_number(item.quantity)}';
          return '${item.name}$quantity';
        }).join('、')}',
      );
    }
    return parts.join('\n');
  }

  static List<String> _normalize(Iterable<String> values) {
    final seen = <String>{};
    final result = <String>[];
    for (final raw in values) {
      final value = raw.trim();
      if (value.isNotEmpty && seen.add(value)) result.add(value);
    }
    return List<String>.unmodifiable(result);
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

class _CandidateCard extends StatelessWidget {
  const _CandidateCard({required this.candidate});

  final VoiceTransactionParseCandidate candidate;

  @override
  Widget build(BuildContext context) {
    final itemText = candidate.items.isEmpty
        ? '未提供商品明細'
        : candidate.items
            .map((item) {
              final quantity = item.quantity == null
                  ? ''
                  : ' × ${_VoiceTransactionEntryPageState._number(item.quantity)}';
              return '${item.name}$quantity';
            })
            .join('、');
    return Card(
      key: VoiceTransactionEntryPage.candidateKey,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '解析候選',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text('交易類型：${candidate.isExpense ? '支出' : '待人工確認'}'),
            Text('商家候選：${candidate.merchantCandidate.isEmpty ? '未辨識' : candidate.merchantCandidate}'),
            Text('付款候選：${candidate.accountCandidate.isEmpty ? '未辨識' : candidate.accountCandidate}'),
            Text('總金額：${candidate.amount == null ? '未辨識' : _VoiceTransactionEntryPageState._number(candidate.amount)}'),
            Text('商品：$itemText'),
            if (candidate.warnings.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '需覆核：${candidate.warnings.join('、')}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
