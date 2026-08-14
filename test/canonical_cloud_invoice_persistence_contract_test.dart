import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('canonical adapters use supplied database executor only', () {
    final source = _adapterSource();

    expect(source, contains('DatabaseExecutor'));
    expect(source, isNot(contains('openDatabase(')));
    expect(source, isNot(contains('getDatabasesPath')));
    expect(source, isNot(contains('AccountRepository.instance')));
    expect(source, isNot(contains('TransactionRepository.instance')));
    expect(source, isNot(contains('CanonicalMerchantRepository.instance')));
    expect(source, isNot(contains('MerchantRepository.instance')));
  });

  test('service scopes execute, inspect, and rollback in transactions', () {
    final source = File(
      'lib/features/invoice/lab/canonical_cloud_invoice_persistence_service.dart',
    ).readAsStringSync();

    expect(RegExp(r'database\.transaction\(').allMatches(source), hasLength(3));
    expect(source, contains('ProductionDatabaseCoordinator.instance.database'));
    expect(source, contains('cleanupFailedOperation'));
    expect(source, contains('inspectRecovery'));
    expect(source, contains('RETRY_CLEANUP_COMPLETED'));
    expect(source, contains('removeOperation'));
    expect(source, contains('ROLLBACK_RECOVERY_REQUIRES_MANUAL_REVIEW'));
  });

  test('production router and providers remain independent from LAB recovery', () {
    final router = File('lib/routing/app_router.dart').readAsStringSync();
    final providerFiles = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('_providers.dart'));
    final providerSource = providerFiles
        .map((file) => file.readAsStringSync())
        .join('\n');

    expect(router, isNot(contains('CanonicalCloudInvoicePersistenceService')));
    expect(providerSource, isNot(contains('CanonicalCloudInvoicePersistenceService')));
  });

  test('codecs require versioned payloads and fail-closed decoding', () {
    final source = File(
      'lib/features/invoice/lab/canonical_cloud_invoice_persistence_codec.dart',
    ).readAsStringSync();

    expect(source, contains('canonicalCloudInvoicePayloadVersion'));
    expect(source, contains('TRANSACTION_CURRENCY_UNSUPPORTED'));
    expect(source, contains('TRANSACTION_TYPE_UNSUPPORTED'));
    expect(source, contains('LINE_ITEMS_PAYLOAD_VERSION_UNSUPPORTED'));
  });
}

String _adapterSource() {
  return <String>[
    'lib/features/invoice/lab/canonical_cloud_invoice_transaction_adapter.dart',
    'lib/features/invoice/lab/canonical_cloud_invoice_merchant_adapter.dart',
    'lib/features/invoice/lab/canonical_cloud_invoice_metadata_adapter.dart',
    'lib/features/invoice/lab/canonical_cloud_invoice_operation_adapter.dart',
  ].map((path) => File(path).readAsStringSync()).join('\n');
}
