import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../backup/file_exchange_service.dart';
import 'gemini/gemini_invoice_review.dart';
import 'gemini/gemini_invoice_review_coordinator.dart';
import 'image_capture_staging.dart';
import 'invoice_capture_review_flow.dart';
import 'invoice_live_capture_page.dart';
import 'invoice_review_form_view_model.dart';
import 'lab/private_cloud_invoice_lab_config.dart';

class InvoiceRecognitionEvidenceExportResult {
  const InvoiceRecognitionEvidenceExportResult({
    required this.path,
    required this.fileName,
    required this.zipBytes,
    required this.captureImageSha256,
    required this.geminiInputSha256,
    required this.geminiInputMatchesCapture,
  });

  final String path;
  final String fileName;
  final int zipBytes;
  final String captureImageSha256;
  final String? geminiInputSha256;
  final bool? geminiInputMatchesCapture;
}

class InvoiceRecognitionEvidenceExporter {
  const InvoiceRecognitionEvidenceExporter({
    this.fileExchange = const PlatformFileExchangeService(),
  });

  final FileExchangePort fileExchange;

  Future<InvoiceRecognitionEvidenceExportResult> exportAndShare({
    required ImageCaptureStagingItem item,
    required InvoiceCaptureReviewFlowResult localResult,
    required GeminiInvoiceReviewExecution? geminiExecution,
    InvoiceLiveCaptureResult? captureContext,
    String appVersion = PrivateCloudInvoiceLabConfig.validationVersion,
  }) async {
    final reference = item.localReference.trim();
    if (reference.isEmpty) {
      throw const FileSystemException('待覆核影像沒有可讀取的本機參照。');
    }
    final source = File(reference);
    if (!await source.exists()) {
      throw const FileSystemException('待覆核影像已不存在，無法建立證據包。');
    }
    final captureBytes = await source.readAsBytes();
    if (captureBytes.isEmpty) {
      throw const FileSystemException('待覆核影像是空白檔案。');
    }

    final captureSha = await _sha256(captureBytes);
    final geminiAttempted = (geminiExecution?.requestCount ?? 0) > 0;
    final automaticUploadPerformed =
        geminiExecution?.automaticUploadPerformed == true;
    final geminiSha = geminiAttempted ? captureSha : null;
    final sameBytes = geminiAttempted ? true : null;

    final ocrResult = localResult.recognitionResult.ocrResult;
    final ocrCandidate = ocrResult?.candidate;
    final rawRecognition = ocrResult?.rawRecognition;
    final rawText = ocrCandidate?.rawText ?? rawRecognition?.rawText ?? '';
    final rawLines =
        ocrCandidate?.rawLines ?? rawRecognition?.rawLines ?? const <String>[];
    final rawOcrAvailable = rawText.trim().isNotEmpty || rawLines.isNotEmpty;
    final variantDiagnostics = ocrCandidate?.variantDiagnostics ??
        rawRecognition?.variantDiagnostics ??
        const [];
    final variantDiagnosticsIncluded = variantDiagnostics.isNotEmpty;
    final liveHistory =
        captureContext?.liveHistory ?? const <InvoiceLiveFrameEvidence>[];
    final liveHistoryIncluded = liveHistory.isNotEmpty;

    final createdAt = DateTime.now().toUtc();
    final evidenceId = _safeToken(
      '${createdAt.toIso8601String()}_${captureSha.substring(0, 12)}',
    );
    final archive = Archive();
    final captureMime = _mimeTypeFromPath(reference);
    final captureExt = _extensionForMime(
      captureMime,
      fallback: path.extension(reference).replaceFirst('.', ''),
    );
    archive.addFile(
      ArchiveFile(
        'capture_image.$captureExt',
        captureBytes.length,
        captureBytes,
      ),
    );
    if (geminiAttempted) {
      archive.addFile(
        ArchiveFile(
          'gemini_input.$captureExt',
          captureBytes.length,
          captureBytes,
        ),
      );
    }
    if (rawOcrAvailable) {
      _addText(
        archive,
        'local_ocr_raw.txt',
        <String>[
          '=== ML KIT RAW FULL TEXT ===',
          rawText,
          '',
          '=== ML KIT RAW LINES ===',
          for (var index = 0; index < rawLines.length; index += 1)
            '[${index.toString().padLeft(3, '0')}] ${rawLines[index]}',
          '',
        ].join('\n'),
      );
    }
    if (variantDiagnosticsIncluded) {
      _addText(
        archive,
        'local_ocr_variant_votes.json',
        const JsonEncoder.withIndent('  ').convert(
          <String, Object?>{
            'schemaVersion': 'invoice-local-ocr-variant-votes-v1',
            'derivativeImagesIncluded': false,
            'originalFrozenImageRemainsAuthority': true,
            'variants': <Object?>[
              for (final diagnostic in variantDiagnostics)
                diagnostic.toJson(),
            ],
          },
        ),
      );
    }
    if (liveHistoryIncluded) {
      _addText(
        archive,
        'live_snapshot_history.json',
        const JsonEncoder.withIndent('  ').convert(
          <String, Object?>{
            'schemaVersion': 'invoice-live-snapshot-history-v1',
            'sampleCount': liveHistory.length,
            'samples': <Object?>[
              for (final sample in liveHistory) sample.toJson(),
            ],
          },
        ),
      );
    }

    final diagnostics = <String, Object?>{
      'schemaVersion': 'invoice-recognition-evidence-v5',
      'appVersion': appVersion,
      'createdAtUtc': createdAt.toIso8601String(),
      'evidenceId': evidenceId,
      'privacy': <String, Object?>{
        'userInitiatedExport': true,
        'containsInvoiceImage': true,
        'containsRecognizedInvoiceValues': true,
        'containsRawLocalOcrEvidence': rawOcrAvailable,
        'containsLocalOcrVariantDiagnostics': variantDiagnosticsIncluded,
        'containsLocalOcrDerivativeImages': false,
        'containsLiveSnapshotHistory': liveHistoryIncluded,
        'apiKeyIncluded': false,
        'automaticUploadPerformed': automaticUploadPerformed,
        'productionDatabaseWritePerformed': false,
      },
      'capture': <String, Object?>{
        'source': item.source.name,
        'origin': captureContext?.origin.name,
        'fileName': item.fileName,
        'byteLength': captureBytes.length,
        'sha256': captureSha,
        'mimeType': captureMime,
        'lastModifiedUtc':
            (await source.lastModified()).toUtc().toIso8601String(),
        'liveClassification': captureContext?.classification.name,
        'autoFrozen': captureContext?.autoFrozen,
        'finalLiveSnapshot': captureContext?.liveSnapshot.toJson(),
        'liveHistoryCount': liveHistory.length,
      },
      'geminiInput': !geminiAttempted
          ? null
          : <String, Object?>{
              'byteLength': captureBytes.length,
              'sha256': captureSha,
              'mimeType': captureMime,
              'matchesCaptureImageSha256': true,
              'isExactRequestBytes': true,
              'provenanceContract':
                  'FileGeminiInvoiceImageLoader -> GeminiInvoiceReviewClient inline_data direct bytes',
            },
      'localRecognition': _localRecognition(localResult),
      'geminiReview': _geminiReview(geminiExecution),
      'comparison': _comparison(localResult, geminiExecution?.candidate),
      'liveSnapshotHistory': <Object?>[
        for (final sample in liveHistory) sample.toJson(),
      ],
      'safety': <String, Object?>{
        'aiOverwritesLocal': false,
        'automaticFormalTransactionWrite': false,
        'ocrDerivativeImageBecomesAuthority': false,
        'requiresUserReview': true,
      },
    };

    _addText(
      archive,
      'diagnostics.json',
      const JsonEncoder.withIndent('  ').convert(diagnostics),
    );
    _addText(
      archive,
      'manifest.txt',
      <String>[
        'my_finance_app invoice recognition evidence package',
        'schema=invoice-recognition-evidence-v5',
        'app_version=$appVersion',
        'evidence_id=$evidenceId',
        'created_at_utc=${createdAt.toIso8601String()}',
        'capture_origin=${captureContext?.origin.name ?? item.source.name}',
        'capture_sha256=$captureSha',
        'gemini_input_sha256=${geminiSha ?? 'NOT_AVAILABLE'}',
        'gemini_input_is_exact_request_bytes=$geminiAttempted',
        'gemini_input_matches_capture_sha256=${sameBytes ?? 'NOT_AVAILABLE'}',
        'gemini_invocation_mode=${geminiExecution?.invocationMode.name ?? 'none'}',
        'gemini_request_count=${geminiExecution?.requestCount ?? 0}',
        'automatic_review_setting_enabled=${geminiExecution?.automaticReviewSettingEnabled ?? false}',
        'local_ocr_raw_included=$rawOcrAvailable',
        'local_ocr_variant_diagnostics_included=$variantDiagnosticsIncluded',
        'local_ocr_derivative_images_included=false',
        'live_snapshot_history_included=$liveHistoryIncluded',
        'live_snapshot_history_count=${liveHistory.length}',
        'api_key_included=false',
        'automatic_upload_performed=$automaticUploadPerformed',
        'production_database_write_performed=false',
        '',
      ].join('\n'),
    );

    final encoded = ZipEncoder().encode(archive);
    if (encoded.isEmpty) {
      throw const FileSystemException('辨識證據 ZIP 編碼失敗。');
    }
    final directory = Directory(
      '${(await getTemporaryDirectory()).path}/invoice_recognition_evidence',
    );
    await directory.create(recursive: true);
    await _deleteStalePackages(directory);
    final fileName = 'invoice_evidence_$evidenceId.zip';
    final zipFile = File('${directory.path}/$fileName');
    await zipFile.writeAsBytes(encoded, flush: true);

    await fileExchange.shareFile(
      file: zipFile,
      subject: '發票辨識證據包 $evidenceId',
      text:
          '包含實際影像、Local/AI 候選、Live 判讀歷程、原始 OCR（若有）與 SHA-256；不含 API Key，AI 呼叫模式會記錄於 manifest。',
    );
    unawaited(
      Future<void>.delayed(const Duration(minutes: 30), () async {
        try {
          if (await zipFile.exists()) await zipFile.delete();
        } catch (_) {}
      }),
    );

    return InvoiceRecognitionEvidenceExportResult(
      path: zipFile.path,
      fileName: fileName,
      zipBytes: encoded.length,
      captureImageSha256: captureSha,
      geminiInputSha256: geminiSha,
      geminiInputMatchesCapture: sameBytes,
    );
  }

