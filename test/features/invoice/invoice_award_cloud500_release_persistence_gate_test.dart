import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/invoice_award_cloud500_production_policy.dart';

void main() {
  test('release blocks cloud-500 durable authority but preserves other tiers', () {
    expect(
      Cloud500ProductionPolicy.blocksCloud500PersistenceForBuild(
        tierCode: 'cloud-500',
        isReleaseBuild: true,
      ),
      isTrue,
    );
    for (final tier in <String>['cloud-800', 'cloud-2000', 'cloud-1000000']) {
      expect(
        Cloud500ProductionPolicy.blocksCloud500PersistenceForBuild(
          tierCode: tier,
          isReleaseBuild: true,
        ),
        isFalse,
        reason: 'Owner C must not disable independent tier $tier',
      );
    }
  });

  test('diagnostic builds retain old fixture paths, not production authority', () {
    expect(
      Cloud500ProductionPolicy.blocksCloud500PersistenceForBuild(
        tierCode: 'cloud-500',
        isReleaseBuild: false,
      ),
      isFalse,
    );
    expect(Cloud500ProductionPolicy.isDeferred(), isTrue);
  });

  test('actual durable gate is pinned to the compile-time release mode', () {
    expect(
      Cloud500ProductionPolicy.blocksCloud500Persistence('cloud-500'),
      kReleaseMode,
    );
    expect(
      Cloud500ProductionPolicy.blocksCloud500Persistence('cloud-800'),
      isFalse,
    );
  });
}
