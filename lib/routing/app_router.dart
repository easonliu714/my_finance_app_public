import 'package:go_router/go_router.dart';

import '../features/account/account_detail_page.dart';
import '../features/account/account_page.dart';
import '../features/account/account_record.dart';
import '../features/account/wallet_top_up_hub_page.dart';
import '../features/account/wallet_top_up_settings_page.dart';
import '../features/backup/flutter_local_backup_notification_port.dart';
import '../features/dashboard/dashboard_invoice_entry_shell.dart';
import '../features/dashboard/dashboard_page.dart';
import '../features/dashboard/ledger_detail_page.dart';
import '../features/invoice/cloud_invoice_inbox_page.dart';
import '../features/invoice/cloud_invoice_review_page.dart';
import '../features/invoice/draft_storage_hidden_route_page.dart';
import '../features/invoice/gemini/gemini_invoice_validation_page.dart';
import '../features/invoice/invoice_capture_entry_page.dart';
import '../features/invoice/invoice_capture_page.dart';
import '../features/invoice/invoice_field_first_review_flow.dart';
import '../features/invoice/invoice_frozen_review_page.dart';
import '../features/invoice/invoice_image_import_page.dart';
import '../features/invoice/invoice_live_capture_adaptive_page.dart';
import '../features/invoice/invoice_live_capture_page.dart';
import '../features/invoice/lab/private_cloud_invoice_lab_config.dart';
import '../features/invoice/lab/private_cloud_invoice_lab_page.dart';
import '../features/invoice/lab/private_cloud_invoice_lab_webview_page.dart';
import '../features/invoice/manual_invoice_entry_page.dart';
import '../features/plan/credit_card_installment_preview_page.dart';
import '../features/plan/repayment_plan_page.dart';
import '../features/product/product_capture_page.dart';
import '../features/profile/my_page.dart';
import '../features/transaction/transaction_entry_page.dart';
import '../features/transaction/transaction_record.dart';
import 'root_route_back_guard.dart';

final appRouter = GoRouter(
  initialLocation: '/',
  routes: buildAppRoutes(),
);

