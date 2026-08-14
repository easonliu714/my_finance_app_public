import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';

import 'restore_source_grant.dart';

class FileExchangeResult {
  const FileExchangeResult({required this.path, required this.message});

  final String path;
  final String message;
}

class RestoreSourcePickResult {
  const RestoreSourcePickResult({required this.grant, this.path, this.bytes});

  final RestoreSourceGrant grant;
  final String? path;
  final Uint8List? bytes;

  bool get hasPreviewBytes => bytes != null && bytes!.isNotEmpty;
}

abstract class FileExchangePort {
  Future<FileExchangeResult> shareFile({required File file, required String subject, String? text});
  Future<String?> pickOpenFilePath({List<String>? allowedExtensions});
  Future<RestoreSourcePickResult?> pickRestoreSource({List<String>? allowedExtensions});
  Future<RestoreSourcePickResult?> pickReadableImportSource({List<String>? allowedExtensions});
}

class PlatformFileExchangeService implements FileExchangePort {
  const PlatformFileExchangeService();

  @override
  Future<FileExchangeResult> shareFile({required File file, required String subject, String? text}) async {
    await SharePlus.instance.share(
      ShareParams(
        files: <XFile>[XFile(file.path)],
        subject: subject,
        text: text,
      ),
    );
    return FileExchangeResult(path: file.path, message: '已開啟系統分享面板：${file.path}');
  }

  @override
  Future<String?> pickOpenFilePath({List<String>? allowedExtensions}) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: allowedExtensions,
      allowMultiple: false,
      withData: false,
    );
    return result?.files.single.path;
  }

  @override
  Future<RestoreSourcePickResult?> pickRestoreSource({List<String>? allowedExtensions}) {
    return _pickDocumentSource(allowedExtensions: allowedExtensions ?? const <String>['json']);
  }

  @override
  Future<RestoreSourcePickResult?> pickReadableImportSource({List<String>? allowedExtensions}) {
    return _pickDocumentSource(allowedExtensions: allowedExtensions ?? const <String>['json', 'csv']);
  }

  Future<RestoreSourcePickResult?> _pickDocumentSource({required List<String> allowedExtensions}) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: allowedExtensions,
      allowMultiple: false,
      withData: true,
    );
    final file = result?.files.single;
    if (file == null) return null;
    final path = file.path;
    final hasReadablePath = path != null && path.isNotEmpty;
    final bytes = file.bytes;
    final hasBytes = bytes != null && bytes.isNotEmpty;
    final uri = hasReadablePath ? path : 'provider:${file.identifier ?? file.name}';
    final grant = RestoreSourceGrant(
      uri: uri,
      displayName: file.name,
      grantedAt: DateTime.now().toUtc(),
      sourceKind: RestoreSourceKind.documentFile,
      persisted: true,
      pathBacked: hasReadablePath,
    );
    return RestoreSourcePickResult(grant: grant, path: path, bytes: hasBytes ? bytes : null);
  }
}
