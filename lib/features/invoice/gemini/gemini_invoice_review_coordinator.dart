import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../../recognition_ai/gemini_flash_model_router.dart';
import '../../recognition_ai/gemini_key_group_router.dart';
import '../../recognition_ai/recognition_ai_contract.dart';
import '../invoice_automatic_recognition_coordinator.dart';
import '../invoice_local_completeness_policy.dart';
import '../traditional_invoice_ocr_review.dart';
import 'gemini_invoice_review.dart';
import 'gemini_invoice_review_client.dart';
import 'gemini_invoice_settings.dart';
import 'gemini_invoice_settings_repository.dart';
import 'gemini_model_catalog_client.dart';

class GeminiInvoiceEscalationDecision {
  const GeminiInvoiceEscalationDecision({
    required this.shouldReview,
    required this.reason,
  });

  final bool shouldReview;
  final String reason;
}

class GeminiInvoiceEscalationPolicy {
  const GeminiInvoiceEscalationPolicy();

  GeminiInvoiceEscalationDecision evaluate(
    InvoiceAutomaticRecognitionResult localResult,
  ) {
    switch (localResult.status) {
      case InvoiceAutomaticRecognitionStatus.invalidInput:
        return const GeminiInvoiceEscalationDecision(
          shouldReview: false,
          reason: '本機輸入無效，不將影像送至 AI。',
        );
      case InvoiceAutomaticRecognitionStatus.qrReviewCandidate:
        final completeness = const InvoiceLocalCompletenessPolicy().evaluate(
          localResult,
        );
        return GeminiInvoiceEscalationDecision(
          shouldReview: completeness.requiresGeminiReview,
          reason: completeness.reason,
        );
      case InvoiceAutomaticRecognitionStatus.manualQrDesignation:
        return const GeminiInvoiceEscalationDecision(
          shouldReview: true,
          reason: '本機 QR 證據無法唯一配對，需要獨立 AI 覆核。',
        );
      case InvoiceAutomaticRecognitionStatus.recognitionFailed:
        return const GeminiInvoiceEscalationDecision(
          shouldReview: true,
          reason: '本機辨識未建立候選，需要獨立 AI 覆核。',
        );
      case InvoiceAutomaticRecognitionStatus.ocrReviewCandidate:
        return _evaluateOcr(localResult.ocrResult?.candidate);
    }
  }

  GeminiInvoiceEscalationDecision _evaluateOcr(
    TraditionalInvoiceOcrReviewCandidate? candidate,
  ) {
    if (candidate == null) {
      return const GeminiInvoiceEscalationDecision(
        shouldReview: true,
        reason: '本機 OCR 狀態缺少候選內容，需要獨立 AI 覆核。',
      );
    }

    final missingFields = <String>[
      if (candidate.invoiceNumber.isEmpty) '發票號碼',
      if (candidate.sellerTaxId.isEmpty) '賣方統編',
      if (candidate.invoiceDate == null) '日期',
      if (candidate.totalAmount == null) '總金額',
      if (candidate.sellerName.trim().isEmpty) '商家名稱',
    ];
    if (missingFields.isNotEmpty) {
      return GeminiInvoiceEscalationDecision(
        shouldReview: true,
        reason: '本機 OCR 缺少${missingFields.join('、')}，需要獨立 AI 覆核。',
      );
    }

    final hasWarnings = candidate.fieldWarnings.values.any(
      (warnings) => warnings.isNotEmpty,
    );
    if (hasWarnings) {
      return const GeminiInvoiceEscalationDecision(
        shouldReview: true,
        reason: '本機 OCR 仍有欄位警告，需要獨立 AI 覆核。',
      );
    }

    const criticalFields = <TraditionalInvoiceOcrField>[
      TraditionalInvoiceOcrField.invoiceNumber,
      TraditionalInvoiceOcrField.sellerTaxId,
      TraditionalInvoiceOcrField.invoiceDate,
      TraditionalInvoiceOcrField.totalAmount,
    ];
    final hasWeakCriticalField = criticalFields.any(
      (field) =>
          candidate.confidence[field] != TraditionalInvoiceOcrConfidence.high,
    );
    if (hasWeakCriticalField) {
      return const GeminiInvoiceEscalationDecision(
        shouldReview: true,
        reason: '本機 OCR 關鍵欄位尚未達高可信度，需要獨立 AI 覆核。',
      );
    }

    return const GeminiInvoiceEscalationDecision(
      shouldReview: false,
      reason: '本機 OCR 關鍵欄位完整且無警告，不需自動呼叫 AI。',
    );
  }
}

class GeminiInvoiceImagePayload {
  const GeminiInvoiceImagePayload({
    required this.bytes,
    required this.mimeType,
  });

  final Uint8List bytes;
  final String mimeType;
}

abstract interface class GeminiInvoiceImageLoader {
  Future<GeminiInvoiceImagePayload> load(String localReference);
}

