import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'features/invoice/invoice_award_app_lifecycle_coordinator.dart';
import 'routing/app_router.dart';

class MyFinanceApp extends StatelessWidget {
  const MyFinanceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return InvoiceAwardAppLifecycleCoordinator(
      child: MaterialApp.router(
        title: 'My Finance App',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        routerConfig: appRouter,
      ),
    );
  }
}
