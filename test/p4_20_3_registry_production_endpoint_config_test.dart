import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/merchant/business_registry_distribution_manifest.dart';
import 'package:my_finance_app/features/merchant/business_registry_update_service.dart';

void main() {
  test('P4.20.3+457 production build has a valid default Registry endpoint', () {
    final uri = BusinessRegistryUpdateConfiguration.manifestUri;

    expect(uri, isNotNull);
    expect(
      uri.toString(),
      BusinessRegistryUpdateConfiguration.productionManifestUrl,
    );
    expect(
      BusinessRegistryDistributionManifest.isAllowedDistributionUri(uri!),
      isTrue,
    );
    expect(
      BusinessRegistryDistributionManifest.isAllowedRepositoryPath(uri),
      isTrue,
    );
    expect(
      const BusinessRegistryUpdateService().isDistributionConfigured,
      isTrue,
    );
  });

  test('production endpoint hotfix cannot regress back to an empty default', () {
    final source = File(
      'lib/features/merchant/business_registry_update_service.dart',
    ).readAsStringSync();

    expect(
      source,
      contains(
        'defaultValue: productionManifestUrl',
      ),
    );
    expect(
      source,
      contains(
        'releases/download/p4.20.3-registry/manifest.json',
      ),
    );
    expect(
      source,
      isNot(contains("defaultValue: ''")),
    );
  });
}
