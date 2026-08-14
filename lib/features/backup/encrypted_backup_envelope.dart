import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

enum BackupEnvelopeKind { encrypted, legacyPlaintext, unknown }

class EncryptedBackupKdfParameters {
  const EncryptedBackupKdfParameters({
    required this.memoryKiB,
    required this.iterations,
    required this.parallelism,
    this.keyLengthBytes = 32,
  });

  static const EncryptedBackupKdfParameters production =
      EncryptedBackupKdfParameters(
        memoryKiB: 19 * 1024,
        iterations: 2,
        parallelism: 1,
      );

  final int memoryKiB;
  final int iterations;
  final int parallelism;
  final int keyLengthBytes;

  Map<String, Object?> toJson({required List<int> salt}) => <String, Object?>{
    'name': EncryptedBackupEnvelopeCodec.kdfName,
    'memory_kib': memoryKiB,
    'iterations': iterations,
    'parallelism': parallelism,
    'key_length_bytes': keyLengthBytes,
    'salt': base64Encode(salt),
  };
}

class EncryptedBackupInspection {
  const EncryptedBackupInspection({
    required this.kind,
    this.formatVersion,
    this.createdAt,
  });

  final BackupEnvelopeKind kind;
  final int? formatVersion;
  final DateTime? createdAt;
}

class BackupRestorePreview {
  const BackupRestorePreview({
    required this.sourceKind,
    required this.plaintextJson,
    required this.appName,
    required this.exportFormatVersion,
    required this.databaseSchemaVersion,
    required this.createdAt,
    required this.tableCounts,
  });

  final BackupEnvelopeKind sourceKind;
  final String plaintextJson;
  final String appName;
  final int exportFormatVersion;
  final int databaseSchemaVersion;
  final DateTime? createdAt;
  final Map<String, int> tableCounts;
}

class EncryptedBackupEnvelopeCodec {
  EncryptedBackupEnvelopeCodec({
    AesGcm? cipher,
    List<int> Function(int length)? randomBytes,
  }) : _cipher = cipher ?? AesGcm.with256bits(),
       _randomBytes = randomBytes ?? _secureRandomBytes;

  static const String envelopeFormat = 'my_finance_encrypted_backup';
  static const int envelopeFormatVersion = 1;
  static const String plaintextFormat = 'full_backup_json_v1';
  static const String kdfName = 'argon2id';
  static const String cipherName = 'aes-256-gcm';
  static const int saltLength = 16;
  static const int minimumPassphraseLength = 12;

  static const int minimumMemoryKiB = 1024;
  static const int maximumMemoryKiB = 256 * 1024;
  static const int maximumIterations = 10;
  static const int maximumParallelism = 4;

  final AesGcm _cipher;
  final List<int> Function(int length) _randomBytes;

  Future<String> encryptBackupJson(
    String plaintextJson, {
    required String passphrase,
    DateTime? createdAt,
    EncryptedBackupKdfParameters kdfParameters =
        EncryptedBackupKdfParameters.production,
  }) async {
    _validatePassphrase(passphrase);
    _validateBackupJson(plaintextJson);
    _validateKdfParameters(kdfParameters);

    final salt = List<int>.unmodifiable(_randomBytes(saltLength));
    final nonce = List<int>.unmodifiable(_randomBytes(_cipher.nonceLength));
    _validateRandomBytes(salt, saltLength, 'salt');
    _validateRandomBytes(nonce, _cipher.nonceLength, 'nonce');

    final timestamp = (createdAt ?? DateTime.now().toUtc()).toUtc();
    final header = _buildAuthenticatedHeader(
      createdAt: timestamp,
      parameters: kdfParameters,
      salt: salt,
      nonce: nonce,
    );
    final aad = utf8.encode(jsonEncode(header));
    final secretKey = await _deriveKey(
      passphrase: passphrase,
      salt: salt,
      parameters: kdfParameters,
    );
    final secretBox = await _cipher.encrypt(
      utf8.encode(plaintextJson),
      secretKey: secretKey,
      nonce: nonce,
      aad: aad,
    );

    final envelope = <String, Object?>{
      ...header,
      'ciphertext': base64Encode(secretBox.cipherText),
      'mac': base64Encode(secretBox.mac.bytes),
    };
    return const JsonEncoder.withIndent('  ').convert(envelope);
  }

