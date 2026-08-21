import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../invoice/gemini/gemini_invoice_settings.dart';
import '../invoice/gemini/gemini_invoice_settings_repository.dart';
import '../invoice/gemini/gemini_model_catalog_client.dart';
import '../recognition_ai/gemini_flash_model_router.dart';
import '../recognition_ai/gemini_key_group_router.dart';
import '../recognition_ai/recognition_ai_contract.dart';
import 'gemini_product_recognition_client.dart';
import 'product_recognition_candidate.dart';

class ProductRecognitionImagePayload {
  const ProductRecognitionImagePayload({
    required this.bytes,
    required this.mimeType,
  });

  final Uint8List bytes;
  final String mimeType;
}

abstract interface class ProductRecognitionImageLoader {
  Future<ProductRecognitionImagePayload> load(String localReference);
}

class FileProductRecognitionImageLoader
    implements ProductRecognitionImageLoader {
  const FileProductRecognitionImageLoader({
    this.maximumBytes = 8 * 1024 * 1024,
  });

  final int maximumBytes;

  @override
  Future<ProductRecognitionImagePayload> load(String localReference) async {
    final reference = localReference.trim();
    if (reference.isEmpty) {
      throw const FileSystemException('商品影像參照為空白');
    }
    final file = File(reference);
    if (!await file.exists()) {
      throw const FileSystemException('商品影像檔案不存在');
    }
    final length = await file.length();
    if (length <= 0 || length > maximumBytes) {
      throw const FileSystemException('商品影像大小不符合安全邊界');
    }
    final extension = reference.split('.').last.toLowerCase();
    final mimeType = switch (extension) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => throw const FileSystemException('商品影像格式不支援'),
    };
    return ProductRecognitionImagePayload(
      bytes: await file.readAsBytes(),
      mimeType: mimeType,
    );
  }
}

enum ProductRecognitionExecutionStatus {
  missingApiKey,
  invalidImage,
  success,
  failed,
}

class ProductRecognitionAttemptSummary {
  const ProductRecognitionAttemptSummary({
    required this.ordinal,
    required this.maskedKey,
    required this.model,
    required this.success,
    required this.message,
  });

  final int ordinal;
  final String maskedKey;
  final String model;
  final bool success;
  final String message;

  Map<String, Object?> toSafeJson() => <String, Object?>{
        'ordinal': ordinal,
        'masked_key': maskedKey,
        'model': model,
        'success': success,
        'message': message,
      };
}

class ProductRecognitionExecution {
  const ProductRecognitionExecution({
    required this.status,
    required this.message,
    required this.model,
    this.candidate,
    this.attempts = const <ProductRecognitionAttemptSummary>[],
    this.sessionContext,
  });

  final ProductRecognitionExecutionStatus status;
  final String message;
  final String model;
  final ProductRecognitionCandidate? candidate;
  final List<ProductRecognitionAttemptSummary> attempts;
  final RecognitionSessionContext? sessionContext;

  int get requestCount => attempts.length;
  bool get usedNetwork => requestCount > 0;
  bool get requiresUserReview => candidate != null;
  bool get canCreateFormalRecord => false;

  Map<String, Object?> toSafeSummary() => <String, Object?>{
        'status': status.name,
        'message': message,
        'model': model,
        'requestCount': requestCount,
        'usedNetwork': usedNetwork,
        'requiresUserReview': requiresUserReview,
        'canCreateFormalRecord': canCreateFormalRecord,
        'attempts': <Object?>[
          for (final attempt in attempts) attempt.toSafeJson(),
        ],
        if (candidate != null) 'candidate': candidate!.toSafeJson(),
        if (sessionContext != null)
          'resilience': sessionContext!.toSafeJson(),
      };
}