class FileGeminiInvoiceImageLoader implements GeminiInvoiceImageLoader {
  const FileGeminiInvoiceImageLoader({this.maximumBytes = 8 * 1024 * 1024});

  final int maximumBytes;

  @override
  Future<GeminiInvoiceImagePayload> load(String localReference) async {
    final reference = localReference.trim();
    if (reference.isEmpty) {
      throw const FileSystemException('影像參照為空白');
    }
    final file = File(reference);
    if (!await file.exists()) {
      throw const FileSystemException('影像檔案不存在');
    }
    final length = await file.length();
    if (length <= 0 || length > maximumBytes) {
      throw const FileSystemException('影像大小不符合安全邊界');
    }
    final extension = reference.split('.').last.toLowerCase();
    final mimeType = switch (extension) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => throw const FileSystemException('影像格式不支援'),
    };
    return GeminiInvoiceImagePayload(
      bytes: await file.readAsBytes(),
      mimeType: mimeType,
    );
  }
}

enum GeminiInvoiceReviewExecutionStatus {
  disabled,
  skippedLocalComplete,
  missingApiKey,
  invalidImage,
  success,
  failed,
}

enum GeminiInvoiceReviewInvocationMode { none, manual, automatic }

class GeminiInvoiceReviewAttemptSummary {
  const GeminiInvoiceReviewAttemptSummary({
    required this.ordinal,
    required this.maskedKey,
    required this.success,
    required this.message,
  });

  final int ordinal;
  final String maskedKey;
  final bool success;
  final String message;
}

class GeminiInvoiceReviewExecution {
  const GeminiInvoiceReviewExecution({
    required this.status,
    required this.message,
    required this.decision,
    required this.model,
    this.candidate,
    this.attempts = const <GeminiInvoiceReviewAttemptSummary>[],
    this.invocationMode = GeminiInvoiceReviewInvocationMode.none,
    this.automaticReviewSettingEnabled = false,
    this.sessionContext,
    int? requestCount,
    bool? automaticUploadPerformed,
  })  : requestCount = requestCount ?? attempts.length,
        automaticUploadPerformed = automaticUploadPerformed ??
            (invocationMode == GeminiInvoiceReviewInvocationMode.automatic &&
                attempts.length > 0);

  final GeminiInvoiceReviewExecutionStatus status;
  final String message;
  final GeminiInvoiceEscalationDecision decision;
  final String model;
  final GeminiInvoiceReviewCandidate? candidate;
  final List<GeminiInvoiceReviewAttemptSummary> attempts;
  final GeminiInvoiceReviewInvocationMode invocationMode;
  final bool automaticReviewSettingEnabled;
  final int requestCount;
  final bool automaticUploadPerformed;
  final RecognitionSessionContext? sessionContext;

  bool get usedNetwork => requestCount > 0;
  bool get canCreateFormalRecord => false;
  bool get requiresUserReview => candidate != null;

  GeminiInvoiceReviewExecution withCumulativeAudit({
    required int requestCount,
    required bool automaticUploadPerformed,
  }) {
    final context = sessionContext;
    final cumulativeContext = context?.copyWith(
      logicalInvocationCount: requestCount > this.requestCount
          ? context.logicalInvocationCount + 1
          : context.logicalInvocationCount,
      physicalAttemptCount: requestCount,
    );
    return GeminiInvoiceReviewExecution(
      status: status,
      message: message,
      decision: decision,
      model: model,
      candidate: candidate,
      attempts: attempts,
      invocationMode: invocationMode,
      automaticReviewSettingEnabled: automaticReviewSettingEnabled,
      sessionContext: cumulativeContext,
      requestCount: requestCount,
      automaticUploadPerformed: automaticUploadPerformed,
    );
  }

  Map<String, Object?> toSafeSummary() {
    return <String, Object?>{
      'status': status.name,
      'decision': decision.reason,
      'model': model,
      'usedNetwork': usedNetwork,
      'requestCount': requestCount,
      'invocationMode': invocationMode.name,
      'automaticReviewSettingEnabled': automaticReviewSettingEnabled,
      'automaticUploadPerformed': automaticUploadPerformed,
      'attemptCount': attempts.length,
      'successfulKeyOrdinal': attempts
          .where((attempt) => attempt.success)
          .map((attempt) => attempt.ordinal)
          .firstOrNull,
      'candidate': candidate?.toSafeSummary(),
      'canCreateFormalRecord': canCreateFormalRecord,
      'requiresUserReview': requiresUserReview,
      if (sessionContext != null) 'resilience': sessionContext!.toSafeJson(),
    };
  }
}