  Future<String> decryptBackupJson(
    String envelopeJson, {
    required String passphrase,
  }) async {
    _validatePassphrase(passphrase);
    final parsed = _parseEncryptedEnvelope(envelopeJson);
    final secretKey = await _deriveKey(
      passphrase: passphrase,
      salt: parsed.salt,
      parameters: parsed.parameters,
    );
    final secretBox = SecretBox(
      parsed.cipherText,
      nonce: parsed.nonce,
      mac: Mac(parsed.mac),
    );

    try {
      final clearText = await _cipher.decrypt(
        secretBox,
        secretKey: secretKey,
        aad: utf8.encode(jsonEncode(parsed.authenticatedHeader)),
      );
      final jsonText = utf8.decode(clearText, allowMalformed: false);
      _validateBackupJson(jsonText);
      return jsonText;
    } on SecretBoxAuthenticationError {
      throw const EncryptedBackupException('加密備份驗證失敗：密碼錯誤或檔案已遭竄改');
    } on FormatException {
      throw const EncryptedBackupException('解密內容不是有效的 UTF-8 JSON 備份');
    }
  }

  EncryptedBackupInspection inspect(String input) {
    Object? decoded;
    try {
      decoded = jsonDecode(input);
    } on FormatException {
      return const EncryptedBackupInspection(kind: BackupEnvelopeKind.unknown);
    }
    if (decoded is! Map) {
      return const EncryptedBackupInspection(kind: BackupEnvelopeKind.unknown);
    }
    final root = Map<String, Object?>.from(decoded);
    if (root['format'] == envelopeFormat) {
      return EncryptedBackupInspection(
        kind: BackupEnvelopeKind.encrypted,
        formatVersion: _asInt(root['format_version']),
        createdAt: DateTime.tryParse(root['created_at']?.toString() ?? ''),
      );
    }
    if (_looksLikeLegacyBackup(root)) {
      final metadata = Map<String, Object?>.from(root['metadata']! as Map);
      return EncryptedBackupInspection(
        kind: BackupEnvelopeKind.legacyPlaintext,
        formatVersion: _asInt(metadata['export_format_version']),
        createdAt: DateTime.tryParse(metadata['created_at']?.toString() ?? ''),
      );
    }
    return const EncryptedBackupInspection(kind: BackupEnvelopeKind.unknown);
  }

  Future<BackupRestorePreview> prepareRestorePreview(
    String input, {
    String? passphrase,
  }) async {
    final inspection = inspect(input);
    final plaintextJson = switch (inspection.kind) {
      BackupEnvelopeKind.encrypted => await decryptBackupJson(
        input,
        passphrase: passphrase ?? '',
      ),
      BackupEnvelopeKind.legacyPlaintext => input,
      BackupEnvelopeKind.unknown => throw const EncryptedBackupException(
        '無法辨識備份檔格式',
      ),
    };

    final decoded = jsonDecode(plaintextJson);
    if (decoded is! Map) {
      throw const EncryptedBackupException('備份預覽失敗：root 必須是 JSON object');
    }
    final root = Map<String, Object?>.from(decoded);
    final metadataRaw = root['metadata'];
    final dataRaw = root['data'];
    if (metadataRaw is! Map || dataRaw is! Map) {
      throw const EncryptedBackupException('備份預覽失敗：缺少 metadata 或 data');
    }
    final metadata = Map<String, Object?>.from(metadataRaw);
    final data = Map<String, Object?>.from(dataRaw);
    final appName = metadata['app_name']?.toString() ?? '';
    final exportFormatVersion = _asRequiredInt(
      metadata['export_format_version'],
      'export_format_version',
    );
    final databaseSchemaVersion = _asRequiredInt(
      metadata['database_schema_version'],
      'database_schema_version',
    );
    if (appName.isEmpty) {
      throw const EncryptedBackupException('備份預覽失敗：app_name 為空');
    }

    final tableCounts = <String, int>{};
    for (final entry in data.entries) {
      final rows = entry.value;
      if (rows is List) tableCounts[entry.key] = rows.length;
    }

    return BackupRestorePreview(
      sourceKind: inspection.kind,
      plaintextJson: plaintextJson,
      appName: appName,
      exportFormatVersion: exportFormatVersion,
      databaseSchemaVersion: databaseSchemaVersion,
      createdAt: DateTime.tryParse(metadata['created_at']?.toString() ?? ''),
      tableCounts: Map<String, int>.unmodifiable(tableCounts),
    );
  }

