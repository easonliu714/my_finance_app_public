import 'package:flutter/material.dart';

import 'gemini_invoice_settings.dart';
import 'gemini_invoice_settings_repository.dart';
import 'gemini_model_catalog_client.dart';

class GeminiInvoiceSettingsCard extends StatefulWidget {
  const GeminiInvoiceSettingsCard({
    super.key,
    this.repository = const GeminiInvoiceSettingsRepository(),
    this.catalogClient,
  });

  static const Key apiKeyFieldKey = Key('gemini_invoice_api_keys');
  static const Key visibilityToggleKey =
      Key('gemini_invoice_api_key_visibility');
  // Retained only so historical tests/source callers still compile. The UI no
  // longer exposes Project/Key Group controls.
  static const Key addGroupKey = Key('gemini_invoice_add_key_group');
  static const Key testKey = Key('gemini_invoice_test_keys');
  static const Key modelDropdownKey = Key('gemini_invoice_model_dropdown');
  static const Key autoReviewToggleKey =
      Key('gemini_invoice_auto_review_low_confidence');
  static const Key saveKey = Key('gemini_invoice_save_settings');
  static const Key clearKey = Key('gemini_invoice_clear_settings');

  static Key groupFieldKey(int index) => Key('gemini_invoice_key_group_$index');
  static Key removeGroupKey(int index) =>
      Key('gemini_invoice_remove_key_group_$index');

  final GeminiInvoiceSettingsRepository repository;
  final GeminiModelCatalogClient? catalogClient;

  @override
  State<GeminiInvoiceSettingsCard> createState() =>
      _GeminiInvoiceSettingsCardState();
}

