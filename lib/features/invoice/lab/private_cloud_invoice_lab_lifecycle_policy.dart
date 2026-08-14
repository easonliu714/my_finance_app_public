import 'package:flutter/widgets.dart';

enum PrivateCloudInvoiceLabLifecycleDisposition {
  preserve,
  cancel,
}

class PrivateCloudInvoiceLabLifecyclePolicy {
  const PrivateCloudInvoiceLabLifecyclePolicy._();

  static PrivateCloudInvoiceLabLifecycleDisposition dispositionFor(
    AppLifecycleState state,
  ) {
    return state == AppLifecycleState.detached
        ? PrivateCloudInvoiceLabLifecycleDisposition.cancel
        : PrivateCloudInvoiceLabLifecycleDisposition.preserve;
  }
}