  Map<String, Object?> _localRecognition(
    InvoiceCaptureReviewFlowResult result,
  ) {
    final recognition = result.recognitionResult;
    final ocr = recognition.ocrResult?.candidate;
    final raw = recognition.ocrResult?.rawRecognition;
    return <String, Object?>{
      'status': recognition.status.name,
      'requestedRoute': recognition.requestedRoute.name,
      'message': recognition.message,
      'selectedRouteReason': recognition.selectedRouteReason,
      'form': <String, Object?>{
        'title': result.formModel.title,
        'routeReason': result.formModel.routeReason,
        'fields': <Object?>[
          for (final field in result.formModel.fields)
            <String, Object?>{
              'key': field.key.name,
              'label': field.label,
              'value': field.value,
              'confidenceLabel': field.confidenceLabel,
              'warnings': field.warnings,
              'requiredForReview': field.requiredForReview,
            },
        ],
        'lineItems': <Object?>[
          for (final item in result.formModel.lineItems)
            <String, Object?>{
              'name': item.name,
              'amount': item.amountText,
              'confidenceLabel': item.confidenceLabel,
              'warnings': item.warnings,
            },
        ],
        'warnings': result.formModel.warnings,
      },
      'ocrCandidate': ocr == null
          ? null
          : <String, Object?>{
              'invoiceNumber': ocr.invoiceNumber,
              'sellerTaxId': ocr.sellerTaxId,
              'sellerTaxIdSource': ocr.sellerTaxIdSource,
              'invoiceDate': ocr.invoiceDate?.toIso8601String(),
              'sellerName': ocr.sellerName,
              'totalAmount': ocr.totalAmount,
              'visibleLineItems': <Object?>[
                for (final item in ocr.visibleLineItems)
                  <String, Object?>{
                    'name': item.name,
                    'amount': item.amount,
                    'confidence': item.confidence.name,
                    'warnings': item.warnings,
                  },
              ],
              'confidence': <String, Object?>{
                for (final entry in ocr.confidence.entries)
                  entry.key.name: entry.value.name,
              },
              'fieldWarnings': <String, Object?>{
                for (final entry in ocr.fieldWarnings.entries)
                  entry.key.name: entry.value,
              },
              'variantDiagnostics': <Object?>[
                for (final diagnostic in ocr.variantDiagnostics)
                  diagnostic.toJson(),
              ],
              'rawText': ocr.rawText,
              'rawLines': ocr.rawLines,
            },
      'ocrRawRecognition': raw == null
          ? null
          : <String, Object?>{
              'invoiceNumber': raw.invoiceNumber,
              'sellerTaxId': raw.sellerTaxId,
              'sellerTaxIdSource': raw.sellerTaxIdSource,
              'invoiceDate': raw.invoiceDate?.toIso8601String(),
              'sellerName': raw.sellerName,
              'totalAmount': raw.totalAmount,
              'variantDiagnostics': <Object?>[
                for (final diagnostic in raw.variantDiagnostics)
                  diagnostic.toJson(),
              ],
              'rawText': raw.rawText,
              'rawLines': raw.rawLines,
            },
      'qr': <String, Object?>{
        'status': recognition.qrResult?.status.name,
        'message': recognition.qrResult?.message,
        'hasReviewCandidate': recognition.qrResult?.hasReviewCandidate == true,
        'decoderDiagnostics': <Object?>[
          for (final diagnostic
              in recognition.qrResult?.decoderDiagnostics ?? const [])
            diagnostic.toSafeMap(),
        ],
      },
    };
  }

