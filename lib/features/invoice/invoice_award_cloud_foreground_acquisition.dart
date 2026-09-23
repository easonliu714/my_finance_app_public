import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'invoice_award_cloud_artifact_downloader.dart';
import 'invoice_award_cloud_index_lkg_repository.dart';
import 'invoice_award_cloud_pdf_index.dart';
import 'invoice_award_cloud_publication_parser.dart';

enum CloudAwardForegroundStage {
  publication,
  downloading,
  extracting,
  promoting,
  reused,
  completed,
  failed,
}

class CloudAwardForegroundProgress {
  const CloudAwardForegroundProgress({
    required this.stage,
    this.tierCode,
    this.downloadedBytes,
    this.declaredBytes,
    this.bytesPerSecond,
    this.pageNumber,
    this.pageCount,
    this.rowCount,
    this.message,
  });

  final CloudAwardForegroundStage stage;
  final String? tierCode;
  final int? downloadedBytes;
  final int? declaredBytes;
  final double? bytesPerSecond;
  final int? pageNumber;
  final int? pageCount;
  final int? rowCount;
  final String? message;
}

typedef CloudAwardForegroundProgressCallback = void Function(
  CloudAwardForegroundProgress progress,
);

enum CloudAwardTierRefreshStatus {
  reused,
  promoted,
  failed,
}

class CloudAwardTierRefreshResult {
  const CloudAwardTierRefreshResult({
    required this.tierCode,
    required this.status,
    required this.sourceUri,
    this.snapshot,
    this.failureCode,
  });

  final String tierCode;
  final CloudAwardTierRefreshStatus status;
  final Uri sourceUri;
  final CloudAwardValidatedIndexSnapshot? snapshot;
  final String? failureCode;

  bool get isReady =>
      status == CloudAwardTierRefreshStatus.reused ||
      status == CloudAwardTierRefreshStatus.promoted;
}

class CloudAwardForegroundRefreshResult {
  const CloudAwardForegroundRefreshResult({
    required this.periodId,
    required this.tiers,
    this.publicationFailureCode,
  });

  final String periodId;
  final List<CloudAwardTierRefreshResult> tiers;
  final String? publicationFailureCode;

  bool get isComplete =>
      publicationFailureCode == null &&
      tiers.length == 4 &&
      tiers.every((item) => item.isReady);
}

typedef CloudAwardTemporaryDirectoryProvider = Future<Directory> Function();

/// Foreground-only acquisition of credential-free public MOF cloud award data.
///
/// Network requests contain only the fixed public publication URL and the four
/// official PDF URLs discovered from it. No local invoice, transaction,
/// merchant, account, device identity, AppID or carrier credential is sent.
class MinistryOfFinanceCloudAwardForegroundAcquisitionService {
  MinistryOfFinanceCloudAwardForegroundAcquisitionService({
    required http.Client client,
    required CloudAwardIndexLkgRepository repository,
    CloudAwardPdfIndexBuilder? indexBuilder,
    MinistryOfFinanceCloudAwardPublicationHtmlParser? publicationParser,
    CloudAwardTemporaryDirectoryProvider? temporaryDirectoryProvider,
    DateTime Function()? clock,
    Uri? publicationUri,
    this.maxPublicationBytes = 1024 * 1024,
  })  : _client = client,
        _repository = repository,
        _indexBuilder = indexBuilder ??
            const CloudAwardPdfIndexBuilder(
              extractor: FlutterPdfTextCloudAwardExtractor(),
            ),
        _publicationParser = publicationParser ??
            const MinistryOfFinanceCloudAwardPublicationHtmlParser(),
        _temporaryDirectoryProvider =
            temporaryDirectoryProvider ?? getTemporaryDirectory,
        _clock = clock ?? DateTime.now,
        _publicationUri = publicationUri ?? currentPublicationUri;

  static final Uri currentPublicationUri =
      Uri.parse('https://invoice.etax.nat.gov.tw/cloudNowNumber.html');
  static final Uri previousPublicationUri =
      Uri.parse('https://invoice.etax.nat.gov.tw/cloudLastNumber.html');
  static final Uri officialPublicationUri = currentPublicationUri;

