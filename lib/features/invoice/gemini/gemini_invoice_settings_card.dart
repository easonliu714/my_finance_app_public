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
  late List<TextEditingController> _groupControllers;
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
    _groupControllers = <TextEditingController>[TextEditingController()];
    _catalogClient = widget.catalogClient ?? GeminiModelCatalogClient();
    _load();
  }

  @override
  void dispose() {
    for (final controller in _groupControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final settings = await widget.repository.load();
      if (!mounted) return;
      _replaceGroupControllers(<String>[
        for (final group in settings.effectiveKeyGroups)
          group.apiKeys.join('，'),
      ]);
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

    final parsedGroups = _parsedGroups();
    final parsedKeys = _flattenGroups(parsedGroups);
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
                        '設定 Project / Key Group、模型與自動覆核。Key 僅保存於系統安全儲存空間。',
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            for (var index = 0; index < _groupControllers.length; index++) ...<Widget>[
              _buildGroupField(context, index),
              const SizedBox(height: 10),
            ],
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                key: GeminiInvoiceSettingsCard.addGroupKey,
                onPressed: _busy ? null : _addGroup,
                icon: const Icon(Icons.add_outlined),
                label: const Text('新增獨立 Project / Key Group'),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              parsedKeys.isEmpty
                  ? '尚未輸入 API Key'
                  : '已解析 ${parsedGroups.length} 個 Key Group / ${parsedKeys.length} 組 API Key',
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
                        '${_groupAliasForOrdinal(parsedGroups, result.ordinal)} · Key #${result.ordinal} ${result.maskedKey}：${result.message}',
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
              label: Text(_busy ? '正在測試並讀取模型…' : '測試 Key Groups 並讀取可用模型'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: ValueKey<String>(
                '${GeminiInvoiceSettingsCard.modelDropdownKey}-$selectedModel-${modelItems.length}',
              ),
              initialValue: selectedModel,
              decoration: const InputDecoration(
                labelText: '發票辨識模型',
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
              subtitle: const Text('AI 只提供第二意見，不會直接建立交易。'),
              value: _settings.experimentalInvoiceVisionEnabled,
              onChanged: _busy
                  ? null
                  : (value) => setState(
                        () => _settings = _settings.copyWith(
                          experimentalInvoiceVisionEnabled: value,
                          autoReviewLowConfidenceEnabled: value
                              ? _settings.autoReviewLowConfidenceEnabled
                              : false,
                        ),
                      ),
            ),
            SwitchListTile.adaptive(
              key: GeminiInvoiceSettingsCard.autoReviewToggleKey,
              contentPadding: EdgeInsets.zero,
              title: const Text('OCR 信心不足時自動 AI 辨識'),
              subtitle: const Text(
                '開啟後，每次只建立 1 個 AI logical invocation；只有配額、模型不可用或暫時性服務錯誤才允許有限次 fallback / retry。',
              ),
              value: _settings.autoReviewLowConfidenceEnabled,
              onChanged: _busy || !_settings.experimentalInvoiceVisionEnabled
                  ? null
                  : (value) => setState(
                        () => _settings = _settings.copyWith(
                          autoReviewLowConfidenceEnabled: value,
                        ),
                      ),
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('保留發票辨識除錯工具'),
              subtitle: const Text('顯示比較、診斷與證據包匯出。'),
              value: _settings.debugToolsEnabled,
              onChanged: _busy
                  ? null
                  : (value) => setState(
                        () => _settings = _settings.copyWith(
                          debugToolsEnabled: value,
                        ),
                      ),
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

  Widget _buildGroupField(BuildContext context, int index) {
    final alias = _groupAlias(index);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                '$alias · 獨立 Google Project / quota boundary',
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
            if (_groupControllers.length > 1)
              IconButton(
                key: GeminiInvoiceSettingsCard.removeGroupKey(index),
                tooltip: '移除 $alias',
                onPressed: _busy ? null : () => _removeGroup(index),
                icon: const Icon(Icons.remove_circle_outline),
              ),
          ],
        ),
        TextField(
          key: index == 0
              ? GeminiInvoiceSettingsCard.apiKeyFieldKey
              : GeminiInvoiceSettingsCard.groupFieldKey(index),
          controller: _groupControllers[index],
          obscureText: _obscureKeys,
          enableSuggestions: false,
          autocorrect: false,
          keyboardType: TextInputType.visiblePassword,
          textInputAction: index == _groupControllers.length - 1
              ? TextInputAction.done
              : TextInputAction.next,
          decoration: InputDecoration(
            labelText: '$alias API Key',
            hintText: 'AIza…',
            helperText: '同一 Project 的多把 Key 可用逗號、頓號或分號分隔。',
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              key: index == 0
                  ? GeminiInvoiceSettingsCard.visibilityToggleKey
                  : null,
              tooltip: _obscureKeys ? '顯示全部 API Key' : '隱藏全部 API Key',
              onPressed: () => setState(() => _obscureKeys = !_obscureKeys),
              icon: Icon(
                _obscureKeys
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
              ),
            ),
          ),
          onChanged: (_) => _onKeyInputChanged(),
        ),
      ],
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
    final groups = _parsedGroups();
    final keys = _flattenGroups(groups);
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
            ? 'Key Group 測試完成；已讀取 ${result.models.length} 個可用模型。'
            : '沒有 API Key 通過測試，設定尚未啟用。';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final groups = _parsedGroups();
    final keys = _flattenGroups(groups);
    final settings = _settings.copyWith(
      apiKeys: keys,
      keyGroups: groups,
      model: _selectedModel ?? GeminiInvoiceSettings.defaultModel,
    );
    setState(() => _busy = true);
    try {
      await widget.repository.save(settings);
      if (!mounted) return;
      setState(() {
        _settings = settings;
        _obscureKeys = true;
        _statusMessage = keys.isEmpty
            ? '已儲存功能開關；目前沒有 API Key。'
            : '已安全儲存 ${groups.length} 個 Key Group / ${keys.length} 組 API Key。';
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
      _replaceGroupControllers(const <String>[]);
      setState(() {
        _settings = const GeminiInvoiceSettings();
        _selectedModel = GeminiInvoiceSettings.defaultModel;
        _models = const <GeminiModelDescriptor>[];
        _keyResults = const <GeminiApiKeyTestResult>[];
        _obscureKeys = true;
        _statusMessage = 'Gemini API Key 與設定已清除。';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _onKeyInputChanged() {
    setState(() {
      _keyResults = const <GeminiApiKeyTestResult>[];
      _statusMessage = null;
    });
  }

  void _addGroup() {
    setState(() {
      _groupControllers.add(TextEditingController());
      _keyResults = const <GeminiApiKeyTestResult>[];
      _statusMessage = null;
    });
  }

  void _removeGroup(int index) {
    if (_groupControllers.length <= 1) return;
    final controller = _groupControllers.removeAt(index);
    controller.dispose();
    setState(() {
      _keyResults = const <GeminiApiKeyTestResult>[];
      _statusMessage = null;
    });
  }

  void _replaceGroupControllers(List<String> values) {
    for (final controller in _groupControllers) {
      controller.dispose();
    }
    final normalized = values.where((value) => value.trim().isNotEmpty).toList();
    _groupControllers = normalized.isEmpty
        ? <TextEditingController>[TextEditingController()]
        : <TextEditingController>[
            for (final value in normalized) TextEditingController(text: value),
          ];
  }

  List<GeminiInvoiceKeyGroup> _parsedGroups() {
    return GeminiInvoiceSettings.parseKeyGroups(
      _groupControllers.map((controller) => controller.text).join('\n'),
    );
  }

  List<String> _flattenGroups(List<GeminiInvoiceKeyGroup> groups) {
    return List<String>.unmodifiable(<String>[
      for (final group in groups) ...group.apiKeys,
    ]);
  }

  String _groupAliasForOrdinal(
    List<GeminiInvoiceKeyGroup> groups,
    int ordinal,
  ) {
    var cursor = 0;
    for (final group in groups) {
      cursor += group.apiKeys.length;
      if (ordinal <= cursor) return group.alias;
    }
    return 'KEY_GROUP';
  }

  String _groupAlias(int index) {
    final code = 65 + index;
    if (code <= 90) return 'GROUP_${String.fromCharCode(code)}';
    return 'GROUP_${index + 1}';
  }
}