class GeminiInvoiceReviewCoordinator {
  GeminiInvoiceReviewCoordinator({
    required this.settingsStore,
    required this.client,
    this.imageLoader = const FileGeminiInvoiceImageLoader(),
    this.policy = const GeminiInvoiceEscalationPolicy(),
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
        assert(maxPhysicalAttempts > 0);

  final GeminiInvoiceSettingsStore settingsStore;
  final GeminiInvoiceReviewPort client;
  final GeminiInvoiceImageLoader imageLoader;
  final GeminiInvoiceEscalationPolicy policy;
  final GeminiModelCatalogClient catalogClient;
  final GeminiKeyGroupRouter Function(List<String>) keyGroupRouterFactory;
  final GeminiFlashModelRouter modelRouter;
  final int maxPhysicalAttempts;
  final String Function() logicalInvocationIdFactory;

  Future<GeminiInvoiceReviewExecution> reviewAutomatically({
    required InvoiceAutomaticRecognitionResult localResult,
    required String localReference,
  }) {
    return review(
      localResult: localResult,
      localReference: localReference,
      invocationMode: GeminiInvoiceReviewInvocationMode.automatic,
    );
  }

  Future<GeminiInvoiceReviewExecution> review({
    required InvoiceAutomaticRecognitionResult localResult,
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

    if (!settings.experimentalInvoiceVisionEnabled) {
      return _terminalExecution(
        status: GeminiInvoiceReviewExecutionStatus.disabled,
        message: 'AI 發票覆核尚未啟用。',
        decision: decision,
        settings: settings,
        invocationMode: invocationMode,
      );
    }
    if (automatic && !settings.autoReviewLowConfidenceEnabled) {
      return _terminalExecution(
        status: GeminiInvoiceReviewExecutionStatus.disabled,
        message: '自動 AI 覆核未啟用。',
        decision: decision,
        settings: settings,
        invocationMode: invocationMode,
      );
    }
    if (!decision.shouldReview) {
      return _terminalExecution(
        status: GeminiInvoiceReviewExecutionStatus.skippedLocalComplete,
        message: decision.reason,
        decision: decision,
        settings: settings,
        invocationMode: invocationMode,
      );
    }
    if (!settings.hasApiKey) {
      return _terminalExecution(
        status: GeminiInvoiceReviewExecutionStatus.missingApiKey,
        message: '尚未設定可用的 Gemini API Key。',
        decision: decision,
        settings: settings,
        invocationMode: invocationMode,
      );
    }

    final logicalInvocationId = logicalInvocationIdFactory();
    final groups = settings.keyGroups.isNotEmpty
        ? GeminiKeyGroupRouter.fromGroups(
            <GeminiKeyGroup>[
              for (final group in settings.effectiveKeyGroups)
                GeminiKeyGroup(alias: group.alias, apiKeys: group.apiKeys),
            ],
          ).healthyGroups
        : keyGroupRouterFactory(settings.apiKeys).healthyGroups;
    if (groups.isEmpty) {
      return _terminalExecution(
        status: GeminiInvoiceReviewExecutionStatus.missingApiKey,
        message: '尚未設定可用的 Gemini API Key。',
        decision: decision,
        settings: settings,
        invocationMode: invocationMode,
      );
    }

    late GeminiInvoiceImagePayload image;
    try {
      // Frozen Original Image authority: load once and reuse the exact same
      // byte object for every physical Gemini attempt in this logical call.
      image = await imageLoader.load(localReference);
    } catch (_) {
      return _resilientExecution(
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
            return _resilientExecution(
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
              return _resilientExecution(
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
            return _resilientExecution(
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

    return _resilientExecution(
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

  GeminiInvoiceReviewExecution _terminalExecution({
    required GeminiInvoiceReviewExecutionStatus status,
    required String message,
    required GeminiInvoiceEscalationDecision decision,
    required GeminiInvoiceSettings settings,
    required GeminiInvoiceReviewInvocationMode invocationMode,
  }) {
    return GeminiInvoiceReviewExecution(
      status: status,
      message: message,
      decision: decision,
      model: settings.model,
      invocationMode: invocationMode,
      automaticReviewSettingEnabled: settings.autoReviewLowConfidenceEnabled,
      requestCount: 0,
      automaticUploadPerformed: false,
    );
  }

  GeminiInvoiceReviewExecution _resilientExecution({
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
    return GeminiInvoiceReviewExecution(
      status: status,
      message: message,
      decision: decision,
      model: activeModel,
      candidate: candidate,
      attempts: frozenAttempts,
      invocationMode: invocationMode,
      automaticReviewSettingEnabled: settings.autoReviewLowConfidenceEnabled,
      sessionContext: context,
      requestCount: frozenAttempts.length,
      automaticUploadPerformed:
          invocationMode == GeminiInvoiceReviewInvocationMode.automatic &&
              frozenAttempts.isNotEmpty,
    );
  }

  Map<String, Object?> _localSummary(InvoiceAutomaticRecognitionResult result) {
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
    return 'gemini_${micros}_$entropy';
  }
}

extension _FirstOrNullExtension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