class _GeminiInvoiceSettingsCardState
    extends State<GeminiInvoiceSettingsCard> {
  late final TextEditingController _keyController;
  late final GeminiModelCatalogClient _catalogClient;
  GeminiInvoiceSettings _settings = const GeminiInvoiceSettings();
  List<GeminiModelDescriptor> _models = const <GeminiModelDescriptor>[];
  List<GeminiApiKeyTestResult> _keyResults = const <GeminiApiKeyTestResult>[];
  var _loading = true;
  var _busy = false;
  var _obscureKeys = true;
  String? _selectedModel;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    _keyController = TextEditingController();
    _catalogClient = widget.catalogClient ?? GeminiModelCatalogClient();
    _load();
  }

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final settings = await widget.repository.load();
      if (!mounted) return;
      _keyController.text = settings.effectiveApiKeys.join('，');
      setState(() {
        _settings = settings;
        _selectedModel = settings.model;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _statusMessage = '無法讀取 Gemini 安全設定。';
      });
    }
  }

  List<String> get _parsedKeys =>
      GeminiInvoiceSettings.parseApiKeys(_keyController.text);

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: LinearProgressIndicator(),
        ),
      );
    }

    final parsedKeys = _parsedKeys;
    final selectedModel = _selectedModel ?? GeminiInvoiceSettings.defaultModel;
    final modelItems = _modelItems(selectedModel);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Icon(Icons.auto_awesome_outlined),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Gemini 發票覆核',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        '輸入一組或多組 Gemini API Key。系統會逐把驗證，辨識時自動依 Key／模型可用性切換；Key 僅保存於系統安全儲存空間。',
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              key: GeminiInvoiceSettingsCard.apiKeyFieldKey,
              controller: _keyController,
              obscureText: _obscureKeys,
              enableSuggestions: false,
              autocorrect: false,
              keyboardType: TextInputType.visiblePassword,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: 'Gemini API Keys',
                hintText: 'AIza…，AIza…，AIza…',
                helperText: '多把 Key 可用空白、逗號、頓號或分號分隔。',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  key: GeminiInvoiceSettingsCard.visibilityToggleKey,
                  tooltip: _obscureKeys ? '顯示全部 API Key' : '隱藏全部 API Key',
                  onPressed: () => setState(() => _obscureKeys = !_obscureKeys),
                  icon: Icon(
                    _obscureKeys
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                ),
              ),
              onChanged: (_) => setState(() {
                _keyResults = const <GeminiApiKeyTestResult>[];
                _statusMessage = null;
              }),
            ),
            const SizedBox(height: 8),
            Text(
              parsedKeys.isEmpty
                  ? '尚未輸入 API Key'
                  : '已解析 ${parsedKeys.length} 組 API Key',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (_keyResults.isNotEmpty) ...<Widget>[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  for (final result in _keyResults)
                    Chip(
                      avatar: Icon(
                        result.available
                            ? Icons.check_circle_outline
                            : Icons.error_outline,
                        size: 18,
                        color: result.available
                            ? Colors.green.shade700
                            : Theme.of(context).colorScheme.error,
                      ),
                      label: Text(
                        'Key #${result.ordinal} ${result.maskedKey}：${result.message}',
                      ),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              key: GeminiInvoiceSettingsCard.testKey,
              onPressed: _busy || parsedKeys.isEmpty ? null : _testAndLoadModels,
              icon: _busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.network_check_outlined),
              label: Text(_busy ? '正在測試並讀取模型…' : '測試 API Keys 並讀取可用模型'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: ValueKey<String>(
                '${GeminiInvoiceSettingsCard.modelDropdownKey}-$selectedModel-${modelItems.length}',
              ),
              initialValue: selectedModel,
              decoration: const InputDecoration(
                labelText: '優先辨識模型',
                helperText: '若此模型不可用，辨識流程會從 Provider 可用清單自動切換 Flash 模型。',
                border: OutlineInputBorder(),
              ),
              items: modelItems,
              onChanged: _busy
                  ? null
                  : (value) => setState(() => _selectedModel = value),
            ),
            const Divider(height: 28),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('啟用 AI 發票覆核'),
              subtitle: const Text('AI 只提供第二意見，不會直接建立交易。切換後立即安全保存。'),
              value: _settings.experimentalInvoiceVisionEnabled,
              onChanged: _busy ? null : _setFeatureEnabled,
            ),
            SwitchListTile.adaptive(
              key: GeminiInvoiceSettingsCard.autoReviewToggleKey,
              contentPadding: EdgeInsets.zero,
              title: const Text('OCR 信心不足時自動 AI 辨識'),
              subtitle: const Text(
                'Local 關鍵欄位缺漏、低信心或有警告時自動啟動 AI；Key／模型不可用時允許有限次自動切換。切換後立即安全保存。',
              ),
              value: _settings.autoReviewLowConfidenceEnabled,
              onChanged: _busy || !_settings.experimentalInvoiceVisionEnabled
                  ? null
                  : _setAutoReviewEnabled,
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('保留發票辨識除錯工具'),
              subtitle: const Text('顯示比較、診斷與證據包匯出。切換後立即安全保存。'),
              value: _settings.debugToolsEnabled,
              onChanged: _busy ? null : _setDebugToolsEnabled,
            ),
            if (_statusMessage != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                _statusMessage!,
                key: const Key('gemini_invoice_settings_status'),
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: <Widget>[
                OutlinedButton.icon(
                  key: GeminiInvoiceSettingsCard.clearKey,
                  onPressed: _busy ? null : _clear,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('清除 Key 與設定'),
                ),
                FilledButton.icon(
                  key: GeminiInvoiceSettingsCard.saveKey,
                  onPressed: _busy ? null : _save,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('安全儲存'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<DropdownMenuItem<String>> _modelItems(String selectedModel) {
    final byId = <String, GeminiModelDescriptor>{
      for (final model in _models) model.id: model,
    };
    byId.putIfAbsent(
      selectedModel,
      () => GeminiModelDescriptor(
        id: selectedModel,
        displayName: selectedModel,
        supportedGenerationMethods: const <String>{'generateContent'},
      ),
    );
    return byId.values
        .map(
          (model) => DropdownMenuItem<String>(
            value: model.id,
            child: Text(
              model.id == GeminiInvoiceSettings.defaultModel
                  ? '${model.displayName}（預設）'
                  : model.displayName,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        )
        .toList(growable: false);
  }

  Future<void> _testAndLoadModels() async {
    final keys = _parsedKeys;
    if (keys.isEmpty) return;
    setState(() {
      _busy = true;
      _statusMessage = null;
      _keyResults = const <GeminiApiKeyTestResult>[];
    });
    try {
      final result = await _catalogClient.validateKeysAndLoadModels(keys);
      if (!mounted) return;
      var nextModel = _selectedModel ?? GeminiInvoiceSettings.defaultModel;
      final availableIds = result.models.map((model) => model.id).toSet();
      if (!availableIds.contains(nextModel)) {
        if (availableIds.contains(GeminiInvoiceSettings.defaultModel)) {
          nextModel = GeminiInvoiceSettings.defaultModel;
        } else if (result.models.isNotEmpty) {
          nextModel = result.models.first.id;
        }
      }
      setState(() {
        _keyResults = result.keyResults;
        _models = result.models;
        _selectedModel = nextModel;
        _statusMessage = result.hasAvailableKey
            ? 'API Key 測試完成；已讀取 ${result.models.length} 個可用模型。'
            : '沒有 API Key 通過測試，設定尚未啟用。';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  GeminiInvoiceSettings _settingsFromForm(GeminiInvoiceSettings base) {
    return base.copyWith(
      apiKeys: _parsedKeys,
      keyGroups: const <GeminiInvoiceKeyGroup>[],
      model: _selectedModel ?? GeminiInvoiceSettings.defaultModel,
    );
  }

  Future<void> _setFeatureEnabled(bool value) async {
    final next = _settings.copyWith(
      experimentalInvoiceVisionEnabled: value,
      // Enabling AI means Local-low-confidence automatic escalation is on by
      // default. The user can explicitly turn that second switch off afterward.
      autoReviewLowConfidenceEnabled: value,
    );
    await _persistImmediate(
      next,
      value ? 'AI 發票覆核與低信心自動辨識已啟用。' : 'AI 發票覆核已停用。',
    );
  }

  Future<void> _setAutoReviewEnabled(bool value) async {
    await _persistImmediate(
      _settings.copyWith(autoReviewLowConfidenceEnabled: value),
      value ? '低信心自動 AI 辨識已啟用。' : '低信心自動 AI 辨識已停用。',
    );
  }

  Future<void> _setDebugToolsEnabled(bool value) async {
    await _persistImmediate(
      _settings.copyWith(debugToolsEnabled: value),
      value ? '發票辨識除錯工具已啟用。' : '發票辨識除錯工具已停用。',
    );
  }

  Future<void> _persistImmediate(
    GeminiInvoiceSettings next,
    String successMessage,
  ) async {
    final previous = _settings;
    final settings = _settingsFromForm(next);
    setState(() {
      _settings = settings;
      _busy = true;
      _statusMessage = null;
    });
    try {
      await widget.repository.save(settings);
      if (!mounted) return;
      setState(() => _statusMessage = successMessage);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _settings = previous;
        _statusMessage = '設定保存失敗；已恢復先前狀態。';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final keys = _parsedKeys;
    final settings = _settingsFromForm(_settings);
    setState(() => _busy = true);
    try {
      await widget.repository.save(settings);
      if (!mounted) return;
      setState(() {
        _settings = settings;
        _obscureKeys = true;
        _statusMessage = keys.isEmpty
            ? '已儲存功能開關；目前沒有 API Key。'
            : '已安全儲存 ${keys.length} 組 API Key。';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _statusMessage = '安全儲存失敗；未寫入記帳資料庫。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clear() async {
    setState(() => _busy = true);
    try {
      await widget.repository.clear();
      if (!mounted) return;
      _keyController.clear();
      setState(() {
        _settings = const GeminiInvoiceSettings();
        _selectedModel = GeminiInvoiceSettings.defaultModel;
        _models = const <GeminiModelDescriptor>[];
        _keyResults = const <GeminiApiKeyTestResult>[];
        _obscureKeys = true;
        _statusMessage = 'Gemini API Key 與設定已清除。';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _statusMessage = '清除安全設定失敗。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
