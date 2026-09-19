import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Issue #29 review orchestration governance', () {
    test('existing coordinator remains the only recognition network seam', () {
      final coordinator = File(
        'lib/features/product/gemini_product_recognition_coordinator.dart',
      ).readAsStringSync();
      final capturePage = File(
        'lib/features/product/product_capture_page.dart',
      ).readAsStringSync();

      expect(coordinator, contains('class ProductRecognitionCoordinator'));
      expect(coordinator, contains('final GeminiProductRecognitionPort client;'));
      expect(
        coordinator,
        contains('await dispatchProductRecognitionCoordinatorAttempt('),
      );
      expect(coordinator, isNot(contains('await client.recognize(')));

      // ProductCapturePage must not create a second Gemini inference path.
      expect(capturePage, isNot(contains('.recognizeForReview(')));
      expect(capturePage, isNot(contains('GeminiProductRecognitionReviewPort')));
    });

    test('compact multi-item review stays presentation-only', () {
      final card = File(
        'lib/features/product/product_multi_item_review_proposal_card.dart',
      ).readAsStringSync();

      expect(card, contains('class ProductMultiItemReviewProposalCard'));
      expect(card, contains('required this.proposal'));
      expect(card, contains('不會自動建立正式記帳'));

      // The compact review card may only render already-produced evidence.
      // It must never grow a second inference, registry/network, repository,
      // merchant-binding, or formal transaction-write seam.
      expect(card, isNot(contains('recognize(')));
      expect(card, isNot(contains('recognizeForReview(')));
      expect(card, isNot(contains('GeminiProductRecognition')));
      expect(card, isNot(contains('Repository')));
      expect(card, isNot(contains('GCIS')));
      expect(card, isNot(contains('Merchant')));
      expect(card, isNot(contains('TransactionEntry')));
      expect(card, isNot(contains('onSave')));
      expect(card, isNot(contains('onBind')));
    });

    test('execution remains explicit-review only and cannot authorize writes', () {
      final coordinator = File(
        'lib/features/product/gemini_product_recognition_coordinator.dart',
      ).readAsStringSync();

      expect(coordinator, contains('class ProductRecognitionExecution'));
      expect(coordinator, contains('bool get canCreateFormalRecord => false;'));
      expect(coordinator, contains('bool get requiresUserReview => candidate != null;'));
    });
  });
}
