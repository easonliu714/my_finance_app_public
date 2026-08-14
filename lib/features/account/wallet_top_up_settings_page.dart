import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'account_record.dart';
import 'wallet_top_up_persistence.dart';
import 'wallet_top_up_recommendation.dart';
import 'wallet_top_up_ui_gateway.dart';

class WalletTopUpSettingsPage extends StatefulWidget {
  const WalletTopUpSettingsPage({
    super.key,
    required this.account,
    this.gateway,
    this.clock = DateTime.now,
  });

  static const routeName = 'wallet-top-up-settings';
  static const routePath = '/accounts/wallet-top-up-settings';

  static const enableSwitchKey = Key('wallet-top-up-enable-switch');
  static const fundingAccountKey = Key('wallet-top-up-funding-account');
  static const thresholdKey = Key('wallet-top-up-threshold');
  static const amountModeKey = Key('wallet-top-up-amount-mode');
  static const targetAmountKey = Key('wallet-top-up-target-amount');
  static const cooldownKey = Key('wallet-top-up-cooldown-hours');
  static const saveKey = Key('wallet-top-up-save');
  static const evaluateKey = Key('wallet-top-up-evaluate');

  final AccountRecord account;
  final WalletTopUpUiGateway? gateway;
  final DateTime Function() clock;

  @override
  State<WalletTopUpSettingsPage> createState() =>
      _WalletTopUpSettingsPageState();
}

class _WalletTopUpSettingsPageState extends State<WalletTopUpSettingsPage> {
  final _thresholdController = TextEditingController(text: '100');
  final _amountController = TextEditingController(text: '500');
  final _cooldownController = TextEditingController(text: '6');

  late final Future<WalletTopUpUiGateway> _gatewayFuture;
  WalletTopUpUiGateway? _gateway;
  WalletTopUpUiSnapshot? _snapshot;
  String? _fundingAccountId;
  WalletTopUpAmountMode _amountMode = WalletTopUpAmountMode.targetBalance;
  bool _enabled = true;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  String? _notice;

  @override
  void initState() {
    super.initState();
    _gatewayFuture = widget.gateway == null
        ? ProductionWalletTopUpUiGateway.create()
        : Future<WalletTopUpUiGateway>.value(widget.gateway!);
    _load();
  }

  @override
  void dispose() {
    _thresholdController.dispose();
    _amountController.dispose();
    _cooldownController.dispose();
    super.dispose();
  }

