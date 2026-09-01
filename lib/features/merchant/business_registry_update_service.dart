import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'business_registry_bounded_downloader.dart';
import 'business_registry_distribution_manifest.dart';
import 'business_registry_repository.dart';
import 'business_registry_stream_validator.dart';
import 'business_registry_transactional_stream_installer.dart';

class BusinessRegistryUpdateConfiguration {
  const BusinessRegistryUpdateConfiguration._();

  static const String manifestUrl = String.fromEnvironment(
    'BUSINESS_REGISTRY_MANIFEST_URL',
    defaultValue: '',
  );

  static Uri? get manifestUri {
    final value = manifestUrl.trim();
    if (value.isEmpty) return null;
    final uri = Uri.tryParse(value);
    if (uri == null || uri.scheme != 'https') return null;
    return uri;
  }
}

enum BusinessRegistryUpdateStatus {
  updated,
  alreadyCurrent,
  distributionNotConfigured,
}

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

  final Database? database;
  final Uri? manifestUri;
  final http.Client? client;
  final Future<Directory> Function()? tempDirectoryProvider;

  bool get isDistributionConfigured =>
      (manifestUri ?? BusinessRegistryUpdateConfiguration.manifestUri) != null;

  Future<BusinessRegistryDistributionManifest?> fetchAvailableManifest() async {
    final uri = manifestUri ?? BusinessRegistryUpdateConfiguration.manifestUri;
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
  }) async {
    final uri = manifestUri ?? BusinessRegistryUpdateConfiguration.manifestUri;
    final repository = BusinessRegistryRepository(database: database);
    if (knownManifest == null && uri == null) {
      return BusinessRegistryUpdateResult(
        status: BusinessRegistryUpdateStatus.distributionNotConfigured,
        snapshot: await repository.installedSnapshot(),
      );
    }

    final ownedClient = client == null;
    final activeClient = client ?? http.Client();
    try {
      final manifest = knownManifest ?? await _loadManifest(activeClient, uri!);
      final validation = manifest.validate();
      if (!validation.isValid) {
        throw FormatException(validation.errors.join(','));
      }

      final installed = await repository.installedSnapshot();
      if (installed != null &&
          installed.version == manifest.registryVersion &&
          installed.contentSha256 == manifest.registryContentSha256) {
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

      final downloaded = await BusinessRegistryBoundedDownloader(
        client: activeClient,
      ).download(
        manifest: manifest,
        destinationTempFile: candidate,
      );
      final validated = await const BusinessRegistryStreamValidator().validate(
        manifest: manifest,
        artifact: downloaded,
      );
      await BusinessRegistryTransactionalStreamInstaller(
        database: database,
      ).install(
        manifest: manifest,
        artifact: validated,
      );

      final snapshot = await repository.installedSnapshot();
      if (snapshot == null ||
          snapshot.version != manifest.registryVersion ||
          snapshot.contentSha256 != manifest.registryContentSha256) {
        throw StateError('REGISTRY_UPDATE_POSTINSTALL_AUTHORITY_MISMATCH');
      }
      return BusinessRegistryUpdateResult(
        status: BusinessRegistryUpdateStatus.updated,
        snapshot: snapshot,
        manifest: manifest,
      );
    } finally {
      if (ownedClient) activeClient.close();
    }
  }

  Future<BusinessRegistryDistributionManifest> _loadManifest(
    http.Client activeClient,
    Uri uri,
  ) async {
    final response = await activeClient.get(uri);
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        'REGISTRY_MANIFEST_HTTP_STATUS_${response.statusCode}',
        uri: uri,
      );
    }
    if (response.bodyBytes.length > 64 * 1024) {
      throw StateError('REGISTRY_MANIFEST_SIZE_EXCEEDED');
    }
    final text = utf8.decode(response.bodyBytes, allowMalformed: false);
    return BusinessRegistryDistributionManifest.fromJsonText(text);
  }

  static String _safeFileToken(String value) => value
      .replaceAll(RegExp(r'[^0-9A-Za-z._-]'), '_')
      .replaceAll(RegExp(r'_+'), '_');
}
