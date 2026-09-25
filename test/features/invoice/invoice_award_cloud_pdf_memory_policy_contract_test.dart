import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const packageRoot = 'packages/flutter_pdf_text';
  const pluginSourcePath =
      '$packageRoot/android/src/main/kotlin/me/movenext/flutter_pdf_text/PdfTextPlugin.kt';

  test('vendored flutter_pdf_text uses temp-file-backed PDFBox policy', () {
    final packagePubspec =
        File('$packageRoot/pubspec.yaml').readAsStringSync();
    final license = File('$packageRoot/LICENSE').readAsStringSync();
    final pluginSource = File(pluginSourcePath).readAsStringSync();
    final appPubspec = File('pubspec.yaml').readAsStringSync();
    final appExtractor = File(
      'lib/features/invoice/invoice_award_cloud_pdf_index.dart',
    ).readAsStringSync();
    final androidBuild = File(
      'packages/flutter_pdf_text/android/build.gradle',
    ).readAsStringSync();
    final candidateScope = File(
      'lib/features/invoice/invoice_award_cloud_candidate_scope.dart',
    ).readAsStringSync();

    expect(packagePubspec, contains('name: flutter_pdf_text'));
    expect(
      RegExp(r'^version:\s*0\.9\.0\s*$', multiLine: true)
          .hasMatch(packagePubspec),
      isTrue,
    );
    expect(license, contains('MIT License'));
    expect(license, contains('Copyright (c) 2020 Alessio Luciani'));
    expect(
      pluginSource,
      contains('import com.tom_roush.pdfbox.io.MemoryUsageSetting'),
    );
    expect(
      pluginSource,
      contains('private lateinit var applicationContext: Context'),
    );
    expect(pluginSource, contains('channel.setMethodCallHandler(this)'));
    expect(pluginSource, contains('MemoryUsageSetting.setupTempFileOnly()'));
    expect(
      pluginSource,
      contains('.setTempDir(applicationContext.cacheDir)'),
    );
    expect(
      pluginSource,
      contains('PDDocument.load(File(path), password, memoryUsageSetting)'),
    );
    expect(
      RegExp(
        r'PDDocument\.load\(\s*File\(path\)\s*,\s*password\s*\)',
      ).hasMatch(pluginSource),
      isFalse,
    );
    expect(RegExp(r'PDDocument\.load\(').allMatches(pluginSource).length, 1);
    expect(pluginSource, contains('ConcurrentHashMap<String, PDDocument>()'));
    expect(pluginSource, contains('"openDocSession"'));
    expect(pluginSource, contains('"getDocSessionPageText"'));
    expect(pluginSource, contains('"closeDocSession"'));
    expect(pluginSource, contains('openDocuments[sessionId] = doc'));
    expect(pluginSource, contains('openDocuments.remove(sessionId)'));
    expect(pluginSource, contains('diagnosticFileName'));
    expect(pluginSource, contains('"OPEN_BEGIN"'));
    expect(pluginSource, contains('"OPEN_OOM"'));
    expect(pluginSource, contains('"PAGE_BEGIN"'));
    expect(pluginSource, contains('"PAGE_OOM"'));
    expect(pluginSource, contains('"EXTRACTION_COMPLETE"'));
    expect(pluginSource, contains('catch (oom: OutOfMemoryError)'));
    expect(pluginSource, contains(r'"heap_used_bytes=$usedHeap"'));
    expect(pluginSource, contains('"getLastDiagnostic"'));
    expect(pluginSource, contains('PdfiumCore(applicationContext)'));
    expect(pluginSource, contains('"openPdfiumSession"'));
    expect(pluginSource, contains('"getPdfiumSessionPageText"'));
    expect(pluginSource, contains('"closePdfiumSession"'));
    expect(pluginSource, contains('"PDFIUM_OPEN_OK"'));
    expect(pluginSource, contains('"PDFIUM_PAGE_OK"'));
    expect(
      androidBuild,
      contains("implementation 'io.legere:pdfiumandroid:1.0.24'"),
    );
    expect(androidBuild, contains('minSdkVersion 23'));
    expect(
      candidateScope,
      contains('class PdfiumCloudAwardSortedPdfCandidateLookup'),
    );
    expect(candidateScope, contains("'openPdfiumSession'"));
    expect(candidateScope, contains('while (low <= high)'));
    expect(candidateScope, contains('candidateUniverseSha256'));
    expect(appExtractor, contains('if (Platform.isAndroid)'));
    expect(appExtractor, contains("'openDocSession'"));
    expect(appExtractor, contains("'getDocSessionPageText'"));
    expect(appExtractor, contains("'closeDocSession'"));
    expect(
      appExtractor,
      contains('flutter_pdf_text-0.9.0-android-chunk8-diagnostic-v3'),
    );
    expect(appExtractor, contains('androidChunkPageCount = 8'));
    expect(appExtractor, contains("'markExtractionComplete'"));
    expect(appExtractor, contains("'getLastDiagnostic'"));
    expect(appExtractor, contains('CloudAwardPdfExtractorStage.pageStarted'));
    expect(
      pluginSource,
      contains(
        'private fun initDoc(result: Result, path: String, password: String) {\n'
        '    getDoc(result, path, password)?.use { doc ->',
      ),
    );
    expect(
      pluginSource,
      contains(
        'private fun getDocPageText(result: Result, path: String, pageNumber: Int, password: String) {\n'
        '    getDoc(result, path, password)?.use { doc ->',
      ),
    );
    expect(
      pluginSource,
      contains(
        'private fun getDocText(result: Result, path: String, missingPagesNumbers: List<Int>, password: String) {\n'
        '    getDoc(result, path, password)?.use { doc ->',
      ),
    );
    expect(
      appPubspec,
      contains(
        '  flutter_pdf_text:\n'
        '    path: packages/flutter_pdf_text\n',
      ),
    );
  });
}
