import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'gemini_invoice_settings.dart';

abstract interface class GeminiInvoiceSettingsStore {
  Future<GeminiInvoiceSettings> load();

  Future<void> save(GeminiInvoiceSettings settings);

  Future<void> clear();
}

class GeminiInvoiceSettingsRepository implements GeminiInvoiceSettingsStore {
  const GeminiInvoiceSettingsRepository({
    FlutterSecureStorage storage = const FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true),
    ),
  }) : _storage = storage;

  static const String _storageKey =
      'my_finance_app.invoice_vision.gemini_settings.v1';

  final FlutterSecureStorage _storage;

  @override
  Future<GeminiInvoiceSettings> load() async {
    try {
      final encoded = await _storage.read(key: _storageKey);
      return GeminiInvoiceSettings.decode(encoded);
    } catch (_) {
      // Secure storage must fail closed. Tests inject the official plugin mock
      // through test/flutter_test_config.dart instead of production timers.
      return const GeminiInvoiceSettings();
    }
  }

  @override
  Future<void> save(GeminiInvoiceSettings settings) {
    return _storage.write(key: _storageKey, value: settings.encode());
  }

  @override
  Future<void> clear() => _storage.delete(key: _storageKey);
}