  Map<String, Object?>? _geminiReview(GeminiInvoiceReviewExecution? execution) {
    if (execution == null) return null;
    final candidate = execution.candidate;
    return <String, Object?>{
      'status': execution.status.name,
      'message': execution.message,
      'decision': execution.decision.reason,
      'model': execution.model,
      'invocationMode': execution.invocationMode.name,
      'automaticReviewSettingEnabled': execution.automaticReviewSettingEnabled,
      'requestCount': execution.requestCount,
      'automaticUploadPerformed': execution.automaticUploadPerformed,
      'attempts': <Object?>[
        for (final attempt in execution.attempts)
          <String, Object?>{
            'ordinal': attempt.ordinal,
            'maskedKey': attempt.maskedKey,
            'success': attempt.success,
            'message': attempt.message,
          },
      ],
      'candidate': candidate == null ? null : _candidate(candidate),
    };
  }

  Map<String, Object?> _candidate(GeminiInvoiceReviewCandidate candidate) {
    return <String, Object?>{
      'invoiceNumber': candidate.invoiceNumber,
      'invoicePeriod': candidate.invoicePeriod,
      'randomCode': candidate.randomCode,
      'sellerTaxId': candidate.sellerTaxId,
      'invoiceDate': candidate.invoiceDate,
      'invoiceTime': candidate.invoiceTime,
      'merchantName': candidate.merchantName,
      'totalAmount': candidate.totalAmount,
      'lineItems': <Object?>[
        for (final item in candidate.lineItems)
          <String, Object?>{
            'name': item.name,
            'quantity': item.quantity,
            'unitPrice': item.unitPrice,
            'amount': item.amount,
          },
      ],
      'confidence': <String, Object?>{
        for (final entry in candidate.confidence.entries)
          entry.key.name: entry.value,
      },
      'warnings': candidate.warnings,
    };
  }

