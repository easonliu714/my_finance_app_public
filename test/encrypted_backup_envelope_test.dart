import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/features/backup/encrypted_backup_envelope.dart';

void main() {
  const passphrase = 'correct-passphrase-123';
  const wrongPassphrase = 'incorrect-passphrase-456';
  const testKdf = EncryptedBackupKdfParameters(
    memoryKiB: 1024,
    iterations: 1,
    parallelism: 1,
  );

  test('production KDF profile matches the documented Argon2id baseline', () {
    expect(EncryptedBackupKdfParameters.production.memoryKiB, 19 * 1024);
    expect(EncryptedBackupKdfParameters.production.iterations, 2);
    expect(EncryptedBackupKdfParameters.production.parallelism, 1);
    expect(EncryptedBackupKdfParameters.production.keyLengthBytes, 32);
  });

  test(
    'encrypted backup round-trips and produces a read-only preview',
    () async {
      final codec = _deterministicCodec();
      final plaintext = _legacyBackupJson();

      final encrypted = await codec.encryptBackupJson(
        plaintext,
        passphrase: passphrase,
        createdAt: DateTime.utc(2026, 6, 28, 6),
        kdfParameters: testKdf,
      );

      expect(encrypted, isNot(contains('Private merchant note')));
      expect(codec.inspect(encrypted).kind, BackupEnvelopeKind.encrypted);

      final decrypted = await codec.decryptBackupJson(
        encrypted,
        passphrase: passphrase,
      );
      expect(jsonDecode(decrypted), jsonDecode(plaintext));

      final preview = await codec.prepareRestorePreview(
        encrypted,
        passphrase: passphrase,
      );
      expect(preview.sourceKind, BackupEnvelopeKind.encrypted);
      expect(preview.appName, 'My Finance App');
      expect(preview.exportFormatVersion, 1);
      expect(preview.databaseSchemaVersion, 16);
      expect(preview.tableCounts['accounts'], 1);
      expect(preview.tableCounts['transactions'], 1);
      expect(jsonDecode(preview.plaintextJson), jsonDecode(plaintext));
    },
  );

  test('wrong passphrase fails closed without returning plaintext', () async {
    final codec = _deterministicCodec();
    final encrypted = await codec.encryptBackupJson(
      _legacyBackupJson(),
      passphrase: passphrase,
      kdfParameters: testKdf,
    );

    await expectLater(
      codec.decryptBackupJson(encrypted, passphrase: wrongPassphrase),
      throwsA(
        isA<EncryptedBackupException>().having(
          (error) => error.message,
          'message',
          contains('密碼錯誤或檔案已遭竄改'),
        ),
      ),
    );
  });

  test('ciphertext tampering fails authentication', () async {
    final codec = _deterministicCodec();
    final encrypted = await codec.encryptBackupJson(
      _legacyBackupJson(),
      passphrase: passphrase,
      kdfParameters: testKdf,
    );
    final root = Map<String, Object?>.from(jsonDecode(encrypted) as Map);
    final cipherText = base64Decode(root['ciphertext']! as String);
    cipherText[0] ^= 0x01;
    root['ciphertext'] = base64Encode(cipherText);

    await expectLater(
      codec.decryptBackupJson(jsonEncode(root), passphrase: passphrase),
      throwsA(isA<EncryptedBackupException>()),
    );
  });

  test('authenticated header tampering fails authentication', () async {
    final codec = _deterministicCodec();
    final encrypted = await codec.encryptBackupJson(
      _legacyBackupJson(),
      passphrase: passphrase,
      createdAt: DateTime.utc(2026, 6, 28, 6),
      kdfParameters: testKdf,
    );
    final root = Map<String, Object?>.from(jsonDecode(encrypted) as Map);
    root['created_at'] = DateTime.utc(2026, 6, 29, 6).toIso8601String();

    await expectLater(
      codec.decryptBackupJson(jsonEncode(root), passphrase: passphrase),
      throwsA(isA<EncryptedBackupException>()),
    );
  });

  test('MAC tampering fails authentication', () async {
    final codec = _deterministicCodec();
    final encrypted = await codec.encryptBackupJson(
      _legacyBackupJson(),
      passphrase: passphrase,
      kdfParameters: testKdf,
    );
    final root = Map<String, Object?>.from(jsonDecode(encrypted) as Map);
    final mac = base64Decode(root['mac']! as String);
    mac[0] ^= 0x01;
    root['mac'] = base64Encode(mac);

    await expectLater(
      codec.decryptBackupJson(jsonEncode(root), passphrase: passphrase),
      throwsA(isA<EncryptedBackupException>()),
    );
  });

  test('legacy plaintext backup remains detectable and previewable', () async {
    final codec = _deterministicCodec();
    final legacy = _legacyBackupJson();

    expect(codec.inspect(legacy).kind, BackupEnvelopeKind.legacyPlaintext);
    final preview = await codec.prepareRestorePreview(legacy);

    expect(preview.sourceKind, BackupEnvelopeKind.legacyPlaintext);
    expect(preview.tableCounts, <String, int>{
      'accounts': 1,
      'transactions': 1,
    });
    expect(preview.plaintextJson, legacy);
  });

  test(
    'unknown input and malformed KDF profiles are rejected before restore',
    () async {
      final codec = _deterministicCodec();
      expect(codec.inspect('not-json').kind, BackupEnvelopeKind.unknown);
      await expectLater(
        codec.prepareRestorePreview('not-json'),
        throwsA(isA<EncryptedBackupException>()),
      );

      final encrypted = await codec.encryptBackupJson(
        _legacyBackupJson(),
        passphrase: passphrase,
        kdfParameters: testKdf,
      );
      final root = Map<String, Object?>.from(jsonDecode(encrypted) as Map);
      final kdf = Map<String, Object?>.from(root['kdf']! as Map);
      kdf['memory_kib'] = EncryptedBackupEnvelopeCodec.maximumMemoryKiB + 1;
      root['kdf'] = kdf;

      await expectLater(
        codec.decryptBackupJson(jsonEncode(root), passphrase: passphrase),
        throwsA(
          isA<EncryptedBackupException>().having(
            (error) => error.message,
            'message',
            contains('KDF 參數超出允許範圍'),
          ),
        ),
      );
    },
  );

  test(
    'short passphrases are rejected for encryption and decryption',
    () async {
      final codec = _deterministicCodec();
      await expectLater(
        codec.encryptBackupJson(
          _legacyBackupJson(),
          passphrase: 'too-short',
          kdfParameters: testKdf,
        ),
        throwsA(isA<EncryptedBackupException>()),
      );
    },
  );
}

EncryptedBackupEnvelopeCodec _deterministicCodec() {
  var cursor = 1;
  return EncryptedBackupEnvelopeCodec(
    randomBytes: (length) {
      final bytes = List<int>.generate(
        length,
        (index) => (cursor + index * 17) & 0xff,
        growable: false,
      );
      cursor += length;
      return bytes;
    },
  );
}

String _legacyBackupJson() {
  return jsonEncode(<String, Object?>{
    'metadata': <String, Object?>{
      'export_format_version': 1,
      'app_name': 'My Finance App',
      'app_version': '4.12.28+366',
      'phase': 'P4.SEC.1 test fixture',
      'database_schema_version': 16,
      'created_at': DateTime.utc(2026, 6, 28, 5).toIso8601String(),
      'source_platform': 'android',
      'export_mode': 'full_backup',
    },
    'data': <String, Object?>{
      'accounts': <Object?>[
        <String, Object?>{'id': 'account-cash', 'name': '現金'},
      ],
      'transactions': <Object?>[
        <String, Object?>{
          'id': 'txn-1',
          'amount': 90,
          'note': 'Private merchant note',
        },
      ],
    },
  });
}
