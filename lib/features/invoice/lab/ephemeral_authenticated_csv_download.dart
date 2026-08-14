import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'official_cloud_invoice_csv_adapter.dart';
import 'official_portal_origin_policy.dart';
import 'private_cloud_invoice_csv_import_service.dart';

/// Metadata emitted by the native WebView download-start callback.
///
/// The Cookie header is intentionally process-memory only. This model must
/// never be serialized, logged, included in diagnostics, or persisted.
class EphemeralCsvDownloadRequest {
  const EphemeralCsvDownloadRequest({
    required this.url,
    required this.userAgent,
    required this.mimeType,
    required this.contentDisposition,
    required this.suggestedFilename,
    required this.contentLength,
    required this.cookieHeader,
  });

  final Uri url;
  final String? userAgent;
  final String? mimeType;
  final String? contentDisposition;
  final String? suggestedFilename;
  final int contentLength;
  final String cookieHeader;
}

class EphemeralCsvDownloadException implements Exception {
  const EphemeralCsvDownloadException(this.code);

  final String code;

  @override
  String toString() => code;
}

typedef EphemeralTempDirectoryProvider = Future<Directory> Function();

/// Performs one user-triggered authenticated GET into private cache, validates
/// it as an official CSV, hands the parsed preview to the existing adapter, and
/// deletes the raw bytes on every completion path.
class EphemeralAuthenticatedCsvDownloadService {
  EphemeralAuthenticatedCsvDownloadService({
    OfficialCloudInvoiceCsvAdapter? adapter,
    EphemeralTempDirectoryProvider? tempDirectoryProvider,
    Set<String>? allowedHosts,
    this.maxBytes = 10 * 1024 * 1024,
    this.maxRedirects = 5,
    this.timeout = const Duration(seconds: 30),
  })  : _adapter = adapter ?? const OfficialCloudInvoiceCsvAdapter(),
        _tempDirectoryProvider =
            tempDirectoryProvider ?? getTemporaryDirectory,
        _explicitAllowedHosts = allowedHosts == null
            ? null
            : Set<String>.unmodifiable(
                allowedHosts.map((host) => host.toLowerCase()),
              );

  static const String cacheDirectoryName = 'cloud_invoice_ephemeral';
  static const String filePrefix = 'cloud_invoice_ephemeral_';

  final OfficialCloudInvoiceCsvAdapter _adapter;
  final EphemeralTempDirectoryProvider _tempDirectoryProvider;
  final Set<String>? _explicitAllowedHosts;
  final int maxBytes;
  final int maxRedirects;
  final Duration timeout;

  HttpClient? _activeClient;
  File? _activeFile;
  bool _cancelled = false;
  bool _running = false;