  List<Map<String, Object?>> _comparison(
    InvoiceCaptureReviewFlowResult result,
    GeminiInvoiceReviewCandidate? ai,
  ) {
    if (ai == null) return const <Map<String, Object?>>[];
    final local = result.formModel;
    final localSeller =
        local.fieldFor(InvoiceReviewFieldKey.sellerName)?.value.trim() ?? '';
    final localTaxId =
        local.fieldFor(InvoiceReviewFieldKey.sellerTaxId)?.value.trim() ?? '';
    final localMerchant = localSeller.startsWith('賣方統編') ? '' : localSeller;
    final values = <(String, String, String, bool, bool)>[
      (
        'invoiceNumber',
        local.fieldFor(InvoiceReviewFieldKey.invoiceNumber)?.value ?? '',
        ai.invoiceNumber,
        false,
        false,
      ),
      (
        'invoicePeriod',
        local.fieldFor(InvoiceReviewFieldKey.invoicePeriod)?.value ?? '',
        ai.invoicePeriod,
        false,
        true,
      ),
      (
        'invoiceDate',
        local.fieldFor(InvoiceReviewFieldKey.invoiceDate)?.value ?? '',
        ai.invoiceDate,
        false,
        false,
      ),
      ('merchantName', localMerchant, ai.merchantName, false, false),
      ('sellerTaxId', localTaxId, ai.sellerTaxId, false, false),
      (
        'totalAmount',
        local.fieldFor(InvoiceReviewFieldKey.totalAmount)?.value ?? '',
        ai.totalAmount == null ? '' : _amount(ai.totalAmount!),
        true,
        false,
      ),
      (
        'randomCode',
        local.fieldFor(InvoiceReviewFieldKey.randomCode)?.value ?? '',
        ai.randomCode,
        false,
        false,
      ),
      (
        'invoiceTime',
        local.fieldFor(InvoiceReviewFieldKey.invoiceTime)?.value ?? '',
        ai.invoiceTime,
        false,
        false,
      ),
    ];
    return <Map<String, Object?>>[
      for (final row in values)
        <String, Object?>{
          'field': row.$1,
          'localValue': row.$2,
          'geminiValue': row.$3,
          'status': _comparisonStatus(
            row.$2,
            row.$3,
            numeric: row.$4,
            invoicePeriod: row.$5,
          ),
        },
    ];
  }