  final http.Client _client;
  final CloudAwardIndexLkgRepository _repository;
  final CloudAwardPdfIndexBuilder _indexBuilder;
  final MinistryOfFinanceCloudAwardPublicationHtmlParser _publicationParser;
  final CloudAwardTemporaryDirectoryProvider _temporaryDirectoryProvider;
  final DateTime Function() _clock;
  final Uri _publicationUri;
  final int maxPublicationBytes;

  Future<CloudAwardForegroundRefreshResult> refresh({
    required String periodId,
    CloudAwardForegroundProgressCallback? onProgress,
  }) async {
    onProgress?.call(
      const CloudAwardForegroundProgress(
        stage: CloudAwardForegroundStage.publication,
        message: '正在取得財政部雲端專屬獎公告…',
      ),
    );

    OfficialCloudAwardPublicationReferenceIndex publication;
    try {
      final html = await _fetchPublicationHtml();
      publication = _publicationParser.parse(
        sourceUri: _publicationUri,
        html: html,
        expectedPeriodId: periodId,
        fetchedAt: _clock().toUtc(),
      );
    } catch (error) {
      final code = _failureCode(error);
      onProgress?.call(
        CloudAwardForegroundProgress(
          stage: CloudAwardForegroundStage.failed,
          message: code,
        ),
      );
      return CloudAwardForegroundRefreshResult(
        periodId: periodId,
        tiers: const <CloudAwardTierRefreshResult>[],
        publicationFailureCode: code,
      );
    }

    final tempRoot = await _temporaryDirectoryProvider();
    final workRoot = Directory(
      '${tempRoot.path}${Platform.pathSeparator}invoice_award_cloud_refresh',
    );
    await workRoot.create(recursive: true);

    final results = <CloudAwardTierRefreshResult>[];
    for (final reference in publication.artifacts) {
      final reusable = await _reusableSnapshot(reference);
      if (reusable != null) {
        results.add(
          CloudAwardTierRefreshResult(
            tierCode: reference.tierCode,
            status: CloudAwardTierRefreshStatus.reused,
            sourceUri: reference.sourceUri,
            snapshot: reusable,
          ),
        );
        onProgress?.call(
          CloudAwardForegroundProgress(
            stage: CloudAwardForegroundStage.reused,
            tierCode: reference.tierCode,
            rowCount: reusable.manifest.rowCount,
            message: '已使用本機驗證資料',
          ),
        );
        continue;
      }

      final safeTier = reference.tierCode.replaceAll(RegExp(r'[^a-z0-9-]'), '_');
      final nonce = DateTime.now().microsecondsSinceEpoch;
      final pdfTemp = File(
        '${workRoot.path}${Platform.pathSeparator}'
        '$safeTier-$nonce.pdf.partial',
      );
      final indexTemp = File(
        '${workRoot.path}${Platform.pathSeparator}'
        '$safeTier-$nonce.index.candidate',
      );

      try {
        final downloader = MinistryOfFinanceCloudAwardArtifactDownloader(
          client: _client,
        );
        final artifact = await downloader.download(
          reference: reference,
          destinationTempFile: pdfTemp,
          onProgress: (progress) {
            onProgress?.call(
              CloudAwardForegroundProgress(
                stage: CloudAwardForegroundStage.downloading,
                tierCode: reference.tierCode,
                downloadedBytes: progress.downloadedBytes,
                declaredBytes: progress.declaredBytes,
                bytesPerSecond: progress.bytesPerSecond,
              ),
            );
          },
        );

        final build = await _indexBuilder.buildCandidate(
          artifact: artifact,
          candidateIndexFile: indexTemp,
          builtAt: _clock().toUtc(),
          onProgress: (pageNumber, pageCount, rowCount) {
            onProgress?.call(
              CloudAwardForegroundProgress(
                stage: CloudAwardForegroundStage.extracting,
                tierCode: reference.tierCode,
                pageNumber: pageNumber,
                pageCount: pageCount,
                rowCount: rowCount,
              ),
            );
          },
        );

        onProgress?.call(
          CloudAwardForegroundProgress(
            stage: CloudAwardForegroundStage.promoting,
            tierCode: reference.tierCode,
            rowCount: build.manifest.rowCount,
          ),
        );
        final promotion = await _repository.promoteValidated(build: build);
        results.add(
          CloudAwardTierRefreshResult(
            tierCode: reference.tierCode,
            status: promotion.status == CloudAwardIndexPromotionStatus.promoted
                ? CloudAwardTierRefreshStatus.promoted
                : CloudAwardTierRefreshStatus.reused,
            sourceUri: reference.sourceUri,
            snapshot: promotion.snapshot,
          ),
        );
      } catch (error) {
        final code = _failureCode(error);
        results.add(
          CloudAwardTierRefreshResult(
            tierCode: reference.tierCode,
            status: CloudAwardTierRefreshStatus.failed,
            sourceUri: reference.sourceUri,
            failureCode: code,
          ),
        );
        onProgress?.call(
          CloudAwardForegroundProgress(
            stage: CloudAwardForegroundStage.failed,
            tierCode: reference.tierCode,
            message: code,
          ),
        );
      } finally {
        await _deleteIfExists(pdfTemp);
        await _deleteIfExists(indexTemp);
      }
    }

    final result = CloudAwardForegroundRefreshResult(
      periodId: periodId,
      tiers: List<CloudAwardTierRefreshResult>.unmodifiable(results),
    );
    onProgress?.call(
      CloudAwardForegroundProgress(
        stage: result.isComplete
            ? CloudAwardForegroundStage.completed
            : CloudAwardForegroundStage.failed,
        message: result.isComplete
            ? '雲端專屬獎官方資料已驗證完成'
            : '雲端專屬獎資料不完整；已保留既有 LKG',
      ),
    );
    return result;
  }

