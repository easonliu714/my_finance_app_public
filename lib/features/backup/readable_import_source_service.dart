import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:sqflite/sqflite.dart';

import 'readable_import_service.dart';

class ReadableImportSourceCandidate {
  const ReadableImportSourceCandidate({
    required this.filePath,
    required this.fileName,
    required this.format,
    required this.fileSizeBytes,
    required this.isValid,
    required this.message,
    this.dryRunResult,
  });

  final String filePath;
  final String fileName;
  final ReadableImportSourceFormat format;
  final int fileSizeBytes;
  final bool isValid;
  final String message;
  final ReadableImportDryRunResult? dryRunResult;
}

enum ReadableImportSourceFormat { json, csv, unsupported }

class ReadableImportSourceService {
  const ReadableImportSourceService({this.importService = const ReadableImportService()});

  final ReadableImportService importService;

  Future<List<ReadableImportSourceCandidate>> scanSourceDirectory(Directory sourceDirectory, {DatabaseExecutor? currentDb}) async {
    if (!sourceDirectory.existsSync()) return const <ReadableImportSourceCandidate>[];
    final files = sourceDirectory
        .listSync()
        .whereType<File>()
        .where((file) => _formatForFileSync(file) != ReadableImportSourceFormat.unsupported)
        .toList()
      ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    final candidates = <ReadableImportSourceCandidate>[];
    for (final file in files) {
      candidates.add(await previewFile(file, currentDb: currentDb));
    }
    return candidates;
  }

  Future<ReadableImportSourceCandidate> previewBytes(
    Uint8List bytes, {
    required String sourceUri,
    required String fileName,
    DatabaseExecutor? currentDb,
  }) {
    return previewText(
      utf8.decode(bytes),
      sourceUri: sourceUri,
      fileName: fileName,
      fileSizeBytes: bytes.length,
      currentDb: currentDb,
    );
  }

  Future<ReadableImportSourceCandidate> previewText(
    String text, {
    required String sourceUri,
    required String fileName,
    required int fileSizeBytes,
    DatabaseExecutor? currentDb,
  }) async {
    final extensionFormat = _formatForName(fileName);
    final format = extensionFormat == ReadableImportSourceFormat.unsupported ? _formatForContent(text, fileName: fileName) : extensionFormat;
    if (format == ReadableImportSourceFormat.unsupported) {
      return ReadableImportSourceCandidate(
        filePath: sourceUri,
        fileName: fileName,
        format: format,
        fileSizeBytes: fileSizeBytes,
        isValid: false,
        message: '不支援的 readable import 格式。',
      );
    }
    if (currentDb == null) {
      return ReadableImportSourceCandidate(
        filePath: sourceUri,
        fileName: fileName,
        format: format,
        fileSizeBytes: fileSizeBytes,
        isValid: true,
        message: extensionFormat == ReadableImportSourceFormat.unsupported ? '已從檔案內容推斷 readable ${format.name} 候選檔；尚未執行 dry-run。' : '已偵測候選檔；尚未執行 dry-run。',
      );
    }
    try {
      final result = format == ReadableImportSourceFormat.json ? await importService.dryRunTransactionsJson(currentDb, text) : await importService.dryRunTransactionsCsv(currentDb, text);
      return ReadableImportSourceCandidate(
        filePath: sourceUri,
        fileName: fileName,
        format: format,
        fileSizeBytes: fileSizeBytes,
        isValid: true,
        message: extensionFormat == ReadableImportSourceFormat.unsupported ? '已從檔案內容推斷 readable ${format.name}，dry-run preview 完成；尚未寫入資料。' : 'dry-run preview 完成；尚未寫入資料。',
        dryRunResult: result,
      );
    } catch (error) {
      return ReadableImportSourceCandidate(
        filePath: sourceUri,
        fileName: fileName,
        format: format,
        fileSizeBytes: fileSizeBytes,
        isValid: false,
        message: '無法建立 dry-run preview：$error',
      );
    }
  }

