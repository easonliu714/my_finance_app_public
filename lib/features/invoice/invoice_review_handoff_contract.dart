import 'invoice_automatic_recognition_coordinator.dart';

const invoiceRecognitionDisclaimer = '發票紀錄僅供記帳與對獎，不能作為兌獎憑證。';

enum InvoiceReviewHandoffAction {
  reviewQrCandidate,
  reviewTraditionalOcrCandidate,
  designateQrManually,
  retryCapture,
  enterManually,
}

enum InvoiceReviewRouteOverride {
  keepSelectedRoute,
  forceTraditionalOcr,
  forceManualQrDesignation,
  manualEntry,
}

class InvoiceReviewHandoffState {
  const InvoiceReviewHandoffState({
    required this.action,
    required this.title,
    required this.routeReason,
    required this.disclaimer,
    required this.availableOverrides,
    required this.warnings,
    this.automaticResult,
  });

  final InvoiceReviewHandoffAction action;
  final String title;
  final String routeReason;
  final String disclaimer;
  final List<InvoiceReviewRouteOverride> availableOverrides;
  final List<String> warnings;
  final InvoiceAutomaticRecognitionResult? automaticResult;

  bool get usedNetwork => false;
  bool get canCreateFormalRecord => false;
  bool get requiresUserReview =>
      action == InvoiceReviewHandoffAction.reviewQrCandidate ||
      action == InvoiceReviewHandoffAction.reviewTraditionalOcrCandidate;
  bool get requiresManualQrDesignation =>
      action == InvoiceReviewHandoffAction.designateQrManually;
  bool get canRetryCapture => action == InvoiceReviewHandoffAction.retryCapture;
  bool get canEnterManually =>
      availableOverrides.contains(InvoiceReviewRouteOverride.manualEntry);
  bool get hasDisclaimer => disclaimer == invoiceRecognitionDisclaimer;

  Map<String, Object?> toSafeSummary() {
    return <String, Object?>{
      'action': action.name,
      'hasRouteReason': routeReason.trim().isNotEmpty,
      'hasDisclaimer': hasDisclaimer,
      'warningCount': warnings.length,
      'overrideCount': availableOverrides.length,
      'usedNetwork': usedNetwork,
      'canCreateFormalRecord': canCreateFormalRecord,
    };
  }
}

class InvoiceReviewHandoffPresenter {
  const InvoiceReviewHandoffPresenter();

  InvoiceReviewHandoffState fromAutomaticResult(
    InvoiceAutomaticRecognitionResult result,
  ) {
    final warnings = <String>[];
    final action = switch (result.status) {
      InvoiceAutomaticRecognitionStatus.qrReviewCandidate =>
        InvoiceReviewHandoffAction.reviewQrCandidate,
      InvoiceAutomaticRecognitionStatus.ocrReviewCandidate =>
        InvoiceReviewHandoffAction.reviewTraditionalOcrCandidate,
      InvoiceAutomaticRecognitionStatus.manualQrDesignation =>
        InvoiceReviewHandoffAction.designateQrManually,
      InvoiceAutomaticRecognitionStatus.recognitionFailed =>
        InvoiceReviewHandoffAction.retryCapture,
      InvoiceAutomaticRecognitionStatus.invalidInput =>
        InvoiceReviewHandoffAction.retryCapture,
    };

    if (result.qrResult?.failedImageReferences.isNotEmpty == true) {
      warnings.add('部分影像無法本機解碼，請確認或重新拍攝。');
    }
    final ocrWarnings = result.ocrResult?.candidate?.fieldWarnings.values
            .expand((items) => items)
            .where((item) => item.trim().isNotEmpty)
            .toList(growable: false) ??
        const <String>[];
    warnings.addAll(ocrWarnings);

    return InvoiceReviewHandoffState(
      action: action,
      title: _titleFor(action),
      routeReason: result.selectedRouteReason,
      disclaimer: invoiceRecognitionDisclaimer,
      availableOverrides: List<InvoiceReviewRouteOverride>.unmodifiable(
        _overridesFor(result.status),
      ),
      warnings: List<String>.unmodifiable(warnings),
      automaticResult: result,
    );
  }

