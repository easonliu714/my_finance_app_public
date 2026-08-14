import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/invoice/invoice_ai_vision_policy.dart';

void main() {
  const service = InvoiceAiVisionPolicyService();

  test('local-only QR parser supports QR parsing without API key', () {
    final result = service.evaluate(
      useCase: InvoiceAiVisionUseCase.invoiceQrParsing,
      dataPath: InvoiceAiVisionDataPath.localOnlyQrParser,
      apiKeyCustody: InvoiceAiVisionApiKeyCustody.notRequired,
      externalImageAnalysisConsentAcknowledged: false,
    );

    expect(result.isAllowed, isTrue);
    expect(result.apiKeyCustody, InvoiceAiVisionApiKeyCustody.notRequired);
    expect(result.requiresReviewGate, isTrue);
    expect(result.allowsAutomaticTransactionCreation, isFalse);
  });

  test('local-only QR parser does not cover product recognition or printed invoice content', () {
    final product = service.evaluate(
      useCase: InvoiceAiVisionUseCase.productItemRecognition,
      dataPath: InvoiceAiVisionDataPath.localOnlyQrParser,
      apiKeyCustody: InvoiceAiVisionApiKeyCustody.notRequired,
      externalImageAnalysisConsentAcknowledged: false,
    );
    final printedContent = service.evaluate(
      useCase: InvoiceAiVisionUseCase.invoicePrintedContentRecognition,
      dataPath: InvoiceAiVisionDataPath.localOnlyQrParser,
      apiKeyCustody: InvoiceAiVisionApiKeyCustody.notRequired,
      externalImageAnalysisConsentAcknowledged: false,
    );

    expect(product.isBlocked, isTrue);
    expect(printedContent.isBlocked, isTrue);
    expect(product.reason, InvoiceAiVisionPolicyCopy.localQrParserOnlySupportsQr);
  });

  test('Gemini vision product recognition and reference price require external image consent', () {
    final product = service.evaluate(
      useCase: InvoiceAiVisionUseCase.productItemRecognition,
      dataPath: InvoiceAiVisionDataPath.externalGeminiVision,
      apiKeyCustody: InvoiceAiVisionApiKeyCustody.userProvidedRuntimeOnly,
      externalImageAnalysisConsentAcknowledged: false,
    );
    final price = service.evaluate(
      useCase: InvoiceAiVisionUseCase.productReferencePriceEstimation,
      dataPath: InvoiceAiVisionDataPath.externalGeminiVision,
      apiKeyCustody: InvoiceAiVisionApiKeyCustody.userProvidedRuntimeOnly,
      externalImageAnalysisConsentAcknowledged: false,
    );

    expect(product.requiresUserConsent, isTrue);
    expect(price.requiresUserConsent, isTrue);
    expect(product.allowsAutomaticTransactionCreation, isFalse);
  });

  test('Gemini vision supports product recognition and advisory reference price after consent', () {
    final product = service.evaluate(
      useCase: InvoiceAiVisionUseCase.productItemRecognition,
      dataPath: InvoiceAiVisionDataPath.externalGeminiVision,
      apiKeyCustody: InvoiceAiVisionApiKeyCustody.secureRuntimeConfig,
      externalImageAnalysisConsentAcknowledged: true,
    );
    final price = service.evaluate(
      useCase: InvoiceAiVisionUseCase.productReferencePriceEstimation,
      dataPath: InvoiceAiVisionDataPath.externalGeminiVision,
      apiKeyCustody: InvoiceAiVisionApiKeyCustody.secureRuntimeConfig,
      externalImageAnalysisConsentAcknowledged: true,
    );

    expect(product.isAllowed, isTrue);
    expect(product.reason, InvoiceAiVisionPolicyCopy.productRecognitionAllowed);
    expect(price.isAllowed, isTrue);
    expect(price.outputsAreAdvisory, isTrue);
    expect(price.reason, InvoiceAiVisionPolicyCopy.referencePriceAllowed);
  });

  test('Gemini vision supports invoice text number and printed content recognition after consent', () {
    final number = service.evaluate(
      useCase: InvoiceAiVisionUseCase.invoiceTextNumberRecognition,
      dataPath: InvoiceAiVisionDataPath.externalGeminiVision,
      apiKeyCustody: InvoiceAiVisionApiKeyCustody.secureRuntimeConfig,
      externalImageAnalysisConsentAcknowledged: true,
    );
    final content = service.evaluate(
      useCase: InvoiceAiVisionUseCase.invoicePrintedContentRecognition,
      dataPath: InvoiceAiVisionDataPath.externalGeminiVision,
      apiKeyCustody: InvoiceAiVisionApiKeyCustody.secureRuntimeConfig,
      externalImageAnalysisConsentAcknowledged: true,
    );

    expect(number.isAllowed, isTrue);
    expect(number.reason, InvoiceAiVisionPolicyCopy.invoiceNumberVisionAllowed);
    expect(content.isAllowed, isTrue);
    expect(content.reason, InvoiceAiVisionPolicyCopy.invoiceContentVisionAllowed);
    expect(content.requiresReviewGate, isTrue);
  });

  test('hardcoded or repository-committed API keys are blocked', () {
    final hardcoded = service.evaluate(
      useCase: InvoiceAiVisionUseCase.productItemRecognition,
      dataPath: InvoiceAiVisionDataPath.externalGeminiVision,
      apiKeyCustody: InvoiceAiVisionApiKeyCustody.hardcodedInSource,
      externalImageAnalysisConsentAcknowledged: true,
    );
    final committed = service.evaluate(
      useCase: InvoiceAiVisionUseCase.invoicePrintedContentRecognition,
      dataPath: InvoiceAiVisionDataPath.externalGeminiVision,
      apiKeyCustody: InvoiceAiVisionApiKeyCustody.committedToRepository,
      externalImageAnalysisConsentAcknowledged: true,
    );

    expect(hardcoded.isBlocked, isTrue);
    expect(committed.isBlocked, isTrue);
    expect(hardcoded.reason, InvoiceAiVisionPolicyCopy.apiKeyCustodyBlocked);
    expect(committed.reason, InvoiceAiVisionPolicyCopy.apiKeyCustodyBlocked);
  });

  test('default guardrails include external consent, API key custody, and review gate', () {
    expect(InvoiceAiVisionPolicyCopy.recommendedModelAlias, 'gemini-flash-latest');
    expect(InvoiceAiVisionPolicyCopy.defaultGuardrails, contains(InvoiceAiVisionPolicyCopy.externalImageConsentRequired));
    expect(InvoiceAiVisionPolicyCopy.defaultGuardrails, contains(InvoiceAiVisionPolicyCopy.apiKeyCustodyBlocked));
    expect(InvoiceAiVisionPolicyCopy.defaultGuardrails, contains(InvoiceAiVisionPolicyCopy.reviewGateRequired));
  });
}