class ProductRecognitionCoordinator {
  ProductRecognitionCoordinator({
    required this.settingsStore,
    required this.client,
    this.imageLoader = const FileProductRecognitionImageLoader(),
    GeminiModelCatalogClient? catalogClient,
    GeminiKeyGroupRouter Function(List<String>)? keyRouterFactory,
    this.modelRouter = const GeminiFlashModelRouter(),
    this.maxPhysicalAttempts = 8,
    String Function()? logicalInvocationIdFactory,
  })  : catalogClient = catalogClient ?? GeminiModelCatalogClient(),
        keyRouterFactory = keyRouterFactory ?? GeminiKeyGroupRouter.fromApiKeys,
        logicalInvocationIdFactory =
            logicalInvocationIdFactory ?? _defaultLogicalInvocationId,
        assert(maxPhysicalAttempts > 0);

  final GeminiInvoiceSettingsStore settingsStore;
  final GeminiProductRecognitionPort client;
  final ProductRecognitionImageLoader imageLoader;
  final GeminiModelCatalogClient catalogClient;
  final GeminiKeyGroupRouter Function(List<String>) keyRouterFactory;
  final GeminiFlashModelRouter modelRouter;
  final int maxPhysicalAttempts;
  final String Function() logicalInvocationIdFactory;

