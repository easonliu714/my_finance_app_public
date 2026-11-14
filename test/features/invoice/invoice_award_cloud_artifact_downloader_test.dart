import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:my_finance_app/features/invoice/invoice_award_cloud_artifact_downloader.dart';
import 'package:my_finance_app/features/invoice/invoice_award_cloud500_production_policy.dart';
import 'package:my_finance_app/features/invoice/invoice_award_cloud_publication_parser.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('cloud_award_download_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  OfficialCloudAwardArtifactReference reference({
    String host = 'invoice.etax.nat.gov.tw',
  }) =>
      OfficialCloudAwardArtifactReference(
        artifactId: '20260506_20260725124532_sorted_AI_E.pdf',
        sourceUri: Uri.parse(
          'https://$host/pdf/20260506_20260725124532_sorted_AI_E.pdf',
        ),
        periodId: '115-05-06',
        tierCode: 'cloud-800',
      );

  List<int> pdfBytes() => utf8.encode(
        '%PDF-1.7\n'
        '1 0 obj << /Type /Catalog >> endobj\n'
        'stream AD00166192 AD00169681 endstream\n'
        '%%EOF\n',
      );

  test('streams official PDF bytes and records exact SHA-256', () async {
    final payload = pdfBytes();
    final destination = File('${tempDir.path}/cloud.partial');
    final result = await MinistryOfFinanceCloudAwardArtifactDownloader(
      client: _StreamingClient(payload: payload),
    ).download(
      reference: reference(),
      destinationTempFile: destination,
    );

    expect(await result.file.readAsBytes(), payload);
    expect(result.sizeBytes, payload.length);
    expect(result.sha256, hasLength(64));
    expect(result.reference.tierCode, 'cloud-800');
  });

  test('Owner C direct cloud-500 source is release-blocked before network and file access', () async {
    final cloud500 = OfficialCloudAwardArtifactReference(
      artifactId: '20260506_20260725124620_sorted_AI_D.pdf',
      sourceUri: Uri.parse(
        'https://invoice.etax.nat.gov.tw/pdf/20260506_20260725124620_sorted_AI_D.pdf',
      ),
      periodId: '115-05-06',
      tierCode: 'cloud-500',
    );
    expect(cloud500.isApprovedOfficialSource, isTrue);
    // Pure negative/positive release policy: diagnostic-mode flags are never
    // accepted from the downloader caller to override the actual build.
    expect(
      Cloud500ProductionPolicy.blocksCloud500PersistenceForBuild(
        tierCode: cloud500.tierCode,
        isReleaseBuild: true,
      ),
      isTrue,
    );
    expect(
      Cloud500ProductionPolicy.blocksCloud500PersistenceForBuild(
        tierCode: cloud500.tierCode,
        isReleaseBuild: false,
      ),
      isFalse,
    );
    expect(
      Cloud500ProductionPolicy.blocksCloud500PersistenceForBuild(
        tierCode: reference().tierCode,
        isReleaseBuild: true,
      ),
      isFalse,
    );
    final client = _StreamingClient(payload: pdfBytes());
    final destination = File('${tempDir.path}/cloud500.partial');
    final downloader = MinistryOfFinanceCloudAwardArtifactDownloader(
      client: client,
    );
    if (kReleaseMode) {
      await expectLater(
        downloader.download(
          reference: cloud500,
          destinationTempFile: destination,
        ),
        throwsA(isA<StateError>().having(
          (error) => error.message,
          'message',
          Cloud500ProductionPolicy.deferredCode,
        )),
      );
      expect(client.requests, 0);
      expect(await destination.exists(), isFalse);
    } else {
      // Existing non-release G0 acquisition diagnostics remain possible;
      // this simulated stream is NOT genuine official PDF evidence.
      final result = await downloader.download(
        reference: cloud500,
        destinationTempFile: destination,
      );
      expect(client.requests, 1);
      expect(result.reference.tierCode, 'cloud-500');
      expect(result.sizeBytes, pdfBytes().length);
    }
  });

  test('rejects non-official host before network use', () async {
    final client = _StreamingClient(payload: pdfBytes());
    final destination = File('${tempDir.path}/cloud.partial');

    await expectLater(
      MinistryOfFinanceCloudAwardArtifactDownloader(client: client).download(
        reference: reference(host: 'example.com'),
        destinationTempFile: destination,
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'CLOUD_AWARD_ARTIFACT_SOURCE_NOT_ALLOWED',
        ),
      ),
    );

    expect(client.requests, 0);
    expect(await destination.exists(), isFalse);
  });

  test('rejects non-PDF bytes and removes partial file', () async {
    final payload = utf8.encode('NOT-PDF' * 20);
    final destination = File('${tempDir.path}/cloud.partial');

    await expectLater(
      MinistryOfFinanceCloudAwardArtifactDownloader(
        client: _StreamingClient(payload: payload),
      ).download(
        reference: reference(),
        destinationTempFile: destination,
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'CLOUD_AWARD_ARTIFACT_PDF_MAGIC_INVALID',
        ),
      ),
    );

    expect(await destination.exists(), isFalse);
  });

  test('rejects declared artifact larger than bounded policy', () async {
    final payload = pdfBytes();
    final destination = File('${tempDir.path}/cloud.partial');

    await expectLater(
      MinistryOfFinanceCloudAwardArtifactDownloader(
        client: _StreamingClient(
          payload: payload,
          declaredLength: 300 * 1024 * 1024,
        ),
      ).download(
        reference: reference(),
        destinationTempFile: destination,
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'CLOUD_AWARD_ARTIFACT_CONTENT_LENGTH_INVALID',
        ),
      ),
    );

    expect(await destination.exists(), isFalse);
  });

  test('rejects non-200 response without retaining bytes', () async {
    final destination = File('${tempDir.path}/cloud.partial');

    await expectLater(
      MinistryOfFinanceCloudAwardArtifactDownloader(
        client: _StreamingClient(
          payload: const <int>[],
          statusCode: HttpStatus.serviceUnavailable,
          declaredLength: 0,
        ),
      ).download(
        reference: reference(),
        destinationTempFile: destination,
      ),
      throwsA(isA<HttpException>()),
    );

    expect(await destination.exists(), isFalse);
  });
}

class _StreamingClient extends http.BaseClient {
  _StreamingClient({
    required this.payload,
    this.statusCode = HttpStatus.ok,
    int? declaredLength,
  }) : declaredLength = declaredLength ?? payload.length;

  final List<int> payload;
  final int statusCode;
  final int declaredLength;
  int requests = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests += 1;
    return http.StreamedResponse(
      Stream<List<int>>.value(payload),
      statusCode,
      headers: const <String, String>{'content-type': 'application/pdf'},
      contentLength: declaredLength,
      request: request,
    );
  }
}
