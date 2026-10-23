import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/invoice_award_cloud_candidate_scope.dart';

void main() {
  group('native heartbeat UI evidence', () {
    test('fresh native open-begin remains the actual reported stage', () {
      expect(
        cloudAwardNativeHeartbeatDisplayStage(
          nativeStage: 'PLATFORM_RENDERER_OPEN_BEGIN',
          heartbeatAge: const Duration(seconds: 2),
        ),
        'PLATFORM_RENDERER_OPEN_BEGIN',
      );
    });

    test('fresh native open-wait is not relabeled', () {
      expect(
        cloudAwardNativeHeartbeatDisplayStage(
          nativeStage: 'PLATFORM_RENDERER_OPEN_WAIT',
          heartbeatAge: const Duration(seconds: 5),
        ),
        'PLATFORM_RENDERER_OPEN_WAIT',
      );
    });

    test('15 second boundary still preserves native evidence', () {
      expect(
        cloudAwardNativeHeartbeatDisplayStage(
          nativeStage: 'PLATFORM_SOURCE_SHA256',
          heartbeatAge: const Duration(seconds: 15),
        ),
        'PLATFORM_SOURCE_SHA256',
      );
    });

    test('stale open-begin never becomes synthetic open-wait', () {
      expect(
        cloudAwardNativeHeartbeatDisplayStage(
          nativeStage: 'PLATFORM_RENDERER_OPEN_BEGIN',
          heartbeatAge: const Duration(seconds: 16),
        ),
        'PLATFORM_WORKER_HEARTBEAT_STALE',
      );
    });

    test('stale progress in any native stage cannot claim new progress', () {
      for (final stage in <String>[
        'PLATFORM_RENDERER_CANDIDATE_SEARCH',
        'PLATFORM_SOURCE_SHA256',
        'PLATFORM_RENDERER_OPEN_WAIT',
      ]) {
        expect(
          cloudAwardNativeHeartbeatDisplayStage(
            nativeStage: stage,
            heartbeatAge: const Duration(minutes: 4),
          ),
          'PLATFORM_WORKER_HEARTBEAT_STALE',
        );
      }
    });

    test('future-dated native heartbeat is not treated as fresh', () {
      expect(
        cloudAwardNativeHeartbeatDisplayStage(
          nativeStage: 'PLATFORM_RENDERER_OPEN_BEGIN',
          heartbeatAge: const Duration(seconds: -1),
        ),
        'PLATFORM_WORKER_HEARTBEAT_STALE',
      );
    });
    test('fresh native heartbeat does not require a liveness probe', () {
      expect(
        cloudAwardNativeHeartbeatNeedsProbe(const Duration(seconds: 2)),
        isFalse,
      );
    });

    test('exact heartbeat age boundary does not probe', () {
      expect(
        cloudAwardNativeHeartbeatNeedsProbe(const Duration(seconds: 15)),
        isFalse,
      );
    });

    test('expired heartbeat requires a liveness probe', () {
      expect(
        cloudAwardNativeHeartbeatNeedsProbe(const Duration(seconds: 16)),
        isTrue,
      );
    });

    test('future native clock requires a liveness probe', () {
      expect(
        cloudAwardNativeHeartbeatNeedsProbe(const Duration(seconds: -1)),
        isTrue,
      );
    });
  });
}