  Future<SecretKey> _deriveKey({
    required String passphrase,
    required List<int> salt,
    required EncryptedBackupKdfParameters parameters,
  }) {
    final algorithm = Argon2id(
      memory: parameters.memoryKiB,
      iterations: parameters.iterations,
      parallelism: parameters.parallelism,
      hashLength: parameters.keyLengthBytes,
    );
    return algorithm.deriveKeyFromPassword(password: passphrase, nonce: salt);
  }

  Map<String, Object?> _buildAuthenticatedHeader({
    required DateTime createdAt,
    required EncryptedBackupKdfParameters parameters,
    required List<int> salt,
    required List<int> nonce,
  }) => <String, Object?>{
    'format': envelopeFormat,
    'format_version': envelopeFormatVersion,
    'plaintext_format': plaintextFormat,
    'created_at': createdAt.toUtc().toIso8601String(),
    'kdf': parameters.toJson(salt: salt),
    'cipher': <String, Object?>{
      'name': cipherName,
      'nonce': base64Encode(nonce),
    },
  };

  _ParsedEncryptedEnvelope _parseEncryptedEnvelope(String envelopeJson) {
    final decoded = jsonDecode(envelopeJson);
    if (decoded is! Map) {
      throw const EncryptedBackupException('加密備份格式錯誤：root 必須是 JSON object');
    }
    final root = Map<String, Object?>.from(decoded);
    const allowedTopLevel = <String>{
      'format',
      'format_version',
      'plaintext_format',
      'created_at',
      'kdf',
      'cipher',
      'ciphertext',
      'mac',
    };
    if (root.keys.any((key) => !allowedTopLevel.contains(key))) {
      throw const EncryptedBackupException('加密備份包含不支援的欄位');
    }
    if (root['format'] != envelopeFormat ||
        root['format_version'] != envelopeFormatVersion ||
        root['plaintext_format'] != plaintextFormat) {
      throw const EncryptedBackupException('不支援的加密備份格式或版本');
    }

    final createdAt = DateTime.tryParse(root['created_at']?.toString() ?? '');
    if (createdAt == null) {
      throw const EncryptedBackupException('加密備份 created_at 格式錯誤');
    }
    final kdfRaw = root['kdf'];
    final cipherRaw = root['cipher'];
    if (kdfRaw is! Map || cipherRaw is! Map) {
      throw const EncryptedBackupException('加密備份缺少 kdf 或 cipher');
    }
    final kdf = Map<String, Object?>.from(kdfRaw);
    final cipher = Map<String, Object?>.from(cipherRaw);
    const allowedKdfFields = <String>{
      'name',
      'memory_kib',
      'iterations',
      'parallelism',
      'key_length_bytes',
      'salt',
    };
    const allowedCipherFields = <String>{'name', 'nonce'};
    if (kdf.keys.any((key) => !allowedKdfFields.contains(key)) ||
        cipher.keys.any((key) => !allowedCipherFields.contains(key))) {
      throw const EncryptedBackupException('加密備份 KDF 或 cipher 欄位不受支援');
    }
    if (kdf['name'] != kdfName || cipher['name'] != cipherName) {
      throw const EncryptedBackupException('不支援的 KDF 或 cipher');
    }

    final parameters = EncryptedBackupKdfParameters(
      memoryKiB: _asRequiredInt(kdf['memory_kib'], 'memory_kib'),
      iterations: _asRequiredInt(kdf['iterations'], 'iterations'),
      parallelism: _asRequiredInt(kdf['parallelism'], 'parallelism'),
      keyLengthBytes: _asRequiredInt(
        kdf['key_length_bytes'],
        'key_length_bytes',
      ),
    );
    _validateKdfParameters(parameters);
    final salt = _decodeBase64(kdf['salt'], 'salt');
    final nonce = _decodeBase64(cipher['nonce'], 'nonce');
    final cipherText = _decodeBase64(root['ciphertext'], 'ciphertext');
    final mac = _decodeBase64(root['mac'], 'mac');
    if (salt.length != saltLength) {
      throw const EncryptedBackupException('加密備份 salt 長度錯誤');
    }
    if (nonce.length != _cipher.nonceLength) {
      throw const EncryptedBackupException('加密備份 nonce 長度錯誤');
    }
    if (mac.length != _cipher.macAlgorithm.macLength) {
      throw const EncryptedBackupException('加密備份 MAC 長度錯誤');
    }
    if (cipherText.isEmpty) {
      throw const EncryptedBackupException('加密備份 ciphertext 為空');
    }

    final authenticatedHeader = _buildAuthenticatedHeader(
      createdAt: createdAt.toUtc(),
      parameters: parameters,
      salt: salt,
      nonce: nonce,
    );
    return _ParsedEncryptedEnvelope(
      parameters: parameters,
      salt: salt,
      nonce: nonce,
      cipherText: cipherText,
      mac: mac,
      authenticatedHeader: authenticatedHeader,
    );
  }

