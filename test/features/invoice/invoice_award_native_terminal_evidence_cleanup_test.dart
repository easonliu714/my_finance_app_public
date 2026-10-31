import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/invoice_award_cloud_candidate_scope.dart';

void main() {
  group('native terminal evidence cleanup fail-closed', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('native_terminal_gate_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    Future<File> evidence() async {
      final file = File('${tempDir.path}/terminal.json');
      await file.writeAsString('{"request_id":"fixture","status":"failed"}');
      return file;
    }

    Future<void> cleanup(
      File file, {
      String? status = 'complete',
      bool verified = true,
      int candidates = 2,
      int matched = 2,
    }) async {
      await cloudAwardCleanupNativeTerminalEvidence(
        resultFile: file,
        terminalStatus: status,
        terminalValidated: verified,
        candidateCount: candidates,
        matchedCount: matched,
      );
    }

    test('deletes only verified all-positive COMPLETE evidence', () async {
      final file = await evidence();
      await cleanup(file);
      expect(await file.exists(), isFalse);
    });

    test('preserves FAILED terminal evidence', () async {
      final file = await evidence();
      await cleanup(file, status: 'failed');
      expect(await file.exists(), isTrue);
    });

    test('preserves malformed COMPLETE evidence', () async {
      final file = await evidence();
      await cleanup(file, verified: false);
      expect(await file.exists(), isTrue);
    });

    test('preserves partial/unknown negative-search evidence', () async {
      final file = await evidence();
      await cleanup(file, matched: 1);
      expect(await file.exists(), isTrue);
    });

    test('preserves empty-candidate and missing-status evidence', () async {
      final file = await evidence();
      await cleanup(file, candidates: 0, matched: 0);
      expect(await file.exists(), isTrue);
      await cleanup(file, status: null);
      expect(await file.exists(), isTrue);
    });

    test('already absent verified result is safe to clean', () async {
      final file = File('${tempDir.path}/absent.json');
      await cleanup(file);
      expect(await file.exists(), isFalse);
    });
  });
}
