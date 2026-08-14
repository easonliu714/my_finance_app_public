import 'dart:io';
import 'dart:typed_data';

import '../invoice_automatic_recognition_coordinator.dart';
import '../traditional_invoice_ocr_review.dart';
import 'gemini_invoice_review.dart';
import 'gemini_invoice_review_client.dart';
import 'gemini_invoice_settings.dart';
import 'gemini_invoice_settings_repository.dart';

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
        return const GeminiInvoiceEscalationDecision(
          shouldReview: false,
          reason: '已有結構化 QR 覆核候選，本階段不自動呼叫 AI。',
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
  const FileGeminiInvoiceImageLoader({
    this.maximumBytes = 8 * 1024 * 1024,
  });

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
  });

  final GeminiInvoiceReviewExecutionStatus status;
  final String message;
  final GeminiInvoiceEscalationDecision decision;
  final String model;
  final GeminiInvoiceReviewCandidate? candidate;
  final List<GeminiInvoiceReviewAttemptSummary> attempts;

  bool get usedNetwork => attempts.isNotEmpty;
  bool get canCreateFormalRecord => false;
  bool get requiresUserReview => candidate != null;

  Map<String, Object?> toSafeSummary() {
    return <String, Object?>{
      'status': status.name,
      'decision': decision.reason,
      'model': model,
      'usedNetwork': usedNetwork,
      'attemptCount': attempts.length,
      'successfulKeyOrdinal': attempts
          .where((attempt) => attempt.success)
          .map((attempt) => attempt.ordinal)
          .firstOrNull,
      'candidate': candidate?.toSafeSummary(),
      'canCreateFormalRecord': canCreateFormalRecord,
      'requiresUserReview': requiresUserReview,
    };
  }
}

class GeminiInvoiceReviewCoordinator {
  const GeminiInvoiceReviewCoordinator({
    required this.settingsStore,
    required this.client,
    this.imageLoader = const FileGeminiInvoiceImageLoader(),
    this.policy = const GeminiInvoiceEscalationPolicy(),
  });

  final GeminiInvoiceSettingsStore settingsStore;
  final GeminiInvoiceReviewPort client;
  final GeminiInvoiceImageLoader imageLoader;
  final GeminiInvoiceEscalationPolicy policy;

  Future<GeminiInvoiceReviewExecution> review({
    required InvoiceAutomaticRecognitionResult localResult,
    required String localReference,
    bool forceReview = false,
  }) async {
    final settings = await settingsStore.load();
    final decision = forceReview
        ? const GeminiInvoiceEscalationDecision(
            shouldReview: true,
            reason: '使用者要求強制 AI 覆核。',
          )
        : policy.evaluate(localResult);

    if (!settings.experimentalInvoiceVisionEnabled) {
      return GeminiInvoiceReviewExecution(
        status: GeminiInvoiceReviewExecutionStatus.disabled,
        message: 'AI 發票覆核實驗功能尚未啟用。',
        decision: decision,
        model: settings.model,
      );
    }
    if (!decision.shouldReview) {
      return GeminiInvoiceReviewExecution(
        status: GeminiInvoiceReviewExecutionStatus.skippedLocalComplete,
        message: decision.reason,
        decision: decision,
        model: settings.model,
      );
    }
    if (!settings.hasApiKey) {
      return GeminiInvoiceReviewExecution(
        status: GeminiInvoiceReviewExecutionStatus.missingApiKey,
        message: '尚未設定可用的 Gemini API Key。',
        decision: decision,
        model: settings.model,
      );
    }

    late GeminiInvoiceImagePayload image;
    try {
      image = await imageLoader.load(localReference);
    } catch (_) {
      return GeminiInvoiceReviewExecution(
        status: GeminiInvoiceReviewExecutionStatus.invalidImage,
        message: '無法安全讀取待覆核影像。',
        decision: decision,
        model: settings.model,
      );
    }

    final attempts = <GeminiInvoiceReviewAttemptSummary>[];
    for (var index = 0; index < settings.apiKeys.length; index++) {
      final key = settings.apiKeys[index];
      final maskedKey = GeminiInvoiceSettings.maskApiKey(key);
      try {
        final candidate = await client.review(
          apiKey: key,
          model: settings.model,
          imageBytes: image.bytes,
          mimeType: image.mimeType,
          localSummary: _localSummary(localResult),
        );
        attempts.add(
          GeminiInvoiceReviewAttemptSummary(
            ordinal: index + 1,
            maskedKey: maskedKey,
            success: true,
            message: '覆核成功',
          ),
        );
        return GeminiInvoiceReviewExecution(
          status: GeminiInvoiceReviewExecutionStatus.success,
          message: '已取得獨立 Gemini 覆核候選，尚未覆寫本機結果。',
          decision: decision,
          model: settings.model,
          candidate: candidate,
          attempts: List<GeminiInvoiceReviewAttemptSummary>.unmodifiable(
            attempts,
          ),
        );
      } on GeminiInvoiceReviewException catch (error) {
        attempts.add(
          GeminiInvoiceReviewAttemptSummary(
            ordinal: index + 1,
            maskedKey: maskedKey,
            success: false,
            message: error.message,
          ),
        );
        if (!error.retryWithNextKey) break;
      } catch (_) {
        attempts.add(
          GeminiInvoiceReviewAttemptSummary(
            ordinal: index + 1,
            maskedKey: maskedKey,
            success: false,
            message: 'Gemini 覆核發生未分類錯誤。',
          ),
        );
        break;
      }
    }

    return GeminiInvoiceReviewExecution(
      status: GeminiInvoiceReviewExecutionStatus.failed,
      message: '所有可嘗試的 Gemini API Key 均未完成覆核。',
      decision: decision,
      model: settings.model,
      attempts: List<GeminiInvoiceReviewAttemptSummary>.unmodifiable(
        attempts,
      ),
    );
  }

  Map<String, Object?> _localSummary(
    InvoiceAutomaticRecognitionResult result,
  ) {
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
      'localWarningFieldCount': candidate?.fieldWarnings.values
              .where((warnings) => warnings.isNotEmpty)
              .length ??
          0,
    };
  }
}

extension _FirstOrNullExtension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