  void _validatePassphrase(String passphrase) {
    if (passphrase.runes.length < minimumPassphraseLength) {
      throw const EncryptedBackupException('備份密碼至少需要 12 個字元');
    }
  }

  void _validateKdfParameters(EncryptedBackupKdfParameters parameters) {
    if (parameters.memoryKiB < minimumMemoryKiB ||
        parameters.memoryKiB > maximumMemoryKiB ||
        parameters.iterations < 1 ||
        parameters.iterations > maximumIterations ||
        parameters.parallelism < 1 ||
        parameters.parallelism > maximumParallelism ||
        parameters.keyLengthBytes != 32) {
      throw const EncryptedBackupException('加密備份 KDF 參數超出允許範圍');
    }
  }

  void _validateBackupJson(String jsonText) {
    final decoded = jsonDecode(jsonText);
    if (decoded is! Map) {
      throw const EncryptedBackupException('完整備份必須是 JSON object');
    }
    final root = Map<String, Object?>.from(decoded);
    if (!_looksLikeLegacyBackup(root)) {
      throw const EncryptedBackupException('內容不是可辨識的完整備份 JSON');
    }
  }

  bool _looksLikeLegacyBackup(Map<String, Object?> root) {
    final metadata = root['metadata'];
    final data = root['data'];
    if (metadata is! Map || data is! Map) return false;
    return metadata['export_mode'] == 'full_backup' &&
        metadata['app_name'] != null &&
        metadata['export_format_version'] is num;
  }

  static List<int> _secureRandomBytes(int length) {
    final random = Random.secure();
    return List<int>.generate(
      length,
      (_) => random.nextInt(256),
      growable: false,
    );
  }

  void _validateRandomBytes(List<int> bytes, int length, String label) {
    if (bytes.length != length ||
        bytes.any((value) => value < 0 || value > 255)) {
      throw EncryptedBackupException('隨機 $label 產生器回傳無效資料');
    }
  }

  List<int> _decodeBase64(Object? raw, String label) {
    if (raw is! String || raw.isEmpty) {
      throw EncryptedBackupException('加密備份 $label 格式錯誤');
    }
    try {
      return base64Decode(raw);
    } on FormatException {
      throw EncryptedBackupException('加密備份 $label 不是有效 Base64');
    }
  }

  int _asRequiredInt(Object? value, String label) {
    final parsed = _asInt(value);
    if (parsed == null) {
      throw EncryptedBackupException('加密備份 $label 必須是整數');
    }
    return parsed;
  }

  int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num && value == value.roundToDouble()) return value.toInt();
    return null;
  }
}

class _ParsedEncryptedEnvelope {
  const _ParsedEncryptedEnvelope({
    required this.parameters,
    required this.salt,
    required this.nonce,
    required this.cipherText,
    required this.mac,
    required this.authenticatedHeader,
  });

  final EncryptedBackupKdfParameters parameters;
  final List<int> salt;
  final List<int> nonce;
  final List<int> cipherText;
  final List<int> mac;
  final Map<String, Object?> authenticatedHeader;
}

class EncryptedBackupException implements Exception {
  const EncryptedBackupException(this.message);

  final String message;

  @override
  String toString() => message;
}
