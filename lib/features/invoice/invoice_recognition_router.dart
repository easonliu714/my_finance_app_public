import 'invoice_qr_parser.dart';

enum InvoiceRecognitionRoute {
  electronicInvoiceQr,
  traditionalOcr,
  manualQrDesignation,
}

enum InvoiceQrPayloadRole {
  left,
  right,
  unknown,
}

class InvoiceRecognitionImageInput {
  const InvoiceRecognitionImageInput({
    required this.localReference,
    required this.fileName,
    required this.payloads,
  });

  final String localReference;
  final String fileName;
  final List<String> payloads;
}

class InvoiceQrPayloadEvidence {
  const InvoiceQrPayloadEvidence({
    required this.imageReference,
    required this.fileName,
    required this.rawPayload,
    required this.role,
    this.leftParseResult,
  });

  final String imageReference;
  final String fileName;
  final String rawPayload;
  final InvoiceQrPayloadRole role;
  final InvoiceQrParseResult? leftParseResult;

  bool get canCreateReviewCandidate =>
      role == InvoiceQrPayloadRole.left &&
      leftParseResult?.canStageCandidate == true;
}

class InvoiceQrPairCandidate {
  const InvoiceQrPairCandidate({
    required this.left,
    this.right,
    this.warnings = const <String>[],
  });

  final InvoiceQrPayloadEvidence left;
  final InvoiceQrPayloadEvidence? right;
  final List<String> warnings;

  bool get isComplete => right != null;
  bool get canCreateReviewCandidate => left.canCreateReviewCandidate;
  bool get canCreateFormalRecord => false;
}

class InvoiceRecognitionRoutingResult {
  const InvoiceRecognitionRoutingResult({
    required this.route,
    required this.message,
    this.pairs = const <InvoiceQrPairCandidate>[],
    this.unresolvedEvidence = const <InvoiceQrPayloadEvidence>[],
    this.warnings = const <String>[],
  });

  final InvoiceRecognitionRoute route;
  final String message;
  final List<InvoiceQrPairCandidate> pairs;
  final List<InvoiceQrPayloadEvidence> unresolvedEvidence;
  final List<String> warnings;

  bool get usedNetwork => false;
  bool get canCreateFormalRecord => false;
  bool get shouldRunTraditionalOcr =>
      route == InvoiceRecognitionRoute.traditionalOcr;
  bool get requiresManualQrDesignation =>
      route == InvoiceRecognitionRoute.manualQrDesignation;
  bool get hasReviewCandidate =>
      pairs.any((pair) => pair.canCreateReviewCandidate);
}

class InvoiceRecognitionRouter {
  const InvoiceRecognitionRouter({
    this.parser = const InvoiceQrParser(),
  });

  final InvoiceQrParser parser;

  InvoiceRecognitionRoutingResult route(
    List<InvoiceRecognitionImageInput> images,
  ) {
    final evidence = <InvoiceQrPayloadEvidence>[];

    for (final image in images) {
      for (final rawPayload in image.payloads) {
        final payload = rawPayload.trim();
        if (payload.isEmpty) continue;

        if (payload.startsWith('**')) {
          evidence.add(
            InvoiceQrPayloadEvidence(
              imageReference: image.localReference,
              fileName: image.fileName,
              rawPayload: payload,
              role: InvoiceQrPayloadRole.right,
            ),
          );
          continue;
        }

        final parseResult = parser.parse(payload);
        evidence.add(
          InvoiceQrPayloadEvidence(
            imageReference: image.localReference,
            fileName: image.fileName,
            rawPayload: payload,
            role: parseResult.canStageCandidate
                ? InvoiceQrPayloadRole.left
                : InvoiceQrPayloadRole.unknown,
            leftParseResult: parseResult,
          ),
        );
      }
    }

    final left = evidence
        .where((item) => item.role == InvoiceQrPayloadRole.left)
        .toList(growable: false);
    final right = evidence
        .where((item) => item.role == InvoiceQrPayloadRole.right)
        .toList(growable: false);
    final unknown = evidence
        .where((item) => item.role == InvoiceQrPayloadRole.unknown)
        .toList(growable: false);

    if (left.isEmpty && right.isEmpty) {
      return InvoiceRecognitionRoutingResult(
        route: InvoiceRecognitionRoute.traditionalOcr,
        message: unknown.isEmpty
            ? '未找到可用的電子發票 QR，改用傳統發票 OCR。'
            : '找到 QR 資料但無法確認為有效電子發票，改用傳統發票 OCR。',
        unresolvedEvidence: List<InvoiceQrPayloadEvidence>.unmodifiable(
          unknown,
        ),
      );
    }

    if (left.isEmpty) {
      return InvoiceRecognitionRoutingResult(
        route: InvoiceRecognitionRoute.manualQrDesignation,
        message: '只找到右側明細 QR，請補拍左側 QR 或重新指定。',
        unresolvedEvidence: List<InvoiceQrPayloadEvidence>.unmodifiable(
          <InvoiceQrPayloadEvidence>[...right, ...unknown],
        ),
      );
    }

    if (left.length == 1 && right.length <= 1) {
      final pairWarnings = <String>[];
      if (right.isEmpty) {
        pairWarnings.add('尚未找到右側明細 QR，僅能建立基本資料覆核候選。');
      }
      if (unknown.isNotEmpty) {
        pairWarnings.add('另有 ${unknown.length} 筆 QR 資料無法辨識，請人工確認。');
      }
      return InvoiceRecognitionRoutingResult(
        route: InvoiceRecognitionRoute.electronicInvoiceQr,
        message: right.isEmpty
            ? '已辨識電子發票左側 QR；右側明細缺漏，將以警示狀態進入覆核。'
            : '已完成電子發票左右 QR 配對，將進入人工覆核。',
        pairs: <InvoiceQrPairCandidate>[
          InvoiceQrPairCandidate(
            left: left.single,
            right: right.isEmpty ? null : right.single,
            warnings: List<String>.unmodifiable(pairWarnings),
          ),
        ],
        unresolvedEvidence: List<InvoiceQrPayloadEvidence>.unmodifiable(
          unknown,
        ),
        warnings: List<String>.unmodifiable(pairWarnings),
      );
    }

    final pairs = <InvoiceQrPairCandidate>[];
    final unusedRight = right.toList();
    final unresolved = <InvoiceQrPayloadEvidence>[];

    for (final leftEvidence in left) {
      final sameImage = unusedRight
          .where(
            (rightEvidence) =>
                rightEvidence.imageReference == leftEvidence.imageReference,
          )
          .toList(growable: false);
      if (sameImage.length != 1) {
        unresolved.add(leftEvidence);
        continue;
      }
      final matchedRight = sameImage.single;
      unusedRight.remove(matchedRight);
      pairs.add(
        InvoiceQrPairCandidate(
          left: leftEvidence,
          right: matchedRight,
        ),
      );
    }

    unresolved.addAll(unusedRight);
    unresolved.addAll(unknown);

    if (unresolved.isEmpty && pairs.length == left.length) {
      return InvoiceRecognitionRoutingResult(
        route: InvoiceRecognitionRoute.electronicInvoiceQr,
        message: '已依影像來源完成多組電子發票左右 QR 配對，將逐筆進入人工覆核。',
        pairs: List<InvoiceQrPairCandidate>.unmodifiable(pairs),
      );
    }

    return InvoiceRecognitionRoutingResult(
      route: InvoiceRecognitionRoute.manualQrDesignation,
      message: '找到多組或無法唯一配對的 QR，請指定左碼與右碼。',
      pairs: List<InvoiceQrPairCandidate>.unmodifiable(pairs),
      unresolvedEvidence: List<InvoiceQrPayloadEvidence>.unmodifiable(
        unresolved,
      ),
    );
  }

