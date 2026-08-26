import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../account/wallet_top_up_hub_page.dart';
import '../invoice/cloud_invoice_review_page.dart';
import '../invoice/lab/private_cloud_invoice_lab_webview_page.dart';
import '../voice/voice_transaction_entry_page.dart';
import 'dashboard_page.dart';

class DashboardInvoiceEntryShell extends StatelessWidget {
  const DashboardInvoiceEntryShell({super.key});

  static const walletTopUpEntryKey =
      Key('dashboard_wallet_top_up_recommendation_entry');
  static const cloudInvoiceReviewEntryKey =
      Key('dashboard_cloud_invoice_review_entry');
  static const cloudInvoiceWebViewEntryKey =
      Key('dashboard_cloud_invoice_webview_entry');
  static const voiceTransactionEntryKey =
      Key('dashboard_voice_transaction_entry');

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const DashboardPage(),
        Positioned(
          right: 16,
          bottom: 96,
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingActionButton.small(
                  key: voiceTransactionEntryKey,
                  heroTag: 'dashboard-voice-transaction-entry',
                  tooltip: '語音／文字快速記帳',
                  onPressed: () =>
                      context.pushNamed(VoiceTransactionEntryPage.routeName),
                  child: const Icon(Icons.mic_none_outlined),
                ),
                const SizedBox(height: 12),
                FloatingActionButton.small(
                  key: walletTopUpEntryKey,
                  heroTag: 'dashboard-wallet-top-up-recommendation-entry',
                  tooltip: '低餘額建議中心',
                  onPressed: () =>
                      context.pushNamed(WalletTopUpHubPage.routeName),
                  child: const Icon(Icons.notifications_active_outlined),
                ),
                const SizedBox(height: 12),
                FloatingActionButton.small(
                  key: cloudInvoiceWebViewEntryKey,
                  heroTag: 'dashboard-cloud-invoice-webview-entry',
                  tooltip: '官方發票一次性匯入',
                  onPressed: () => context.pushNamed(
                    PrivateCloudInvoiceLabWebViewPage.routeName,
                  ),
                  child: const Icon(Icons.public_outlined),
                ),
                const SizedBox(height: 12),
                FloatingActionButton(
                  key: cloudInvoiceReviewEntryKey,
                  heroTag: 'dashboard-cloud-invoice-review-entry',
                  tooltip: '雲端發票工作箱',
                  onPressed: () =>
                      context.pushNamed(CloudInvoiceReviewPage.routeName),
                  child: const Icon(Icons.receipt_long),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
