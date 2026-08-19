import 'dart:async';
import 'dart:math';

import '../../recognition_ai/gemini_flash_model_router.dart';
import '../../recognition_ai/gemini_key_group_router.dart';
import '../../recognition_ai/recognition_ai_contract.dart';
import 'gemini_invoice_review.dart';
import 'gemini_invoice_review_client.dart';
import 'gemini_invoice_review_coordinator.dart';
import 'gemini_invoice_settings.dart';
import 'gemini_invoice_settings_repository.dart';
import 'gemini_model_catalog_client.dart';

class ResilientGeminiInvoiceReviewExecution extends GeminiInvoiceReviewExecution {
  const ResilientGeminiInvoiceReviewExecution({
    required super.status,
    required super.message,
    required super.decision,
    required super.model,
    required this.sessionContext,
    super.candidate,
    super.attempts,
    super.invocationMode,
    super.automaticReviewSettingEnabled,
    super.requestCount,
    super.automaticUploadPerformed,
  });

  final RecognitionSessionContext sessionContext;

  @override
  Map<String, Object?> toSafeSummary() => <String, Object?>{
        ...super.toSafeSummary(),
        'resilience': sessionContext.toSafeJson(),
      };
}

class ResilientGeminiInvoiceReviewCoordinator
    extends GeminiInvoiceReviewCoordinator {
  ResilientGeminiInvoiceReviewCoordinator({
    required GeminiInvoiceSettingsStore settingsStore,
    required GeminiInvoiceReviewPort client,
    GeminiInvoiceImageLoader imageLoader = const FileGeminiInvoiceImageLoader(),
    GeminiInvoiceEscalationPolicy policy = const GeminiInvoiceEscalationPolicy(),
    GeminiModelCatalogClient? catalogClient,
    GeminiKeyGroupRouter Function(List<String>)? keyGroupRouterFactory,
    this.modelRouter = const GeminiFlashModelRouter(),
    this.maxPhysicalAttempts = 3,
    String Function()? logicalInvocationIdFactory,
  })  : catalogClient = catalogClient ?? GeminiModelCatalogClient(),
        keyGroupRouterFactory =
            keyGroupRouterFactory ?? GeminiKeyGroupRouter.fromApiKeys,
        logicalInvocationIdFactory =
            logicalInvocationIdFactory ?? _defaultLogicalInvocationId,
        assert(maxPhysicalAttempts > 0),
        super(
          settingsStore: settingsStore,
          client: client,
          imageLoader: imageLoader,
          policy: policy,
        );

  final GeminiModelCatalogClient catalogClient;
  final GeminiKeyGroupRouter Function(List<String>) keyGroupRouterFactory;
  final GeminiFlashModelRouter modelRouter;
  final int maxPhysicalAttempts;
  final String Function() logicalInvocationIdFactory;

  @override
  Future<GeminiInvoiceReviewExecution> reviewAutomatically({
    required localResult,
    required String localReference,
  }) {
    return review(
      localResult: localResult,
      localReference: localReference,
      invocationMode: GeminiInvoiceReviewInvocationMode.automatic,
    );
  }

  @override
  Future<GeminiInvoiceReviewExecution> review({
    required localResult,
    required String localReference,
    bool forceReview = false,
    GeminiInvoiceReviewInvocationMode invocationMode =
        GeminiInvoiceReviewInvocationMode.manual,
  }) async {
    final settings = await settingsStore.load();
    final automatic =
        invocationMode == GeminiInvoiceReviewInvocationMode.automatic;
    final decision = forceReview
        ? const GeminiInvoiceEscalationDecision(
            shouldReview: true,
            reason: '使用者要求強制 AI 覆核。',
          )
        : policy.evaluate(localResult);

    if (!settings.experimentalInvoiceVisionEnabled ||
        (automatic && !settings.autoReviewLowConfidenceEnabled) ||
        !decision.shouldReview ||
        !settings.hasApiKey) {
      return super.review(
        localResult: localResult,
        localReference: localReference,
        forceReview: forceReview,
        invocationMode: invocationMode,
      );
    }

    final logicalInvocationId = logicalInvocationIdFactory();
    final groups = keyGroupRouterFactory(settings.apiKeys).healthyGroups;
    if (groups.isEmpty) {
      return super.review(
        localResult: localResult,
        localReference: localReference,
        forceReview: forceReview,
        invocationMode: invocationMode,
      );
    }

    late GeminiInvoiceImagePayload image;
    try {
      image = await imageLoader.load(localReference);
    } catch (_) {
      return _execution(
        status: GeminiInvoiceReviewExecutionStatus.invalidImage,
        message: '無法安全讀取待覆核影像。',
        decision: decision,
        settings: settings,
        invocationMode: invocationMode,
        logicalInvocationId: logicalInvocationId,
        activeModel: settings.model,
        activeKeyGroupAlias: groups.first.alias,
        fallbackReason: RecognitionAiFallbackReason.none,
        modelCatalogChecked: false,
        attempts: const <GeminiInvoiceReviewAttemptSummary>[],
        events: const <RecognitionAiRoutingEvent>[],
        attemptedModels: const <String>{},
        attemptedGroups: const <String>{},
      );
    }

    final attempts = <GeminiInvoiceReviewAttemptSummary>[];
    final events = <RecognitionAiRoutingEvent>[];
    final attemptedModels = <String>{};
    final attemptedGroups = <String>{};
    var fallbackReason = RecognitionAiFallbackReason.none;
    var activeModel = settings.model;
    var activeKeyGroupAlias = groups.first.alias;
    var preferredForNextGroup = settings.model;
    var modelCatalogChecked = false;

    for (final group in groups) {
      if (attempts.length >= maxPhysicalAttempts) break;
      attemptedGroups.add(group.alias);
      activeKeyGroupAlias = group.alias;
      final key = group.apiKeys.first;

      var catalog = const <GeminiModelDescriptor>[];
      try {
        modelCatalogChecked = true;
        catalog = await catalogClient.listModels(key);
      } on GeminiModelCatalogException catch (error) {
        modelCatalogChecked = true;
        if (error.statusCode == 429) {
          fallbackReason = RecognitionAiFallbackReason.quotaExhausted;
          events.add(
            RecognitionAiRoutingEvent(
              keyGroupAlias: group.alias,
              model: preferredForNextGroup,
              reason: fallbackReason,
              physicalRequestSent: false,
              message: 'model_catalog_quota',
            ),
          );
          continue;
        }
        if (error.statusCode == 401 || error.statusCode == 403) {
          fallbackReason = RecognitionAiFallbackReason.authenticationFailed;
          events.add(
            RecognitionAiRoutingEvent(
              keyGroupAlias: group.alias,
              model: preferredForNextGroup,
              reason: fallbackReason,
              physicalRequestSent: false,
              message: 'model_catalog_auth',
            ),
          );
          continue;
        }
        // Catalog metadata failures must not invent a model. Keep only the
        // currently configured model and let generateContent classify it.
        catalog = const <GeminiModelDescriptor>[];
      } on TimeoutException {
        modelCatalogChecked = true;
        fallbackReason = RecognitionAiFallbackReason.timeout;
      } catch (_) {
        modelCatalogChecked = true;
        fallbackReason = RecognitionAiFallbackReason.network;
      }

      final preferredAvailable = catalog.isEmpty ||
          modelRouter.isPreferredAvailable(
            preferredModel: preferredForNextGroup,
            catalog: catalog,
          );
      final modelCandidates = modelRouter.candidates(
        preferredModel: preferredForNextGroup,
        catalog: catalog,
      );
      if (!preferredAvailable && modelCandidates.isNotEmpty) {
        fallbackReason = RecognitionAiFallbackReason.modelUnavailable;
        events.add(
          RecognitionAiRoutingEvent(
            keyGroupAlias: group.alias,
            model: modelCandidates.first,
            reason: fallbackReason,
            physicalRequestSent: false,
            message: 'preferred_model_not_in_catalog',
          ),
        );
      }
      if (modelCandidates.isEmpty) {
        fallbackReason = RecognitionAiFallbackReason.modelUnavailable;
        events.add(
          RecognitionAiRoutingEvent(
            keyGroupAlias: group.alias,
            model: preferredForNextGroup,
            reason: fallbackReason,
            physicalRequestSent: false,
            message: 'no_flash_generate_content_model',
          ),
        );
        continue;
      }

      var moveToNextGroup = false;
      for (final model in modelCandidates) {
        if (attempts.length >= maxPhysicalAttempts || moveToNextGroup) break;
        activeModel = model;
        attemptedModels.add(model);
        var transientRetryUsed = false;

        while (attempts.length < maxPhysicalAttempts) {
          try {
            final candidate = await client.review(
              apiKey: key,
              model: model,
              imageBytes: image.bytes,
              mimeType: image.mimeType,
              localSummary: _localSummary(localResult),
            );
            attempts.add(
              GeminiInvoiceReviewAttemptSummary(
                ordinal: attempts.length + 1,
                maskedKey: GeminiInvoiceSettings.maskApiKey(key),
                success: true,
                message: '覆核成功',
              ),
            );
            events.add(
              RecognitionAiRoutingEvent(
                keyGroupAlias: group.alias,
                model: model,
                reason: RecognitionAiFallbackReason.none,
                physicalRequestSent: true,
                message: 'success',
              ),
            );
            return _execution(
              status: GeminiInvoiceReviewExecutionStatus.success,
              message: automatic ? '已完成自動 AI 覆核。' : '已取得 AI 第二意見。',
              decision: decision,
              settings: settings,
              invocationMode: invocationMode,
              logicalInvocationId: logicalInvocationId,
              activeModel: model,
              activeKeyGroupAlias: group.alias,
              fallbackReason: fallbackReason,
              modelCatalogChecked: modelCatalogChecked,
              candidate: candidate,
              attempts: attempts,
              events: events,
              attemptedModels: attemptedModels,
              attemptedGroups: attemptedGroups,
            );
          } on GeminiInvoiceReviewException catch (error) {
            attempts.add(
              GeminiInvoiceReviewAttemptSummary(
                ordinal: attempts.length + 1,
                maskedKey: GeminiInvoiceSettings.maskApiKey(key),
                success: false,
                message: error.message,
              ),
            );

            if (error.kind == GeminiInvoiceReviewFailureKind.quota) {
              fallbackReason = RecognitionAiFallbackReason.quotaExhausted;
              preferredForNextGroup = model;
              moveToNextGroup = true;
            } else if (error.kind ==
                GeminiInvoiceReviewFailureKind.authentication) {
              fallbackReason = RecognitionAiFallbackReason.authenticationFailed;
              preferredForNextGroup = model;
              moveToNextGroup = true;
            } else if (error.statusCode == 404) {
              fallbackReason = RecognitionAiFallbackReason.modelUnavailable;
            } else if (error.kind ==
                    GeminiInvoiceReviewFailureKind.serviceUnavailable ||
                error.kind == GeminiInvoiceReviewFailureKind.timeout ||
                error.kind == GeminiInvoiceReviewFailureKind.network) {
              fallbackReason = switch (error.kind) {
                GeminiInvoiceReviewFailureKind.timeout =>
                  RecognitionAiFallbackReason.timeout,
                GeminiInvoiceReviewFailureKind.network =>
                  RecognitionAiFallbackReason.network,
                _ => RecognitionAiFallbackReason.serviceUnavailable,
              };
              if (!transientRetryUsed &&
                  attempts.length < maxPhysicalAttempts) {
                transientRetryUsed = true;
                events.add(
                  RecognitionAiRoutingEvent(
                    keyGroupAlias: group.alias,
                    model: model,
                    reason: fallbackReason,
                    physicalRequestSent: true,
                    message: 'bounded_retry',
                  ),
                );
                continue;
              }
              moveToNextGroup = true;
              preferredForNextGroup = model;
            } else {
              events.add(
                RecognitionAiRoutingEvent(
                  keyGroupAlias: group.alias,
                  model: model,
                  reason: fallbackReason,
                  physicalRequestSent: true,
                  message: error.kind.name,
                ),
              );
              return _execution(
                status: GeminiInvoiceReviewExecutionStatus.failed,
                message: 'AI 覆核未完成；本機結果仍可繼續使用。',
                decision: decision,
                settings: settings,
                invocationMode: invocationMode,
                logicalInvocationId: logicalInvocationId,
                activeModel: model,
                activeKeyGroupAlias: group.alias,
                fallbackReason: fallbackReason,
                modelCatalogChecked: modelCatalogChecked,
                attempts: attempts,
                events: events,
                attemptedModels: attemptedModels,
                attemptedGroups: attemptedGroups,
              );
            }

            events.add(
              RecognitionAiRoutingEvent(
                keyGroupAlias: group.alias,
                model: model,
                reason: fallbackReason,
                physicalRequestSent: true,
                message: error.kind.name,
              ),
            );
            break;
          } catch (_) {
            attempts.add(
              GeminiInvoiceReviewAttemptSummary(
                ordinal: attempts.length + 1,
                maskedKey: GeminiInvoiceSettings.maskApiKey(key),
                success: false,
                message: 'Gemini 覆核發生未分類錯誤。',
              ),
            );
            return _execution(
              status: GeminiInvoiceReviewExecutionStatus.failed,
              message: 'AI 覆核未完成；本機結果仍可繼續使用。',
              decision: decision,
              settings: settings,
              invocationMode: invocationMode,
              logicalInvocationId: logicalInvocationId,
              activeModel: model,
              activeKeyGroupAlias: group.alias,
              fallbackReason: fallbackReason,
              modelCatalogChecked: modelCatalogChecked,
              attempts: attempts,
              events: events,
              attemptedModels: attemptedModels,
              attemptedGroups: attemptedGroups,
            );
          }
        }
      }
    }

    return _execution(
      status: GeminiInvoiceReviewExecutionStatus.failed,
      message: 'AI 覆核未完成；本機結果仍可繼續使用。',
      decision: decision,
      settings: settings,
      invocationMode: invocationMode,
      logicalInvocationId: logicalInvocationId,
      activeModel: activeModel,
      activeKeyGroupAlias: activeKeyGroupAlias,
      fallbackReason: fallbackReason,
      modelCatalogChecked: modelCatalogChecked,
      attempts: attempts,
      events: events,
      attemptedModels: attemptedModels,
      attemptedGroups: attemptedGroups,
    );
  }

  ResilientGeminiInvoiceReviewExecution _execution({
    required GeminiInvoiceReviewExecutionStatus status,
    required String message,
    required GeminiInvoiceEscalationDecision decision,
    required GeminiInvoiceSettings settings,
    required GeminiInvoiceReviewInvocationMode invocationMode,
    required String logicalInvocationId,
    required String activeModel,
    required String activeKeyGroupAlias,
    required RecognitionAiFallbackReason fallbackReason,
    required bool modelCatalogChecked,
    required List<GeminiInvoiceReviewAttemptSummary> attempts,
    required List<RecognitionAiRoutingEvent> events,
    required Set<String> attemptedModels,
    required Set<String> attemptedGroups,
    GeminiInvoiceReviewCandidate? candidate,
  }) {
    final frozenAttempts =
        List<GeminiInvoiceReviewAttemptSummary>.unmodifiable(attempts);
    final context = RecognitionSessionContext(
      logicalInvocationId: logicalInvocationId,
      provider: 'Gemini',
      activeModel: activeModel,
      keyGroupAlias: activeKeyGroupAlias,
      logicalInvocationCount: 1,
      physicalAttemptCount: frozenAttempts.length,
      modelAttemptCount: attemptedModels.length,
      keyGroupAttemptCount: attemptedGroups.length,
      fallbackReason: fallbackReason,
      modelCatalogChecked: modelCatalogChecked,
      events: List<RecognitionAiRoutingEvent>.unmodifiable(events),
    );
    return ResilientGeminiInvoiceReviewExecution(
      status: status,
      message: message,
      decision: decision,
      model: activeModel,
      sessionContext: context,
      candidate: candidate,
      attempts: frozenAttempts,
      invocationMode: invocationMode,
      automaticReviewSettingEnabled: settings.autoReviewLowConfidenceEnabled,
      requestCount: frozenAttempts.length,
      automaticUploadPerformed:
          invocationMode == GeminiInvoiceReviewInvocationMode.automatic &&
              frozenAttempts.isNotEmpty,
    );
  }

  Map<String, Object?> _localSummary(dynamic result) {
    final candidate = result.ocrResult?.candidate;
    return <String, Object?>{
      'status': result.status.name,
      'requestedRoute': result.requestedRoute.name,
      'hasQrCandidate': result.qrResult?.hasReviewCandidate == true,
      'hasOcrCandidate': candidate != null,
      'localHasInvoiceNumber': candidate?.invoiceNumber.isNotEmpty == true,
      'localHasSellerTaxId': candidate?.sellerTaxId.isNotEmpty == true,
      'localHasInvoiceDate': candidate?.invoiceDate != null,
      'localHasSellerName': candidate?.sellerName.isNotEmpty == true,
      'localHasTotalAmount': candidate?.totalAmount != null,
      'localWarningFieldCount':
          candidate?.fieldWarnings.values
                  .where((warnings) => warnings.isNotEmpty)
                  .length ??
              0,
    };
  }

  static String _defaultLogicalInvocationId() {
    final micros = DateTime.now().toUtc().microsecondsSinceEpoch.toRadixString(36);
    final entropy = Random.secure().nextInt(0x7fffffff).toRadixString(36);
    return 'gemini_$micros_$entropy';
  }
}
