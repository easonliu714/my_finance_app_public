class PrivateCloudInvoiceLabConfig {
  const PrivateCloudInvoiceLabConfig._();

  static const bool enabled = bool.fromEnvironment(
    'ENABLE_PRIVATE_CLOUD_INVOICE_LAB',
    defaultValue: false,
  );

  /// Must match the version declared in pubspec.yaml for signed LAB packages.
  static const String validationVersion = '4.17.4+426';

  static final Uri officialLandingUri = Uri.parse(
    'https://www.einvoice.nat.gov.tw/portal/btc/mobile',
  );

  static const String approvedQueryPathFragment = '/btc502w';
}
