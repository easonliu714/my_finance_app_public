import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/product/gemini_product_recognition_candidate_payload.dart';

void main() {
  group('GeminiProductRecognitionCandidatePayload', () {
    test('derives legacy and review consumers from the same candidate JSON', () {
      final source = <String, Object?>{
        'productName': '牛奶',
        'quantity': 1,
        'unitPrice': 65,
        'totalAmount': 65,
        'categorySuggestion': '飲食',
        'merchantName': null,
        'recognizedText': '牛奶 65',
        'confidence': <String, Object?>{},
        'warnings': <Object?>[],
        'lines': <Object?>[
          <String, Object?>{
            'description': '牛奶',
            'quantity': 1,
            'unitPrice': 65,
            'lineTotal': 65,
          },
        ],
      };

      final payload =
          GeminiProductRecognitionCandidatePayload.fromCandidateJson(source);

      expect(payload.legacyCandidate.productName, '牛奶');
      expect(payload.reviewResult.candidate.productName, '牛奶');
      expect(payload.reviewResult.multiItemProposal, isNotNull);
      expect(payload.reviewResult.requiresUserReview, isTrue);
      expect(payload.reviewResult.canCreateFormalRecord, isFalse);

      source['productName'] = '被外部修改';
      expect(payload.candidateJson['productName'], '牛奶');
    });

    test('missing lines preserves legacy candidate without review proposal', () {
      final payload = GeminiProductRecognitionCandidatePayload.fromCandidateJson(
        <String, Object?>{
          'productName': '咖啡',
          'quantity': 1,
          'unitPrice': 45,
          'totalAmount': 45,
          'categorySuggestion': '飲食',
          'merchantName': null,
          'recognizedText': '咖啡 45',
          'confidence': <String, Object?>{},
          'warnings': <Object?>[],
        },
      );

      expect(payload.legacyCandidate.productName, '咖啡');
      expect(payload.reviewResult.candidate.productName, '咖啡');
      expect(payload.reviewResult.multiItemProposal, isNull);
      expect(payload.reviewResult.requiresUserReview, isTrue);
      expect(payload.reviewResult.canCreateFormalRecord, isFalse);
    });
  });
}