List<RouteBase> buildAppRoutes({
  bool privateCloudInvoiceLabEnabled = PrivateCloudInvoiceLabConfig.enabled,
}) {
  return <RouteBase>[
    GoRoute(
      path: '/',
      name: DashboardPage.routeName,
      builder: (context, state) => const DashboardInvoiceEntryShell(),
    ),
    GoRoute(
      path: AccountPage.routePath,
      name: AccountPage.routeName,
      builder: (context, state) =>
          const RootRouteBackGuard(child: AccountPage()),
    ),
    GoRoute(
      path: AccountDetailPage.routePath,
      name: AccountDetailPage.routeName,
      builder: (context, state) {
        final account =
            state.extra is AccountRecord ? state.extra! as AccountRecord : null;
        if (account == null) {
          return const RootRouteBackGuard(child: AccountPage());
        }
        return AccountDetailPage(account: account);
      },
    ),
    GoRoute(
      path: WalletTopUpHubPage.routePath,
      name: WalletTopUpHubPage.routeName,
      builder: (context, state) => const WalletTopUpHubPage(),
    ),
    GoRoute(
      path: WalletTopUpSettingsPage.routePath,
      name: WalletTopUpSettingsPage.routeName,
      builder: (context, state) {
        final account =
            state.extra is AccountRecord ? state.extra! as AccountRecord : null;
        if (account == null ||
            (account.type != AccountType.eWallet &&
                account.type != AccountType.storedValue)) {
          return const RootRouteBackGuard(child: AccountPage());
        }
        return WalletTopUpSettingsPage(account: account);
      },
    ),
    GoRoute(
      path: RepaymentPlanPage.routePath,
      name: RepaymentPlanPage.routeName,
      builder: (context, state) => const RepaymentPlanPage(),
    ),
    GoRoute(
      path: CreditCardInstallmentPreviewPage.routePath,
      name: CreditCardInstallmentPreviewPage.routeName,
      builder: (context, state) => const CreditCardInstallmentPreviewPage(),
    ),
    GoRoute(
      path: LedgerDetailPage.routePath,
      name: LedgerDetailPage.routeName,
      builder: (context, state) => const LedgerDetailPage(),
    ),
    GoRoute(
      path: ManualInvoiceEntryPage.routePath,
      name: ManualInvoiceEntryPage.routeName,
      builder: (context, state) => const ManualInvoiceEntryPage(),
    ),
    GoRoute(
      path: InvoiceCapturePage.routePath,
      name: InvoiceCapturePage.routeName,
      builder: (context, state) => const InvoiceCaptureEntryPage(),
    ),
    // Legacy still route remains non-discoverable for backward compatibility;
    // the production entry hub no longer exposes camera capture here.
    GoRoute(
      path: '/invoice-capture/still',
      name: 'invoice-capture-still',
      builder: (context, state) => const InvoiceCapturePage(),
    ),
    GoRoute(
      path: InvoiceImageImportPage.routePath,
      name: InvoiceImageImportPage.routeName,
      builder: (context, state) => const InvoiceImageImportPage(),
    ),
    GoRoute(
      path: InvoiceLiveCapturePage.routePath,
      name: InvoiceLiveCapturePage.routeName,
      builder: (context, state) => const AdaptiveInvoiceLiveCapturePage(),
    ),
    GoRoute(
      path: InvoiceFrozenReviewPage.routePath,
      name: InvoiceFrozenReviewPage.routeName,
      builder: (context, state) {
        final live = state.extra is InvoiceLiveCaptureResult
            ? state.extra! as InvoiceLiveCaptureResult
            : null;
        if (live == null) return const InvoiceCaptureEntryPage();
        return InvoiceFrozenReviewPage(
          liveResult: live,
          reviewFlowCoordinator:
              FieldFirstInvoiceCaptureReviewFlowCoordinator.production(
            liveResult: live,
          ),
        );
      },
    ),
    // Retained as a diagnostic deep-link only; it is no longer a capture mode.
    GoRoute(
      path: GeminiInvoiceValidationPage.routePath,
      name: GeminiInvoiceValidationPage.routeName,
      builder: (context, state) => const GeminiInvoiceValidationPage(),
    ),
    GoRoute(
      path: ProductCapturePage.routePath,
      name: ProductCapturePage.routeName,
      builder: (context, state) => const ProductCapturePage(),
    ),
    GoRoute(
      path: CloudInvoiceReviewPage.routePath,
      name: CloudInvoiceReviewPage.routeName,
      builder: (context, state) => CloudInvoiceInboxPage(
        onManualEntry: () =>
            context.pushNamed(ManualInvoiceEntryPage.routeName),
      ),
    ),
    GoRoute(
      path: DraftStorageHiddenRoutePage.routePath,
      name: DraftStorageHiddenRoutePage.routeName,
      builder: (context, state) => const DraftStorageHiddenRoutePage(),
    ),
    GoRoute(
      path: MyPage.routePath,
      name: MyPage.routeName,
      builder: (context, state) {
        final notificationPort = FlutterLocalBackupReminderNotificationPort();
        final page = MyPage(
          notificationPort: notificationPort,
          notificationPermissionPort: notificationPort,
        );
        return page;
      },
    ),
    GoRoute(
      path: TransactionEntryPage.routePath,
      name: TransactionEntryPage.routeName,
      builder: (context, state) {
        final extra = state.extra;
        final record = extra is TransactionRecord ? extra : null;
        final seed = extra is TransactionEntrySeed ? extra : null;
        return TransactionEntryPage(initialRecord: record, seed: seed);
      },
    ),
    GoRoute(
      path: PrivateCloudInvoiceLabWebViewPage.routePath,
      name: PrivateCloudInvoiceLabWebViewPage.routeName,
      builder: (context, state) =>
          const PrivateCloudInvoiceLabWebViewPage(),
    ),
    if (privateCloudInvoiceLabEnabled)
      GoRoute(
        path: PrivateCloudInvoiceLabPage.routePath,
        name: PrivateCloudInvoiceLabPage.routeName,
        builder: (context, state) => PrivateCloudInvoiceLabPage(),
      ),
  ];
}
