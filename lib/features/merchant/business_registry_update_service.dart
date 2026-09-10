import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'business_registry_bounded_downloader.dart';
import 'business_registry_distribution_manifest.dart';
import 'business_registry_repository.dart';
import 'business_registry_stream_validator.dart';
import 'business_registry_transactional_stream_installer.dart';

class BusinessRegistryUpdateConfiguration {
  const BusinessRegistryUpdateConfiguration._();

  static const String productionManifestUrl =
      'https://github.com/easonliu714/my_finance_app_public/'
      'releases/download/p4.20.3-registry/manifest.json';

  static const String manifestUrl = String.fromEnvironment(
    'BUSINESS_REGISTRY_MANIFEST_URL',
    defaultValue: productionManifestUrl,
  );

  static Uri? get manifestUri {
    final value = manifestUrl.trim();
    if (value.isEmpty) return null;
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !BusinessRegistryDistributionManifest.isAllowedDistributionUri(uri) ||
        !BusinessRegistryDistributionManifest.isAllowedRepositoryPath(uri)) {
      return null;
    }
    return uri;
  }
}

enum BusinessRegistryUpdateStatus {
  updated,
  alreadyCurrent,
  distributionNotConfigured,
}

enum BusinessRegistryUpdateStage {
  readingManifest,
  downloadingRegistry,
  validatingRegistry,
  installingRegistry,
  readingBackAuthority,
  complete,
}

class BusinessRegistryUpdateProgress {
  const BusinessRegistryUpdateProgress({
    required this.stage,
    this.download,
    this.validation,
    this.install,
  });

  final BusinessRegistryUpdateStage stage;
  final BusinessRegistryDownloadProgress? download;
  final BusinessRegistryValidationProgress? validation;
  final BusinessRegistryInstallProgress? install;
}

typedef BusinessRegistryUpdateProgressCallback = void Function(
  BusinessRegistryUpdateProgress progress,
);

class BusinessRegistryUpdateResult {
  const BusinessRegistryUpdateResult({
    required this.status,
    required this.snapshot,
    this.manifest,
  });

  final BusinessRegistryUpdateStatus status;
  final BusinessRegistrySnapshotInfo? snapshot;
  final BusinessRegistryDistributionManifest? manifest;
}

/// Executes the production registry refresh chain as one explicit user/network
/// operation: manifest → bounded download → first-pass stream validation →
/// transactional second-pass install.
///
/// Network/update failure is intentionally surfaced to the caller without
/// modifying the installed registry. Normal invoice lookup never invokes this
/// service directly and remains local-first/offline-capable.
class BusinessRegistryUpdateService {
  const BusinessRegistryUpdateService({
    this.database,
    this.manifestUri,
    this.client,
    this.tempDirectoryProvider,
  });

  static final StreamController<BusinessRegistryUpdateProgress>
      _progressController =
      StreamController<BusinessRegistryUpdateProgress>.broadcast(sync: true);

  /// UI-only observation surface for the explicit Registry update flow.
  ///
  /// This stream does not initiate network work. It only mirrors progress from
  /// an already-running explicit update so My Page can render stage/throughput
  /// telemetry without turning Invoice Review into a network trigger.
  static Stream<BusinessRegistryUpdateProgress> get progressStream =>
      _progressController.stream;

  final Database? database;
  final Uri? manifestUri;
  final http.Client? client;
  final Future<Directory> Function()? tempDirectoryProvider;

  Uri? get _effectiveManifestUri =>
      manifestUri ?? BusinessRegistryUpdateConfiguration.manifestUri;

  bool get isDistributionConfigured {
    final uri = _effectiveManifestUri;
    return uri != null &&
        BusinessRegistryDistributionManifest.isAllowedDistributionUri(uri) &&
        BusinessRegistryDistributionManifest.isAllowedRepositoryPath(uri);
  }

  Future<BusinessRegistryDistributionManifest?> fetchAvailableManifest() async {
    final uri = _effectiveManifestUri;
    if (uri == null) return null;
    final ownedClient = client == null;
    final activeClient = client ?? http.Client();
    try {
      final manifest = await _loadManifest(activeClient, uri);
      final validation = manifest.validate();
      if (!validation.isValid) {
        throw FormatException(validation.errors.join(','));
      }
      return manifest;
    } finally {
      if (ownedClient) activeClient.close();
    }
  }

