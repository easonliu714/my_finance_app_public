import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'invoice_award_check_page.dart';

/// Visible, user-initiated entry from the Reports/Ledger surface into the
/// Issue #13 Award Check workflow.
///
/// Navigation itself performs no network request and grants no award-refresh
/// or accounting-write authority. The destination owns the explicit refresh
/// action and all official-source/LKG gates.
class InvoiceAwardCheckEntryButton extends StatelessWidget {
  const InvoiceAwardCheckEntryButton({super.key});

  static const buttonKey = Key('invoice_award_check_report_entry');

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: buttonKey,
      tooltip: '統一發票對獎',
      onPressed: () => context.pushNamed(InvoiceAwardCheckPage.routeName),
      icon: const Icon(Icons.workspace_premium_outlined),
    );
  }
}
