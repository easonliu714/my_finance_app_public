import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'private_cloud_invoice_lab_page.dart';

class PrivateCloudInvoiceLabEntryOverlay extends StatelessWidget {
  const PrivateCloudInvoiceLabEntryOverlay({
    super.key,
    required this.child,
    this.onOpen,
  });

  static const Key entryKey = Key('private_cloud_invoice_lab_entry');

  final Widget child;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        PositionedDirectional(
          end: 16,
          bottom: 88,
          child: SafeArea(
            child: FloatingActionButton.extended(
              key: entryKey,
              onPressed: onOpen ??
                  () => context.push(PrivateCloudInvoiceLabPage.routePath),
              icon: const Icon(Icons.science_outlined),
              label: const Text('雲端發票 LAB'),
            ),
          ),
        ),
      ],
    );
  }
}
