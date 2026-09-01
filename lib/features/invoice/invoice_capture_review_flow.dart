import 'image_capture_staging.dart';
import 'invoice_automatic_recognition_coordinator.dart';
import 'invoice_merchant_identity_review_service.dart';
import 'invoice_registry_corroboration_policy.dart';
import 'invoice_review_form_view_model.dart';
import 'invoice_review_handoff_contract.dart';
import 'invoice_review_qr_line_item_enricher.dart';

class InvoiceCaptureReviewFlowResult {
  const InvoiceCaptureReviewFlowResult({
    required this.recognitionResult,
    required this.handoffState,
    required this.formModel,
    this.registryContext,
    this.registryAuthorityDecision,
  });

  final InvoiceAutomaticRecognitionResult recognitionResult;
  final InvoiceReviewHandoffState handoffState;
  final InvoiceReviewFormViewModel formModel;
  final InvoiceMerchantIdentityReviewContext? registryContext;
  final InvoiceRegistryCorroborationAuthorityDecision? registryAuthorityDecision;

  bool get canOpenReview => formModel.canOpenReview;
  bool get canCreateFormalRecord => false;
  bool get usedNetwork => false;

  Map<String, Object?> toSafeSummary() {
    return <String, Object?>{
      'recognitionStatus': recognitionResult.status.name,
      'handoffAction': handoffState.action.name,
      'canOpenReview': canOpenReview,
      'canCreateFormalRecord': canCreateFormalRecord,
      'usedNetwork': usedNetwork,
      'form': formModel.toSafeSummary(),
      'registryLookupEligible': registryAuthorityDecision?.authoritative == true,
      'registryAuthoritySource': registryAuthorityDecision?.source.name ?? 'none',
      'registryStatus': registryContext?.registryStatus.name ?? 'not_requested',
      'registryCoverage': registryContext?.registryCoverage ?? '',
      'registryVersionPresent':
          registryContext?.registryVersion.trim().isNotEmpty == true,
      'registryRefreshAttempted':
          registryContext?.registryRefreshAttempted == true,
    };
  }
}

class InvoiceCaptureReviewFlowCoordinator {
  const InvoiceCaptureReviewFlowCoordinator({
    required this.recognitionCoordinator,
    this.handoffPresenter = const InvoiceReviewHandoffPresenter(),
    this.formPresenter = const InvoiceReviewFormPresenter(),
    this.qrLineItemEnricher = const InvoiceReviewQrLineItemEnricher(),
    this.registryAuthorityPolicy =
        const InvoiceRegistryCorroborationAuthorityPolicy(),
    this.merchantIdentityReviewService =
        const InvoiceMerchantIdentityReviewService(),
  });

  final InvoiceAutomaticRecognitionCoordinator recognitionCoordinator;
  final InvoiceReviewHandoffPresenter handoffPresenter;
  final InvoiceReviewFormPresenter formPresenter;
  final InvoiceReviewQrLineItemEnricher qrLineItemEnricher;
  final InvoiceRegistryCorroborationAuthorityPolicy registryAuthorityPolicy;
  final InvoiceMerchantIdentityReviewPort merchantIdentityReviewService;

  Future<InvoiceCaptureReviewFlowResult> recognize({
    required ImageCaptureStagingItem image,
    required InvoiceRecognitionRequestedRoute requestedRoute,
  }) async {
    final recognitionResult = await recognitionCoordinator.recognize(
      images: <ImageCaptureStagingItem>[image],
      requestedRoute: requestedRoute,
    );
    final handoffState = handoffPresenter.fromAutomaticResult(
      recognitionResult,
    );
    final baseFormModel = formPresenter.fromHandoff(handoffState);
    var formModel = qrLineItemEnricher.enrich(
      review: baseFormModel,
      recognition: recognitionResult,
    );

    final authorityDecision = registryAuthorityPolicy.evaluate(
      recognition: recognitionResult,
      review: formModel,
    );
    InvoiceMerchantIdentityReviewContext? registryContext;
    if (authorityDecision.authoritative) {
      try {
        final merchantText =
            formModel.fieldFor(InvoiceReviewFieldKey.sellerName)?.value ?? '';
        registryContext = await merchantIdentityReviewService.resolve(
          sellerIdentifier: authorityDecision.sellerIdentifier,
          sellerIdentifierAuthoritative: true,
          literalMerchantText: merchantText,
        );
        formModel = _withRegistryCorroboration(
          formModel,
          registryContext,
        );
      } catch (_) {
        // Registry is non-blocking corroboration. Recognition/review remains
        // usable if local registry access or a controlled refresh fails.
        formModel = _withRegistryFailureNotice(formModel);
      }
    }

    return InvoiceCaptureReviewFlowResult(
      recognitionResult: recognitionResult,
      handoffState: handoffState,
      formModel: formModel,
      registryContext: registryContext,
      registryAuthorityDecision: authorityDecision,
    );
  }

  InvoiceReviewFormViewModel _withRegistryCorroboration(
    InvoiceReviewFormViewModel model,
    InvoiceMerchantIdentityReviewContext context,
  ) {
    final legalName = context.decision.officialLegalNameSuggestion.trim();
    final formalMerchant = context.decision.formalMerchantName.trim();
    final notices = <String>[
      if (legalName.isNotEmpty)
        '官方登記名稱：$legalName（僅供佐證，不覆寫發票商家文字）',
      if (formalMerchant.isNotEmpty)
        '已知正式商家：$formalMerchant',
      if (context.isValidationSubset)
        '官方資料來源：實機驗證子集',
      if (context.registryRefreshAttempted && context.registryRefreshError.isNotEmpty)
        '官方資料更新失敗；已保留本機發票覆核流程',
    ];
    if (notices.isEmpty) return model;
    return _appendSellerNameNotices(model, notices);
  }

  InvoiceReviewFormViewModel _withRegistryFailureNotice(
    InvoiceReviewFormViewModel model,
  ) {
    return _appendSellerNameNotices(
      model,
      const <String>['官方商家資料暫時無法查詢；不影響本機發票覆核'],
    );
  }

  InvoiceReviewFormViewModel _appendSellerNameNotices(
    InvoiceReviewFormViewModel model,
    List<String> notices,
  ) {
    final fields = <InvoiceReviewFieldViewModel>[
      for (final field in model.fields)
        if (field.key == InvoiceReviewFieldKey.sellerName)
          InvoiceReviewFieldViewModel(
            key: field.key,
            label: field.label,
            value: field.value,
            editable: field.editable,
            requiredForReview: field.requiredForReview,
            confidenceLabel: field.confidenceLabel,
            warnings: List<String>.unmodifiable(<String>[
              ...field.warnings,
              ...notices.where((notice) => notice.trim().isNotEmpty),
            ]),
          )
        else
          field,
    ];
    return InvoiceReviewFormViewModel(
      title: model.title,
      routeReason: model.routeReason,
      disclaimer: model.disclaimer,
      fields: List<InvoiceReviewFieldViewModel>.unmodifiable(fields),
      lineItems: model.lineItems,
      warnings: model.warnings,
      availableOverrides: model.availableOverrides,
      canOpenReview: model.canOpenReview,
      requiresAcknowledgement: model.requiresAcknowledgement,
      disclaimerAcknowledged: model.disclaimerAcknowledged,
    );
  }
}