  Future<BusinessRegistryUpdateResult> update({
    BusinessRegistryDistributionManifest? knownManifest,
    BusinessRegistryUpdateProgressCallback? onProgress,
  }) async {
    final uri = _effectiveManifestUri;
    final repository = BusinessRegistryRepository(database: database);
    if (knownManifest == null && uri == null) {
      return BusinessRegistryUpdateResult(
        status: BusinessRegistryUpdateStatus.distributionNotConfigured,
        snapshot: await repository.installedSnapshot(),
      );
    }

    try {
      await WakelockPlus.enable();
    } catch (_) {}
    final ownedClient = client == null;
    final activeClient = client ?? http.Client();
    try {
      if (knownManifest == null) {
        _emitProgress(
          onProgress,
          const BusinessRegistryUpdateProgress(
            stage: BusinessRegistryUpdateStage.readingManifest,
          ),
        );
      }
      final manifest = knownManifest ?? await _loadManifest(activeClient, uri!);
      final validation = manifest.validate();
      if (!validation.isValid) {
        throw FormatException(validation.errors.join(','));
      }

      final installed = await repository.installedSnapshot();
      if (installed != null &&
          installed.version == manifest.registryVersion &&
          installed.contentSha256 == manifest.registryContentSha256) {
        _emitProgress(
          onProgress,
          const BusinessRegistryUpdateProgress(
            stage: BusinessRegistryUpdateStage.complete,
          ),
        );
        return BusinessRegistryUpdateResult(
          status: BusinessRegistryUpdateStatus.alreadyCurrent,
          snapshot: installed,
          manifest: manifest,
        );
      }

      final tempRoot = tempDirectoryProvider == null
          ? await getTemporaryDirectory()
          : await tempDirectoryProvider!();
      final taskDirectory = Directory(
        '${tempRoot.path}${Platform.pathSeparator}business_registry_update',
      );
      await taskDirectory.create(recursive: true);
      final candidate = File(
        '${taskDirectory.path}${Platform.pathSeparator}'
        '${_safeFileToken(manifest.registryVersion)}.registry.gz.partial',
      );

      _emitProgress(
        onProgress,
        const BusinessRegistryUpdateProgress(
          stage: BusinessRegistryUpdateStage.downloadingRegistry,
        ),
      );
      final downloaded = await BusinessRegistryBoundedDownloader(
        client: activeClient,
      ).download(
        manifest: manifest,
        destinationTempFile: candidate,
        onProgress: (download) => _emitProgress(
          onProgress,
          BusinessRegistryUpdateProgress(
            stage: BusinessRegistryUpdateStage.downloadingRegistry,
            download: download,
          ),
        ),
      );

      _emitProgress(
        onProgress,
        const BusinessRegistryUpdateProgress(
          stage: BusinessRegistryUpdateStage.validatingRegistry,
        ),
      );
      final validated = await const BusinessRegistryStreamValidator().validate(
        manifest: manifest,
        artifact: downloaded,
        onProgress: (validation) => _emitProgress(
          onProgress,
          BusinessRegistryUpdateProgress(
            stage: BusinessRegistryUpdateStage.validatingRegistry,
            validation: validation,
          ),
        ),
      );

      _emitProgress(
        onProgress,
        const BusinessRegistryUpdateProgress(
          stage: BusinessRegistryUpdateStage.installingRegistry,
        ),
      );
      await BusinessRegistryTransactionalStreamInstaller(
        database: database,
      ).install(
        manifest: manifest,
        artifact: validated,
        onProgress: (install) => _emitProgress(
          onProgress,
          BusinessRegistryUpdateProgress(
            stage: BusinessRegistryUpdateStage.installingRegistry,
            install: install,
          ),
        ),
      );

      _emitProgress(
        onProgress,
        const BusinessRegistryUpdateProgress(
          stage: BusinessRegistryUpdateStage.readingBackAuthority,
        ),
      );
      final snapshot = await repository.installedSnapshot();
      if (snapshot == null ||
          snapshot.version != manifest.registryVersion ||
          snapshot.contentSha256 != manifest.registryContentSha256) {
        throw StateError('REGISTRY_UPDATE_POSTINSTALL_AUTHORITY_MISMATCH');
      }
      _emitProgress(
        onProgress,
        const BusinessRegistryUpdateProgress(
          stage: BusinessRegistryUpdateStage.complete,
        ),
      );
      return BusinessRegistryUpdateResult(
        status: BusinessRegistryUpdateStatus.updated,
        snapshot: snapshot,
        manifest: manifest,
      );
    } finally {
      if (ownedClient) activeClient.close();
      try {
        await WakelockPlus.disable();
      } catch (_) {}
    }
  }

  static void _emitProgress(
    BusinessRegistryUpdateProgressCallback? callback,
    BusinessRegistryUpdateProgress progress,
  ) {
    callback?.call(progress);
    _progressController.add(progress);
  }

  Future<BusinessRegistryDistributionManifest> _loadManifest(
    http.Client activeClient,
    Uri uri,
  ) async {
    if (!BusinessRegistryDistributionManifest.isAllowedDistributionUri(uri) ||
        !BusinessRegistryDistributionManifest.isAllowedRepositoryPath(uri)) {
      throw StateError('REGISTRY_MANIFEST_URL_NOT_ALLOWED');
    }

    final request = http.Request('GET', uri);
    final response = await activeClient.send(request);
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        'REGISTRY_MANIFEST_HTTP_STATUS_${response.statusCode}',
        uri: uri,
      );
    }
    final declaredLength = response.contentLength;
    if (declaredLength != null &&
        declaredLength >
            BusinessRegistryDistributionManifest.maxManifestSizeBytes) {
      throw StateError('REGISTRY_MANIFEST_SIZE_EXCEEDED');
    }

    final bytes = BytesBuilder(copy: false);
    var size = 0;
    await for (final chunk in response.stream) {
      size += chunk.length;
      if (size > BusinessRegistryDistributionManifest.maxManifestSizeBytes) {
        throw StateError('REGISTRY_MANIFEST_SIZE_EXCEEDED');
      }
      bytes.add(chunk);
    }
    final text = utf8.decode(bytes.takeBytes(), allowMalformed: false);
    return BusinessRegistryDistributionManifest.fromJsonText(text);
  }

  static String _safeFileToken(String value) => value
      .replaceAll(RegExp(r'[^0-9A-Za-z._-]'), '_')
      .replaceAll(RegExp(r'_+'), '_');
}
