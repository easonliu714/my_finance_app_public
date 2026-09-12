import 'package:flutter/services.dart';

import 'business_registry_pack.dart';
import 'business_registry_repository.dart';

class BusinessRegistryValidationBootstrap {
  const BusinessRegistryValidationBootstrap({
    this.repository = const BusinessRegistryRepository(),
  });

  static const bool enabled = bool.fromEnvironment(
    'ENABLE_P4_20_REGISTRY_VALIDATION_PACK',
    defaultValue: false,
  );
  static const String assetPath =
      'assets/seed/business_registry_validation_pack.json';

  final BusinessRegistryRepository repository;

  /// Installs the tiny official-source validation subset only when the signed
  /// canary explicitly opts in and no registry is already installed. A real
  /// installed registry always wins; the validation subset never downgrades or
  /// replaces user-installed nationwide data.
  Future<bool> ensureInstalled() async {
    if (!enabled) return false;
    final existing = await repository.installedSnapshot();
    if (existing != null) return false;
    final text = await rootBundle.loadString(assetPath);
    final pack = BusinessRegistryPack.fromJsonText(text);
    if (!pack.isValidationSubset) {
      throw StateError('P4_20_VALIDATION_PACK_SCOPE_INVALID');
    }
    final result = await repository.install(pack);
    if (!result.isSuccess) {
      throw StateError(
        'P4_20_VALIDATION_PACK_INSTALL_REJECTED:${result.validationErrors.join(',')}',
      );
    }
    return true;
  }
}
