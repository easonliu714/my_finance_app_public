import 'package:flutter/foundation.dart' show kReleaseMode;

/// Owner option C: production cloud-500 is deferred. The shipped release
/// cannot re-enable it through a constructor, cached index or preference.
/// Explicit diagnostic replay is possible only in non-release builds.
class Cloud500ProductionPolicy {
  const Cloud500ProductionPolicy._();
  static const String deferredCode =
      'CLOUD500_PRODUCTION_DEFERRED_OWNER_OPTION_C';
  static bool isDeferred({bool allowDiagnostic = false}) =>
      kReleaseMode || !allowDiagnostic;

  /// Pure decision for positive/negative release policy regression tests.
  /// Production repositories always pass the compile-time release flag, never
  /// a caller-controlled preference or diagnostic override.
  static bool blocksCloud500PersistenceForBuild({
    required String tierCode,
    required bool isReleaseBuild,
  }) =>
      tierCode == 'cloud-500' && isReleaseBuild;

  static bool blocksCloud500Persistence(String tierCode) =>
      blocksCloud500PersistenceForBuild(
        tierCode: tierCode,
        isReleaseBuild: kReleaseMode,
      );

  /// Owner C: historical cloud-500 projections must not be rendered as
  /// validated prizes in a shipped release, including direct constructors.
  /// Check both amount and label so inconsistent legacy records fail closed.
  static bool blocksCloud500PrizeProjectionForBuild({
    required bool isReleaseBuild,
    required bool isCloudExclusive,
    required int grossAmount,
    required String tierLabel,
  }) {
    if (!isReleaseBuild || !isCloudExclusive) return false;
    return grossAmount == 500 ||
        RegExp(r'(^|[^0-9])500([^0-9]|$)').hasMatch(tierLabel.trim());
  }

  static bool blocksCloud500PrizeProjection({
    required bool isCloudExclusive,
    required int grossAmount,
    required String tierLabel,
  }) =>
      blocksCloud500PrizeProjectionForBuild(
        isReleaseBuild: kReleaseMode,
        isCloudExclusive: isCloudExclusive,
        grossAmount: grossAmount,
        tierLabel: tierLabel,
      );
}