  Future<String> _fetchPublicationHtml() async {
    final request = http.Request('GET', _publicationUri);
    request.headers[HttpHeaders.acceptHeader] =
        'text/html,application/xhtml+xml';
    final response = await _client.send(request);
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        'CLOUD_AWARD_PUBLICATION_HTTP_STATUS_${response.statusCode}',
        uri: _publicationUri,
      );
    }

    final contentType =
        response.headers[HttpHeaders.contentTypeHeader]?.toLowerCase();
    if (contentType != null &&
        (!contentType.contains('text/html') ||
            (contentType.contains('charset=') &&
                !contentType.contains('utf-8')))) {
      throw StateError('CLOUD_AWARD_PUBLICATION_CONTENT_TYPE_INVALID');
    }

    final declared = response.contentLength;
    if (declared != null &&
        (declared <= 0 || declared > maxPublicationBytes)) {
      throw StateError('CLOUD_AWARD_PUBLICATION_SIZE_INVALID');
    }

    final builder = BytesBuilder(copy: false);
    var total = 0;
    await for (final chunk in response.stream) {
      total += chunk.length;
      if (total > maxPublicationBytes) {
        throw StateError('CLOUD_AWARD_PUBLICATION_SIZE_EXCEEDED');
      }
      builder.add(chunk);
    }
    if (total <= 0) {
      throw StateError('CLOUD_AWARD_PUBLICATION_EMPTY');
    }

    return utf8.decode(builder.takeBytes(), allowMalformed: false);
  }

  Future<CloudAwardValidatedIndexSnapshot?> _reusableSnapshot(
    OfficialCloudAwardArtifactReference reference,
  ) async {
    final snapshot = await _repository.readLatest(
      periodId: reference.periodId,
      tierCode: reference.tierCode,
    );
    if (snapshot == null) return null;
    if (snapshot.manifest.officialSourceUri != reference.sourceUri) return null;
    if (snapshot.manifest.extractorVersion !=
        _indexBuilder.extractor.extractorVersion) {
      return null;
    }
    return snapshot;
  }

  static String _failureCode(Object error) {
    if (error is HttpException) return error.message;
    if (error is FormatException) return 'CLOUD_AWARD_FORMAT_INVALID';
    if (error is StateError) return error.message;
    if (error is http.ClientException) return 'CLOUD_AWARD_NETWORK_FAILURE';
    return 'CLOUD_AWARD_REFRESH_FAILURE';
  }

  static Future<void> _deleteIfExists(File file) async {
    if (await file.exists()) await file.delete();
  }
}