  InvoiceRecognitionRoutingResult resolveManualDesignation({
    required InvoiceRecognitionRoutingResult routingResult,
    required int leftEvidenceIndex,
    int? rightEvidenceIndex,
  }) {
    if (!routingResult.requiresManualQrDesignation) {
      return _designationFailure(
        routingResult,
        '目前辨識結果不需要指定左右 QR。',
      );
    }

    final evidence = routingResult.unresolvedEvidence;
    if (leftEvidenceIndex < 0 || leftEvidenceIndex >= evidence.length) {
      return _designationFailure(
        routingResult,
        '必須指定一筆有效的電子發票左碼。',
      );
    }

    final left = evidence[leftEvidenceIndex];
    if (!left.canCreateReviewCandidate) {
      return _designationFailure(
        routingResult,
        '指定的左碼無效，請重新選擇。',
      );
    }

    InvoiceQrPayloadEvidence? right;
    if (rightEvidenceIndex != null) {
      if (rightEvidenceIndex < 0 ||
          rightEvidenceIndex >= evidence.length ||
          rightEvidenceIndex == leftEvidenceIndex) {
        return _designationFailure(
          routingResult,
          '指定的右碼無效，請重新選擇。',
        );
      }
      right = evidence[rightEvidenceIndex];
      if (right.role != InvoiceQrPayloadRole.right) {
        return _designationFailure(
          routingResult,
          '指定的右碼無效，請重新選擇。',
        );
      }
    }

    final selected = <int>{leftEvidenceIndex};
    if (rightEvidenceIndex != null) selected.add(rightEvidenceIndex);
    final remaining = <InvoiceQrPayloadEvidence>[];
    for (var index = 0; index < evidence.length; index += 1) {
      if (!selected.contains(index)) remaining.add(evidence[index]);
    }

    final warnings = <String>[];
    if (right == null) {
      warnings.add('尚未指定右側明細 QR，僅能建立基本資料覆核候選。');
    }
    final pair = InvoiceQrPairCandidate(
      left: left,
      right: right,
      warnings: List<String>.unmodifiable(warnings),
    );

    return InvoiceRecognitionRoutingResult(
      route: InvoiceRecognitionRoute.electronicInvoiceQr,
      message: right == null
          ? '已指定電子發票左碼；右碼缺漏，將以警示狀態進入覆核。'
          : '已指定電子發票左碼與右碼，將進入人工覆核。',
      pairs: List<InvoiceQrPairCandidate>.unmodifiable(
        <InvoiceQrPairCandidate>[...routingResult.pairs, pair],
      ),
      unresolvedEvidence:
          List<InvoiceQrPayloadEvidence>.unmodifiable(remaining),
      warnings: List<String>.unmodifiable(warnings),
    );
  }

  static InvoiceRecognitionRoutingResult _designationFailure(
    InvoiceRecognitionRoutingResult routingResult,
    String message,
  ) {
    return InvoiceRecognitionRoutingResult(
      route: InvoiceRecognitionRoute.manualQrDesignation,
      message: message,
      pairs: routingResult.pairs,
      unresolvedEvidence: routingResult.unresolvedEvidence,
      warnings: routingResult.warnings,
    );
  }
}