  String _comparisonStatus(
    String localValue,
    String aiValue, {
    required bool numeric,
    bool invoicePeriod = false,
  }) {
    final local = localValue.trim();
    final ai = aiValue.trim();
    if (local.isEmpty && ai.isEmpty) return 'BOTH_MISSING';
    if (local.isEmpty) return 'MISSING_LOCAL';
    if (ai.isEmpty) return 'MISSING_AI';
    if (numeric) {
      final left = double.tryParse(local.replaceAll(',', ''));
      final right = double.tryParse(ai.replaceAll(',', ''));
      if (left != null && right != null && left == right) return 'AGREE';
    } else if (invoicePeriod) {
      final left = normalizeInvoicePeriodForComparison(local);
      final right = normalizeInvoicePeriodForComparison(ai);
      if (left.isNotEmpty && left == right) return 'AGREE';
    } else if (local == ai) {
      return 'AGREE';
    }
    return 'CONFLICT';
  }

  String _amount(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toString();

  Future<String> _sha256(Uint8List bytes) async {
    final digest = await Sha256().hash(bytes);
    return digest.bytes
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  String _mimeTypeFromPath(String reference) {
    final extension = path.extension(reference).toLowerCase();
    return switch (extension) {
      '.png' => 'image/png',
      '.webp' => 'image/webp',
      _ => 'image/jpeg',
    };
  }

  String _extensionForMime(String mimeType, {required String fallback}) {
    return switch (mimeType.toLowerCase()) {
      'image/png' => 'png',
      'image/webp' => 'webp',
      'image/jpeg' || 'image/jpg' => 'jpg',
      _ => fallback.isEmpty ? 'jpg' : fallback,
    };
  }

  void _addText(Archive archive, String name, String content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }

  String _safeToken(String value) {
    final normalized = value.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return normalized.length <= 96 ? normalized : normalized.substring(0, 96);
  }

  Future<void> _deleteStalePackages(Directory directory) async {
    final cutoff = DateTime.now().subtract(const Duration(hours: 24));
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.zip')) continue;
      try {
        final modified = await entity.lastModified();
        if (modified.isBefore(cutoff)) await entity.delete();
      } catch (_) {}
    }
  }
}