  Future<void> _load({bool preserveNotice = false}) async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
        if (!preserveNotice) _notice = null;
      });
    }
    try {
      final gateway = _gateway ?? await _gatewayFuture;
      final snapshot = await gateway.load(widget.account);
      _gateway = gateway;
      _hydrate(snapshot);
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _friendlyError(error);
      });
    }
  }

  void _hydrate(WalletTopUpUiSnapshot snapshot) {
    final profile = snapshot.profile;
    final eligibleIds = snapshot.eligibleFundingAccounts
        .map((item) => item.id)
        .toSet();
    if (profile == null) {
      _fundingAccountId = snapshot.eligibleFundingAccounts.isEmpty
          ? null
          : snapshot.eligibleFundingAccounts.first.id;
      _enabled = true;
      _amountMode = WalletTopUpAmountMode.targetBalance;
      _thresholdController.text = '100';
      _amountController.text = '500';
      _cooldownController.text = '6';
      return;
    }
    _fundingAccountId = eligibleIds.contains(profile.fundingAccountId)
        ? profile.fundingAccountId
        : null;
    _enabled = profile.isEnabled;
    _amountMode = profile.amountMode;
    _thresholdController.text = _compact(profile.threshold);
    _amountController.text = _compact(
      profile.amountMode == WalletTopUpAmountMode.targetBalance
          ? profile.targetBalance
          : profile.fixedAmount,
    );
    _cooldownController.text = _compact(
      profile.cooldown.inMinutes / 60,
    );
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    return Scaffold(
      appBar: AppBar(title: const Text('低餘額儲值建議')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null && snapshot == null
              ? _ErrorState(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: () => _load(preserveNotice: true),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
                    children: [
                      _SafetyCard(account: widget.account),
                      const SizedBox(height: 12),
                      if (_error != null)
                        _MessageCard(
                          icon: Icons.error_outline,
                          message: _error!,
                          isError: true,
                        ),
                      if (_notice != null)
                        _MessageCard(
                          icon: Icons.info_outline,
                          message: _notice!,
                        ),
                      if (_error != null || _notice != null)
                        const SizedBox(height: 12),
                      _buildSettingsCard(snapshot!),
                      const SizedBox(height: 12),
                      _buildSuggestionCard(snapshot),
                      const SizedBox(height: 12),
                      _buildHistoryCard(snapshot),
                    ],
                  ),
                ),
    );
  }

  Widget _buildSettingsCard(WalletTopUpUiSnapshot snapshot) {
    final hasFundingAccounts = snapshot.eligibleFundingAccounts.isNotEmpty;
    final canSave = !_busy && hasFundingAccounts && _fundingAccountId != null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '建議設定',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              '${snapshot.targetAccount.displayName}・'
              '${snapshot.targetAccount.currency.displayLabel}',
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              key: WalletTopUpSettingsPage.enableSwitchKey,
              contentPadding: EdgeInsets.zero,
              title: const Text('啟用低餘額建議'),
              subtitle: const Text('停用後保留設定與歷史，但不產生新建議。'),
              value: _enabled,
              onChanged: _busy ? null : (value) => setState(() => _enabled = value),
            ),
            if (!hasFundingAccounts)
              const _InlineWarning(
                message: '目前沒有同幣別、未封存且可作為資金來源的帳戶。',
              )
            else
              DropdownButtonFormField<String>(
                key: WalletTopUpSettingsPage.fundingAccountKey,
                initialValue: _fundingAccountId,
                decoration: const InputDecoration(labelText: '資金來源帳戶'),
                items: snapshot.eligibleFundingAccounts
                    .map(
                      (item) => DropdownMenuItem<String>(
                        value: item.id,
                        child: Text(item.displayName),
                      ),
                    )
                    .toList(growable: false),
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _fundingAccountId = value),
              ),
            const SizedBox(height: 12),
            TextField(
              key: WalletTopUpSettingsPage.thresholdKey,
              controller: _thresholdController,
              enabled: !_busy,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: '低餘額門檻',
                suffixText: snapshot.targetAccount.currency.code,
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<WalletTopUpAmountMode>(
              key: WalletTopUpSettingsPage.amountModeKey,
              initialValue: _amountMode,
              decoration: const InputDecoration(labelText: '建議金額方式'),
              items: const [
                DropdownMenuItem(
                  value: WalletTopUpAmountMode.targetBalance,
                  child: Text('補到目標餘額'),
                ),
                DropdownMenuItem(
                  value: WalletTopUpAmountMode.fixedAmount,
                  child: Text('固定建議金額'),
                ),
              ],
              onChanged: _busy
                  ? null
                  : (value) => setState(
                        () => _amountMode =
                            value ?? WalletTopUpAmountMode.targetBalance,
                      ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: WalletTopUpSettingsPage.targetAmountKey,
              controller: _amountController,
              enabled: !_busy,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: _amountMode == WalletTopUpAmountMode.targetBalance
                    ? '目標餘額'
                    : '固定建議金額',
                suffixText: snapshot.targetAccount.currency.code,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: WalletTopUpSettingsPage.cooldownKey,
              controller: _cooldownController,
              enabled: !_busy,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: '相同建議冷卻時間',
                suffixText: '小時',
                helperText: '冷卻期間不會重複保存相同的建議。',
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: WalletTopUpSettingsPage.saveKey,
                onPressed: canSave ? _saveProfile : null,
                icon: _busy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: const Text('保存建議設定'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuggestionCard(WalletTopUpUiSnapshot snapshot) {
    final profile = snapshot.profile;
    final latest = snapshot.latestSuggestion;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '建議檢視',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                FilledButton.tonalIcon(
                  key: WalletTopUpSettingsPage.evaluateKey,
                  onPressed: !_busy && profile?.isEnabled == true
                      ? _evaluateNow
                      : null,
                  icon: const Icon(Icons.calculate_outlined),
                  label: const Text('立即評估'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (profile == null)
              const Text('請先保存建議設定。')
            else if (!profile.isEnabled)
              const Text('此設定目前已停用，不會產生新建議。')
            else if (latest == null)
              const Text('尚無已保存的建議。立即評估不會建立正式交易。')
            else
              _SuggestionTile(
                suggestion: latest,
                accountName: _accountName,
                onDismiss: latest.status == WalletTopUpSuggestionStatus.pending &&
                        !_busy
                    ? () => _dismiss(latest.id)
                    : null,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryCard(WalletTopUpUiSnapshot snapshot) {
    return Card(
      child: ExpansionTile(
        title: const Text('建議與設定歷史'),
        subtitle: Text(
          '${snapshot.suggestions.length} 筆建議・${snapshot.audits.length} 筆稽核',
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          if (snapshot.suggestions.isEmpty && snapshot.audits.isEmpty)
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('尚無歷史紀錄。'),
            ),
          for (final suggestion in snapshot.suggestions.skip(1))
            _SuggestionTile(
              suggestion: suggestion,
              accountName: _accountName,
              compact: true,
              onDismiss: suggestion.status == WalletTopUpSuggestionStatus.pending &&
                      !_busy
                  ? () => _dismiss(suggestion.id)
                  : null,
            ),
          if (snapshot.audits.isNotEmpty) ...[
            const Divider(height: 24),
            for (final audit in snapshot.audits.reversed.take(12))
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.history, size: 20),
                title: Text(_auditLabel(audit.eventType)),
                subtitle: Text(_formatDateTime(audit.createdAt)),
              ),
          ],
        ],
      ),
    );
  }

  Future<void> _saveProfile() async {
    final snapshot = _snapshot!;
    final threshold = double.tryParse(_thresholdController.text.trim());
    final amount = double.tryParse(_amountController.text.trim());
    final cooldownHours = double.tryParse(_cooldownController.text.trim());
    final fundingAccountId = _fundingAccountId;
    String? validation;
    if (fundingAccountId == null) {
      validation = '請選擇資金來源帳戶。';
    } else if (threshold == null || !threshold.isFinite || threshold < 0) {
      validation = '低餘額門檻必須是 0 以上的有效數字。';
    } else if (amount == null || !amount.isFinite || amount <= 0) {
      validation = '目標餘額或固定建議金額必須大於 0。';
    } else if (_amountMode == WalletTopUpAmountMode.targetBalance &&
        amount <= threshold) {
      validation = '目標餘額必須高於低餘額門檻。';
    } else if (cooldownHours == null ||
        !cooldownHours.isFinite ||
        cooldownHours < 0) {
      validation = '冷卻時間不可為負數。';
    }
    if (validation != null) {
      setState(() {
        _error = validation;
        _notice = null;
      });
      return;
    }

    final now = widget.clock().toUtc();
    final existing = snapshot.profile;
    final profile = StoredWalletTopUpProfile(
      id: existing?.id ?? 'wallet-top-up-profile-${widget.account.id}',
      targetAccountId: widget.account.id,
      fundingAccountId: fundingAccountId!,
      currency: widget.account.currency,
      threshold: threshold!,
      amountMode: _amountMode,
      targetBalance:
          _amountMode == WalletTopUpAmountMode.targetBalance ? amount! : 0,
      fixedAmount:
          _amountMode == WalletTopUpAmountMode.fixedAmount ? amount! : 0,
      cooldown: Duration(
        minutes: (cooldownHours! * Duration.minutesPerHour).round(),
      ),
      isEnabled: _enabled,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );

    await _runAction(() async {
      await _gateway!.saveProfile(profile, now: now);
      _notice = _enabled ? '建議設定已保存。' : '建議設定已停用並保存。';
    });
  }

  Future<void> _evaluateNow() async {
    final profile = _snapshot?.profile;
    if (profile == null) return;
    await _runAction(() async {
      final result = await _gateway!.evaluateAndPersist(
        profile: profile,
        evaluatedAt: widget.clock().toUtc(),
      );
      final evaluation = result.evaluation;
      if (evaluation is WalletTopUpNoSuggestion) {
        _notice = evaluation.reason ==
                WalletTopUpNoSuggestionReason.balanceAtOrAboveThreshold
            ? '目前餘額 ${_compact(evaluation.currentAvailableBalance)} '
                '未低於門檻 ${_compact(evaluation.threshold)}，不需建立建議。'
            : '相同建議仍在冷卻期間，本次未重複保存。';
      } else if (result.persistence?.replayed == true) {
        _notice = '相同建議已存在，已顯示原始紀錄，未重複新增。';
      } else {
        _notice = '已保存一筆本機建議；尚未建立任何正式交易。';
      }
    });
  }

  Future<void> _dismiss(String suggestionId) async {
    await _runAction(() async {
      final result = await _gateway!.dismissSuggestion(
        suggestionId,
        now: widget.clock().toUtc(),
      );
      _notice = result.replayed ? '此建議先前已忽略。' : '已忽略此建議。';
    });
  }

  Future<void> _runAction(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await action();
      await _load(preserveNotice: true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _friendlyError(error);
      });
      return;
    }
    if (mounted) setState(() => _busy = false);
  }

  String _accountName(String id) {
    if (id == widget.account.id) return widget.account.displayName;
    for (final account in _snapshot?.eligibleFundingAccounts ?? const []) {
      if (account.id == id) return account.displayName;
    }
    return id;
  }

  String _friendlyError(Object error) {
    if (error is WalletTopUpRecommendationException) return error.message;
    if (error is WalletTopUpPersistenceException) return error.message;
    return error.toString();
  }
}

class _SafetyCard extends StatelessWidget {
  const _SafetyCard({required this.account});

  final AccountRecord account;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.shield_outlined),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '此功能只依 App 內帳務資料計算並保存本機建議。'
                '不會連線至銀行或支付服務，也不代表 ${account.displayName} '
                '已完成真實儲值；本頁所有操作都不會建立正式交易。',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SuggestionTile extends StatelessWidget {
  const _SuggestionTile({
    required this.suggestion,
    required this.accountName,
    this.compact = false,
    this.onDismiss,
  });

  final StoredWalletTopUpSuggestion suggestion;
  final String Function(String id) accountName;
  final bool compact;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final status = switch (suggestion.status) {
      WalletTopUpSuggestionStatus.pending => '待檢視',
      WalletTopUpSuggestionStatus.dismissed => '已忽略',
      WalletTopUpSuggestionStatus.superseded => '已被新建議取代',
    };
    return Padding(
      key: Key('wallet-top-up-suggestion-${suggestion.id}'),
      padding: EdgeInsets.symmetric(vertical: compact ? 4 : 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${_compact(suggestion.suggestedAmount)} '
                  '${suggestion.currency.code}・$status',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              if (onDismiss != null)
                TextButton(
                  key: Key('wallet-top-up-dismiss-${suggestion.id}'),
                  onPressed: onDismiss,
                  child: const Text('忽略'),
                ),
            ],
          ),
          Text(
            '${accountName(suggestion.fundingAccountId)} → '
            '${accountName(suggestion.targetAccountId)}',
          ),
          Text(
            '評估餘額 ${_compact(suggestion.currentAvailableBalance)}・'
            '門檻 ${_compact(suggestion.threshold)}・'
            '資金餘額 ${_compact(suggestion.fundingAvailableBalance)}',
          ),
          Text(
            suggestion.fundingSufficient
                ? '資金餘額足以涵蓋建議金額。'
                : '資金不足，尚差 ${_compact(suggestion.fundingShortfall)} '
                    '${suggestion.currency.code}。',
            style: TextStyle(
              color: suggestion.fundingSufficient
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.error,
            ),
          ),
          Text(
            _formatDateTime(suggestion.evaluatedAt),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({
    required this.icon,
    required this.message,
    this.isError = false,
  });

  final IconData icon;
  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: isError
          ? Theme.of(context).colorScheme.errorContainer
          : Theme.of(context).colorScheme.secondaryContainer,
      child: ListTile(
        leading: Icon(icon),
        title: Text(message),
      ),
    );
  }
}

class _InlineWarning extends StatelessWidget {
  const _InlineWarning({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber, color: Theme.of(context).colorScheme.error),
          const SizedBox(width: 8),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('重試')),
          ],
        ),
      ),
    );
  }
}

String _auditLabel(WalletTopUpAuditEventType type) => switch (type) {
      WalletTopUpAuditEventType.profileCreated => '建立建議設定',
      WalletTopUpAuditEventType.profileUpdated => '更新建議設定',
      WalletTopUpAuditEventType.profileEnabled => '啟用建議設定',
      WalletTopUpAuditEventType.profileDisabled => '停用建議設定',
      WalletTopUpAuditEventType.suggestionCreated => '建立本機建議',
      WalletTopUpAuditEventType.suggestionDismissed => '忽略建議',
      WalletTopUpAuditEventType.suggestionSuperseded => '建議被新狀態取代',
    };

String _formatDateTime(DateTime value) =>
    DateFormat('yyyy/MM/dd HH:mm').format(value.toLocal());

String _compact(double value) => value == value.roundToDouble()
    ? value.toStringAsFixed(0)
    : value.toStringAsFixed(2);
