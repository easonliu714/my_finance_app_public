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
}