  Future<ProductRecognitionExecution> recognize({
    required String localReference,
  }) async {
    final settings = await settingsStore.load();
    final keySlots = keyRouterFactory(settings.effectiveApiKeys).healthyGroups;
    if (keySlots.isEmpty) {
      return ProductRecognitionExecution(
        status: ProductRecognitionExecutionStatus.missingApiKey,
        message: '尚未設定可用的 Gemini API Key。',
        model: settings.model,
      );
    }

    late ProductRecognitionImagePayload image;
    try {
      image = await imageLoader.load(localReference);
    } catch (_) {
      return ProductRecognitionExecution(
        status: ProductRecognitionExecutionStatus.invalidImage,
        message: '無法安全讀取待辨識商品影像。',
        model: settings.model,
      );
    }

    final logicalInvocationId = logicalInvocationIdFactory();
    final attempts = <ProductRecognitionAttemptSummary>[];
    final events = <RecognitionAiRoutingEvent>[];
    final attemptedModels = <String>{};
    final attemptedKeySlots = <String>{};
    var fallbackReason = RecognitionAiFallbackReason.none;
    var activeModel = settings.model;
    var activeKeySlotAlias = keySlots.first.alias;
    var preferredForNextKey = settings.model;
    var modelCatalogChecked = false;

    for (final keySlot in keySlots) {
      if (attempts.length >= maxPhysicalAttempts) break;
      attemptedKeySlots.add(keySlot.alias);
      activeKeySlotAlias = keySlot.alias;
      final key = keySlot.apiKeys.first;

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
              keyGroupAlias: keySlot.alias,
              model: preferredForNextKey,
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
              keyGroupAlias: keySlot.alias,
              model: preferredForNextKey,
              reason: fallbackReason,
              physicalRequestSent: false,
              message: 'model_catalog_auth',
            ),
          );
          continue;
        }
        if (error.statusCode != null && error.statusCode! >= 500) {
          fallbackReason = RecognitionAiFallbackReason.serviceUnavailable;
        } else {
          fallbackReason = RecognitionAiFallbackReason.network;
        }
      } on TimeoutException {
        modelCatalogChecked = true;
        fallbackReason = RecognitionAiFallbackReason.timeout;
      } catch (_) {
        modelCatalogChecked = true;
        fallbackReason = RecognitionAiFallbackReason.network;
      }

      final preferredAvailable = catalog.isEmpty ||
          modelRouter.isPreferredAvailable(
            preferredModel: preferredForNextKey,
            catalog: catalog,
          );
      final modelCandidates = modelRouter.candidates(
        preferredModel: preferredForNextKey,
        catalog: catalog,
      );
      if (!preferredAvailable && modelCandidates.isNotEmpty) {
        fallbackReason = RecognitionAiFallbackReason.modelUnavailable;
        events.add(
          RecognitionAiRoutingEvent(
            keyGroupAlias: keySlot.alias,
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
            keyGroupAlias: keySlot.alias,
            model: preferredForNextKey,
            reason: fallbackReason,
            physicalRequestSent: false,
            message: 'no_flash_generate_content_model',
          ),
        );
        continue;
      }

      var moveToNextKey = false;
      for (final model in modelCandidates) {
        if (attempts.length >= maxPhysicalAttempts || moveToNextKey) break;
        activeModel = model;
        attemptedModels.add(model);
        var transientRetryUsed = false;

        while (attempts.length < maxPhysicalAttempts) {
          try {
            final candidate = await client.recognize(
              apiKey: key,
              model: model,
              imageBytes: image.bytes,
              mimeType: image.mimeType,
            );
            attempts.add(
              ProductRecognitionAttemptSummary(
                ordinal: attempts.length + 1,
                maskedKey: GeminiInvoiceSettings.maskApiKey(key),
                model: model,
                success: true,
                message: '商品辨識成功',
              ),
            );
            events.add(
              RecognitionAiRoutingEvent(
                keyGroupAlias: keySlot.alias,
                model: model,
                reason: RecognitionAiFallbackReason.none,
                physicalRequestSent: true,
                message: 'success',
              ),
            );
            return _execution(
              status: ProductRecognitionExecutionStatus.success,
              message: '已取得商品 AI 辨識候選，請人工覆核。',
              model: model,
              candidate: candidate,
              logicalInvocationId: logicalInvocationId,
              keySlotAlias: keySlot.alias,
              fallbackReason: fallbackReason,
              modelCatalogChecked: modelCatalogChecked,
              attempts: attempts,
              events: events,
              attemptedModels: attemptedModels,
              attemptedKeySlots: attemptedKeySlots,
            );
          } on GeminiProductRecognitionException catch (error) {
            attempts.add(
              ProductRecognitionAttemptSummary(
                ordinal: attempts.length + 1,
                maskedKey: GeminiInvoiceSettings.maskApiKey(key),
                model: model,
                success: false,
                message: error.message,
              ),
            );

            if (error.kind == GeminiProductRecognitionFailureKind.quota) {
              fallbackReason = RecognitionAiFallbackReason.quotaExhausted;
              preferredForNextKey = model;
              moveToNextKey = true;
            } else if (error.kind ==
                GeminiProductRecognitionFailureKind.authentication) {
              fallbackReason = RecognitionAiFallbackReason.authenticationFailed;
              preferredForNextKey = model;
              moveToNextKey = true;
            } else if (error.statusCode == 404) {
              fallbackReason = RecognitionAiFallbackReason.modelUnavailable;
            } else if (error.kind ==
                    GeminiProductRecognitionFailureKind.serviceUnavailable ||
                error.kind == GeminiProductRecognitionFailureKind.timeout ||
                error.kind == GeminiProductRecognitionFailureKind.network) {
              fallbackReason = switch (error.kind) {
                GeminiProductRecognitionFailureKind.timeout =>
                  RecognitionAiFallbackReason.timeout,
                GeminiProductRecognitionFailureKind.network =>
                  RecognitionAiFallbackReason.network,
                _ => RecognitionAiFallbackReason.serviceUnavailable,
              };
              if (!transientRetryUsed &&
                  attempts.length < maxPhysicalAttempts) {
                transientRetryUsed = true;
                events.add(
                  RecognitionAiRoutingEvent(
                    keyGroupAlias: keySlot.alias,
                    model: model,
                    reason: fallbackReason,
                    physicalRequestSent: true,
                    message: 'bounded_retry',
                  ),
                );
                continue;
              }
              preferredForNextKey = model;
              moveToNextKey = true;
            } else {
              events.add(
                RecognitionAiRoutingEvent(
                  keyGroupAlias: keySlot.alias,
                  model: model,
                  reason: fallbackReason,
                  physicalRequestSent: true,
                  message: error.kind.name,
                ),
              );
              return _execution(
                status: ProductRecognitionExecutionStatus.failed,
                message: '商品 AI 辨識未完成；照片仍保留於本機待人工處理。',
                model: model,
                logicalInvocationId: logicalInvocationId,
                keySlotAlias: keySlot.alias,
                fallbackReason: fallbackReason,
                modelCatalogChecked: modelCatalogChecked,
                attempts: attempts,
                events: events,
                attemptedModels: attemptedModels,
                attemptedKeySlots: attemptedKeySlots,
              );
            }

            events.add(
              RecognitionAiRoutingEvent(
                keyGroupAlias: keySlot.alias,
                model: model,
                reason: fallbackReason,
                physicalRequestSent: true,
                message: error.kind.name,
              ),
            );
            break;
          } catch (_) {
            attempts.add(
              ProductRecognitionAttemptSummary(
                ordinal: attempts.length + 1,
                maskedKey: GeminiInvoiceSettings.maskApiKey(key),
                model: model,
                success: false,
                message: 'Gemini 商品辨識發生未分類錯誤。',
              ),
            );
            return _execution(
              status: ProductRecognitionExecutionStatus.failed,
              message: '商品 AI 辨識未完成；照片仍保留於本機待人工處理。',
              model: model,
              logicalInvocationId: logicalInvocationId,
              keySlotAlias: keySlot.alias,
              fallbackReason: fallbackReason,
              modelCatalogChecked: modelCatalogChecked,
              attempts: attempts,
              events: events,
              attemptedModels: attemptedModels,
              attemptedKeySlots: attemptedKeySlots,
            );
          }
        }
      }
    }

    return _execution(
      status: ProductRecognitionExecutionStatus.failed,
      message: '商品 AI 辨識未完成；可稍後重試或改由人工記帳。',
      model: activeModel,
      logicalInvocationId: logicalInvocationId,
      keySlotAlias: activeKeySlotAlias,
      fallbackReason: fallbackReason,
      modelCatalogChecked: modelCatalogChecked,
      attempts: attempts,
      events: events,
      attemptedModels: attemptedModels,
      attemptedKeySlots: attemptedKeySlots,
    );
  }

  ProductRecognitionExecution _execution({
    required ProductRecognitionExecutionStatus status,
    required String message,
    required String model,
    required String logicalInvocationId,
    required String keySlotAlias,
    required RecognitionAiFallbackReason fallbackReason,
    required bool modelCatalogChecked,
    required List<ProductRecognitionAttemptSummary> attempts,
    required List<RecognitionAiRoutingEvent> events,
    required Set<String> attemptedModels,
    required Set<String> attemptedKeySlots,
    ProductRecognitionCandidate? candidate,
  }) {
    final frozenAttempts =
        List<ProductRecognitionAttemptSummary>.unmodifiable(attempts);
    final session = RecognitionSessionContext(
      logicalInvocationId: logicalInvocationId,
      provider: 'Gemini',
      activeModel: model,
      keyGroupAlias: keySlotAlias,
      logicalInvocationCount: 1,
      physicalAttemptCount: frozenAttempts.length,
      modelAttemptCount: attemptedModels.length,
      keyGroupAttemptCount: attemptedKeySlots.length,
      fallbackReason: fallbackReason,
      modelCatalogChecked: modelCatalogChecked,
      events: List<RecognitionAiRoutingEvent>.unmodifiable(events),
    );
    return ProductRecognitionExecution(
      status: status,
      message: message,
      model: model,
      candidate: candidate,
      attempts: frozenAttempts,
      sessionContext: session,
    );
  }

  static String _defaultLogicalInvocationId() {
    final micros = DateTime.now().toUtc().microsecondsSinceEpoch.toRadixString(36);
    final entropy = Random.secure().nextInt(0x7fffffff).toRadixString(36);
    return 'product_gemini_${micros}_$entropy';
  }
}