  InvoiceReviewHandoffState applyOverride({
    required InvoiceReviewHandoffState state,
    required InvoiceReviewRouteOverride override,
  }) {
    if (!state.availableOverrides.contains(override)) {
      return InvoiceReviewHandoffState(
        action: state.action,
        title: state.title,
        routeReason: state.routeReason,
        disclaimer: state.disclaimer,
        availableOverrides: state.availableOverrides,
        warnings: List<String>.unmodifiable(
          <String>[...state.warnings, '此覆核路徑目前不可切換。'],
        ),
        automaticResult: state.automaticResult,
      );
    }

    switch (override) {
      case InvoiceReviewRouteOverride.keepSelectedRoute:
        return state;
      case InvoiceReviewRouteOverride.forceTraditionalOcr:
        return _overrideState(
          action: InvoiceReviewHandoffAction.reviewTraditionalOcrCandidate,
          routeReason: '使用者改選傳統發票 OCR 覆核路徑。',
          warnings: state.warnings,
          automaticResult: state.automaticResult,
        );
      case InvoiceReviewRouteOverride.forceManualQrDesignation:
        return _overrideState(
          action: InvoiceReviewHandoffAction.designateQrManually,
          routeReason: '使用者改選手動指定電子發票 QR 左碼與右碼。',
          warnings: state.warnings,
          automaticResult: state.automaticResult,
        );
      case InvoiceReviewRouteOverride.manualEntry:
        return _overrideState(
          action: InvoiceReviewHandoffAction.enterManually,
          routeReason: '使用者改用手動輸入發票資料。',
          warnings: state.warnings,
          automaticResult: state.automaticResult,
        );
    }
  }

  static InvoiceReviewHandoffState _overrideState({
    required InvoiceReviewHandoffAction action,
    required String routeReason,
    required List<String> warnings,
    required InvoiceAutomaticRecognitionResult? automaticResult,
  }) {
    return InvoiceReviewHandoffState(
      action: action,
      title: _titleFor(action),
      routeReason: routeReason,
      disclaimer: invoiceRecognitionDisclaimer,
      availableOverrides: List<InvoiceReviewRouteOverride>.unmodifiable(
        const <InvoiceReviewRouteOverride>[
          InvoiceReviewRouteOverride.keepSelectedRoute,
          InvoiceReviewRouteOverride.manualEntry,
        ],
      ),
      warnings: warnings,
      automaticResult: automaticResult,
    );
  }

  static String _titleFor(InvoiceReviewHandoffAction action) {
    return switch (action) {
      InvoiceReviewHandoffAction.reviewQrCandidate => '電子發票 QR 覆核',
      InvoiceReviewHandoffAction.reviewTraditionalOcrCandidate =>
        '傳統發票 OCR 覆核',
      InvoiceReviewHandoffAction.designateQrManually => '指定電子發票 QR 左碼與右碼',
      InvoiceReviewHandoffAction.retryCapture => '重新拍攝或選擇影像',
      InvoiceReviewHandoffAction.enterManually => '手動輸入發票資料',
    };
  }

  static List<InvoiceReviewRouteOverride> _overridesFor(
    InvoiceAutomaticRecognitionStatus status,
  ) {
    switch (status) {
      case InvoiceAutomaticRecognitionStatus.qrReviewCandidate:
        return const <InvoiceReviewRouteOverride>[
          InvoiceReviewRouteOverride.keepSelectedRoute,
          InvoiceReviewRouteOverride.forceTraditionalOcr,
          InvoiceReviewRouteOverride.forceManualQrDesignation,
          InvoiceReviewRouteOverride.manualEntry,
        ];
      case InvoiceAutomaticRecognitionStatus.ocrReviewCandidate:
        return const <InvoiceReviewRouteOverride>[
          InvoiceReviewRouteOverride.keepSelectedRoute,
          InvoiceReviewRouteOverride.forceManualQrDesignation,
          InvoiceReviewRouteOverride.manualEntry,
        ];
      case InvoiceAutomaticRecognitionStatus.manualQrDesignation:
        return const <InvoiceReviewRouteOverride>[
          InvoiceReviewRouteOverride.keepSelectedRoute,
          InvoiceReviewRouteOverride.forceTraditionalOcr,
          InvoiceReviewRouteOverride.manualEntry,
        ];
      case InvoiceAutomaticRecognitionStatus.recognitionFailed:
      case InvoiceAutomaticRecognitionStatus.invalidInput:
        return const <InvoiceReviewRouteOverride>[
          InvoiceReviewRouteOverride.keepSelectedRoute,
          InvoiceReviewRouteOverride.manualEntry,
        ];
    }
  }
}