  Future<void> cleanupStaleFiles() async {
    final directory = await _cacheDirectory();
    if (!await directory.exists()) return;
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is File && p.basename(entity.path).startsWith(filePrefix)) {
        await _deleteQuietly(entity);
      }
    }
  }

  Future<PrivateCloudInvoiceCsvSource> downloadAndParse(
    EphemeralCsvDownloadRequest request,
  ) async {
    if (_running) {
      throw const EphemeralCsvDownloadException('CSV_DOWNLOAD_ALREADY_RUNNING');
    }

    // Reject metadata before entering the running state. A rejected event must
    // not poison the one-shot service and prevent the user's next valid tap.
    _validateRequestMetadata(request);
    _running = true;
    _cancelled = false;

    final client = HttpClient()..connectionTimeout = timeout;
    _activeClient = client;
    File? temporaryFile;
    try {
      final directory = await _cacheDirectory();
      await directory.create(recursive: true);
      temporaryFile = File(
        p.join(
          directory.path,
          '$filePrefix${DateTime.now().microsecondsSinceEpoch}.part',
        ),
      );
      _activeFile = temporaryFile;

      final response = await _openFollowingApprovedRedirects(
        client: client,
        request: request,
      );
      _validateResponseMetadata(response, request);

      final sink = temporaryFile.openWrite(mode: FileMode.writeOnly);
      var received = 0;
      try {
        await for (final chunk in response.timeout(timeout)) {
          _throwIfCancelled();
          received += chunk.length;
          if (received > maxBytes) {
            throw const EphemeralCsvDownloadException(
              'CSV_DOWNLOAD_SIZE_LIMIT_EXCEEDED',
            );
          }
          sink.add(chunk);
        }
      } finally {
        await sink.close();
      }

      _throwIfCancelled();
      final bytes = await temporaryFile.readAsBytes();
      final csvText = utf8.decode(bytes, allowMalformed: false);
      final preview = _adapter.createPreview(csvText);
      final invalidHeader = preview.fileIssues.any(
        (issue) =>
            issue.code == OfficialCloudInvoiceCsvIssueCode.invalidHeader,
      );
      if (invalidHeader) {
        throw const EphemeralCsvDownloadException('CSV_SIGNATURE_INVALID');
      }

      return PrivateCloudInvoiceCsvSource(
        fileName: _safeFileName(request),
        preview: preview,
      );
    } on EphemeralCsvDownloadException {
      rethrow;
    } on TimeoutException {
      throw const EphemeralCsvDownloadException('CSV_DOWNLOAD_TIMEOUT');
    } on FormatException {
      throw const EphemeralCsvDownloadException('CSV_UTF8_INVALID');
    } on HandshakeException {
      throw const EphemeralCsvDownloadException('CSV_TLS_FAILED');
    } on SocketException {
      if (_cancelled) {
        throw const EphemeralCsvDownloadException('CSV_DOWNLOAD_CANCELLED');
      }
      throw const EphemeralCsvDownloadException('CSV_NETWORK_FAILED');
    } catch (_) {
      if (_cancelled) {
        throw const EphemeralCsvDownloadException('CSV_DOWNLOAD_CANCELLED');
      }
      throw const EphemeralCsvDownloadException('CSV_DOWNLOAD_FAILED');
    } finally {
      client.close(force: true);
      if (temporaryFile != null) await _deleteQuietly(temporaryFile);
      _activeClient = null;
      _activeFile = null;
      _running = false;
    }
  }

  Future<void> cancel() async {
    _cancelled = true;
    _activeClient?.close(force: true);
    final file = _activeFile;
    if (file != null) await _deleteQuietly(file);
  }

  Future<HttpClientResponse> _openFollowingApprovedRedirects({
    required HttpClient client,
    required EphemeralCsvDownloadRequest request,
  }) async {
    var current = request.url;
    for (var redirectCount = 0;
        redirectCount <= maxRedirects;
        redirectCount += 1) {
      _throwIfCancelled();
      _validateApprovedUri(current);
      final outbound = await client.getUrl(current).timeout(timeout);
      outbound.followRedirects = false;
      outbound.headers.set(HttpHeaders.acceptHeader, 'text/csv,*/*;q=0.1');
      final userAgent = request.userAgent?.trim();
      if (userAgent != null && userAgent.isNotEmpty) {
        outbound.headers.set(HttpHeaders.userAgentHeader, userAgent);
      }
      if (request.cookieHeader.isNotEmpty) {
        outbound.headers.set(HttpHeaders.cookieHeader, request.cookieHeader);
      }
      final response = await outbound.close().timeout(timeout);
      if (!_isRedirect(response.statusCode)) {
        if (response.statusCode != HttpStatus.ok) {
          await response.drain<void>();
          throw const EphemeralCsvDownloadException(
            'CSV_DOWNLOAD_HTTP_STATUS_REJECTED',
          );
        }
        return response;
      }

      final location = response.headers.value(HttpHeaders.locationHeader);
      await response.drain<void>();
      if (location == null || location.isEmpty) {
        throw const EphemeralCsvDownloadException(
          'CSV_REDIRECT_LOCATION_MISSING',
        );
      }
      if (redirectCount == maxRedirects) {
        throw const EphemeralCsvDownloadException(
          'CSV_REDIRECT_LIMIT_EXCEEDED',
        );
      }
      current = current.resolve(location);
      _validateApprovedUri(current);
    }
    throw const EphemeralCsvDownloadException('CSV_REDIRECT_LIMIT_EXCEEDED');
  }

  void _validateRequestMetadata(EphemeralCsvDownloadRequest request) {
    _validateApprovedUri(request.url);
    if (request.contentLength > maxBytes) {
      throw const EphemeralCsvDownloadException(
        'CSV_DOWNLOAD_SIZE_LIMIT_EXCEEDED',
      );
    }
    if (!_hasCsvEvidence(
      uri: request.url,
      mimeType: request.mimeType,
      disposition: request.contentDisposition,
      suggestedFilename: request.suggestedFilename,
    )) {
      throw const EphemeralCsvDownloadException('CSV_METADATA_REJECTED');
    }
  }

  void _validateResponseMetadata(
    HttpClientResponse response,
    EphemeralCsvDownloadRequest request,
  ) {
    final responseLength = response.contentLength;
    if (responseLength > maxBytes) {
      throw const EphemeralCsvDownloadException(
        'CSV_DOWNLOAD_SIZE_LIMIT_EXCEEDED',
      );
    }
    final mimeType = response.headers.contentType?.mimeType;
    final disposition = response.headers.value('content-disposition');
    if (!_hasCsvEvidence(
      uri: request.url,
      mimeType: mimeType,
      disposition: disposition,
      suggestedFilename: request.suggestedFilename,
    )) {
      throw const EphemeralCsvDownloadException('CSV_RESPONSE_REJECTED');
    }
  }

  void _validateApprovedUri(Uri uri) {
    if (uri.scheme.toLowerCase() != 'https') {
      throw const EphemeralCsvDownloadException('CSV_HTTPS_REQUIRED');
    }
    if (!_isAllowedHost(uri.host)) {
      throw const EphemeralCsvDownloadException('CSV_HOST_NOT_APPROVED');
    }
    if (uri.userInfo.isNotEmpty) {
      throw const EphemeralCsvDownloadException('CSV_URL_USERINFO_REJECTED');
    }
  }

  bool _isAllowedHost(String host) {
    final normalized = host.toLowerCase();
    final explicit = _explicitAllowedHosts;
    if (explicit != null) return explicit.contains(normalized);
    return isApprovedOfficialPortalHost(normalized);
  }

  bool _hasCsvEvidence({
    required Uri uri,
    required String? mimeType,
    required String? disposition,
    required String? suggestedFilename,
  }) {
    final normalizedMime = mimeType?.split(';').first.trim().toLowerCase();
    final acceptedMime = normalizedMime == 'text/csv' ||
        normalizedMime == 'application/csv' ||
        normalizedMime == 'application/vnd.ms-excel';
    final csvName = uri.path.toLowerCase().endsWith('.csv') ||
        (suggestedFilename?.toLowerCase().endsWith('.csv') ?? false) ||
        (disposition?.toLowerCase().contains('.csv') ?? false);
    final genericMime = normalizedMime == null ||
        normalizedMime.isEmpty ||
        normalizedMime == 'application/octet-stream';
    return acceptedMime || (genericMime && csvName);
  }

  String _safeFileName(EphemeralCsvDownloadRequest request) {
    final candidate = request.suggestedFilename?.trim();
    if (candidate == null || candidate.isEmpty) {
      return 'official_cloud_invoice.csv';
    }
    final base =
        p.basename(candidate).replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return base.toLowerCase().endsWith('.csv')
        ? base
        : 'official_cloud_invoice.csv';
  }

  bool _isRedirect(int statusCode) {
    return statusCode == HttpStatus.movedPermanently ||
        statusCode == HttpStatus.found ||
        statusCode == HttpStatus.seeOther ||
        statusCode == HttpStatus.temporaryRedirect ||
        statusCode == HttpStatus.permanentRedirect;
  }

  void _throwIfCancelled() {
    if (_cancelled) {
      throw const EphemeralCsvDownloadException('CSV_DOWNLOAD_CANCELLED');
    }
  }

  Future<Directory> _cacheDirectory() async {
    final root = await _tempDirectoryProvider();
    return Directory(p.join(root.path, cacheDirectoryName));
  }

  Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {
      // The caller still clears the WebView session. No path or file data is
      // emitted because diagnostics must not reveal downloaded invoice data.
    }
  }
}
