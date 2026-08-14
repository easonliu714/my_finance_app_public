import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'account_record.dart';
import 'account_repository.dart';
import 'wallet_top_up_settings_page.dart';

class WalletTopUpHubPage extends StatefulWidget {
  const WalletTopUpHubPage({super.key});

  static const routeName = 'wallet-top-up-hub';
  static const routePath = '/accounts/wallet-top-up';
  static const refreshKey = Key('wallet-top-up-hub-refresh');

  @override
  State<WalletTopUpHubPage> createState() => _WalletTopUpHubPageState();
}

class _WalletTopUpHubPageState extends State<WalletTopUpHubPage> {
  late Future<List<AccountRecord>> _accountsFuture;

  @override
  void initState() {
    super.initState();
    _accountsFuture = _loadAccounts();
  }

  Future<List<AccountRecord>> _loadAccounts() async {
    final accounts = await AccountRepository.instance.listAccounts(
      includeArchived: true,
    );
    final eligible = accounts
        .where(
          (item) =>
              !item.isArchived &&
              (item.type == AccountType.eWallet ||
                  item.type == AccountType.storedValue),
        )
        .toList(growable: false)
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return List<AccountRecord>.unmodifiable(eligible);
  }

  void _refresh() {
    setState(() => _accountsFuture = _loadAccounts());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('低餘額建議中心'),
        actions: [
          IconButton(
            key: WalletTopUpHubPage.refreshKey,
            tooltip: '重新整理',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<List<AccountRecord>>(
        future: _accountsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, size: 48),
                    const SizedBox(height: 12),
                    Text('讀取帳戶失敗：${snapshot.error}'),
                    const SizedBox(height: 12),
                    FilledButton(onPressed: _refresh, child: const Text('重試')),
                  ],
                ),
              ),
            );
          }
          final accounts = snapshot.data ?? const <AccountRecord>[];
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.shield_outlined),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '本中心只依 App 內帳務資料計算與保存建議。'
                          '不會連線至銀行或支付服務，也不會自動建立正式交易。',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '選擇目標帳戶',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              if (accounts.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Text(
                      '目前沒有可用的電子錢包或儲值帳戶。請先到「帳戶」建立帳戶。',
                    ),
                  ),
                )
              else
                for (final account in accounts)
                  Card(
                    child: ListTile(
                      key: Key('wallet-top-up-hub-account-${account.id}'),
                      leading: Icon(
                        account.type == AccountType.eWallet
                            ? Icons.account_balance_wallet_outlined
                            : Icons.credit_card_outlined,
                      ),
                      title: Text(account.displayName),
                      subtitle: Text(account.currency.displayLabel),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.pushNamed(
                        WalletTopUpSettingsPage.routeName,
                        extra: account,
                      ),
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }
}
