import 'package:flutter/material.dart';

import 'invoice_award_check_card.dart';
import 'invoice_award_check_presentation.dart';

/// Read-only Issue #13 Award Check surface.
///
/// The page consumes already validated local projections only. It intentionally
/// has no network acquisition, redemption/remittance, or accounting-write
/// capability; those authorities remain outside this presentation boundary.
///
/// [onManualRefresh] is an explicit user-intent seam only. The page never
/// starts background acquisition by itself; the caller remains responsible for
/// applying consent, official-source, and Last-Known-Good repository policy.
class InvoiceAwardCheckPage extends StatelessWidget {
  const InvoiceAwardCheckPage({
    super.key,
    required this.presentations,
    this.isRefreshing = false,
    this.onManualRefresh,
  });

  static const String routePath = '/invoice-award-check';
  static const String routeName = 'invoice-award-check';

  final List<InvoiceAwardCheckPresentation> presentations;
  final bool isRefreshing;
  final VoidCallback? onManualRefresh;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('統一發票中獎檢查'),
        actions: [
          if (onManualRefresh != null)
            IconButton(
              tooltip: '手動更新官方中獎資料',
              onPressed: isRefreshing ? null : onManualRefresh,
              icon: const Icon(Icons.refresh),
            ),
        ],
      ),
      body: SafeArea(
        child: isRefreshing
            ? const Center(child: CircularProgressIndicator())
            : presentations.isEmpty
                ? const _EmptyAwardCheckState()
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: presentations.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) => InvoiceAwardCheckCard(
                      presentation: presentations[index],
                    ),
                  ),
      ),
    );
  }
}

class _EmptyAwardCheckState extends StatelessWidget {
  const _EmptyAwardCheckState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          '目前沒有可顯示的中獎結果。中獎比對只使用已驗證的官方資料並在裝置本機完成。',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