  Future<ReadableImportSourceCandidate> previewFile(File file, {DatabaseExecutor? currentDb}) async {
    final fileName = file.uri.pathSegments.isEmpty ? file.path : file.uri.pathSegments.last;
    final fileSize = file.existsSync() ? file.lengthSync() : 0;
    String? text;
    final extensionFormat = _formatForName(file.path);
    var format = extensionFormat;
    if (format == ReadableImportSourceFormat.unsupported && file.existsSync()) {
      text = await file.readAsString();
      format = _formatForContent(text, fileName: fileName);
    }
    if (format == ReadableImportSourceFormat.unsupported) {
      return ReadableImportSourceCandidate(
        filePath: file.path,
        fileName: fileName,
        format: format,
        fileSizeBytes: fileSize,
        isValid: false,
        message: '不支援的 readable import 格式。',
      );
    }
    if (currentDb == null) {
      return ReadableImportSourceCandidate(
        filePath: file.path,
        fileName: fileName,
        format: format,
        fileSizeBytes: fileSize,
        isValid: true,
        message: extensionFormat == ReadableImportSourceFormat.unsupported ? '已從檔案內容推斷 readable ${format.name} 候選檔；尚未執行 dry-run。' : '已偵測候選檔；尚未執行 dry-run。',
      );
    }
    try {
      text ??= await file.readAsString();
      final result = format == ReadableImportSourceFormat.json ? await importService.dryRunTransactionsJson(currentDb, text) : await importService.dryRunTransactionsCsv(currentDb, text);
      return ReadableImportSourceCandidate(
        filePath: file.path,
        fileName: fileName,
        format: format,
        fileSizeBytes: fileSize,
        isValid: true,
        message: extensionFormat == ReadableImportSourceFormat.unsupported ? '已從檔案內容推斷 readable ${format.name}，dry-run preview 完成；尚未寫入資料。' : 'dry-run preview 完成；尚未寫入資料。',
        dryRunResult: result,
      );
    } catch (error) {
      return ReadableImportSourceCandidate(
        filePath: file.path,
        fileName: fileName,
        format: format,
        fileSizeBytes: fileSize,
        isValid: false,
        message: '無法建立 dry-run preview：$error',
      );
    }
  }

  ReadableImportSourceFormat _formatForFileSync(File file) {
    final pathFormat = _formatForName(file.path);
    if (pathFormat != ReadableImportSourceFormat.unsupported) return pathFormat;
    if (!file.existsSync()) return ReadableImportSourceFormat.unsupported;
    try {
      return _formatForContent(file.readAsStringSync(), fileName: file.uri.pathSegments.isEmpty ? file.path : file.uri.pathSegments.last);
    } catch (_) {
      return ReadableImportSourceFormat.unsupported;
    }
  }

  ReadableImportSourceFormat _formatForName(String pathOrName) {
    final lower = pathOrName.toLowerCase();
    if (lower.endsWith('.json')) return ReadableImportSourceFormat.json;
    if (lower.endsWith('.csv')) return ReadableImportSourceFormat.csv;
    if (lower.contains('readable') && lower.contains('json')) return ReadableImportSourceFormat.json;
    if (lower.contains('readable') && lower.contains('csv')) return ReadableImportSourceFormat.csv;
    return ReadableImportSourceFormat.unsupported;
  }

  ReadableImportSourceFormat _formatForContent(String text, {String fileName = ''}) {
    final nameFormat = _formatForName(fileName);
    if (nameFormat != ReadableImportSourceFormat.unsupported) return nameFormat;
    final trimmed = text.trimLeft();
    if (trimmed.startsWith('{')) {
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is Map && decoded['data'] is List) return ReadableImportSourceFormat.json;
      } catch (_) {
        return ReadableImportSourceFormat.unsupported;
      }
    }
    final firstLine = trimmed.split(RegExp(r'\r?\n')).first.toLowerCase();
    if (firstLine.contains('id') && firstLine.contains('type') && firstLine.contains('occurred_at') && firstLine.contains('amount')) {
      return ReadableImportSourceFormat.csv;
    }
    return ReadableImportSourceFormat.unsupported;
  }
}
