import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'gemini_invoice_settings.dart';

class GeminiModelDescriptor {
  const GeminiModelDescriptor({
    required this.id,
    required this.displayName,
    required this.supportedGenerationMethods,
    this.description,
    this.inputTokenLimit,
    this.outputTokenLimit,
  });

  final String id;
  final String displayName;
  final Set<String> supportedGenerationMethods;
  final String? description;
  final int? inputTokenLimit;
  final int? outputTokenLimit;

  bool get supportsGenerateContent =>
      supportedGenerationMethods.contains('generateContent');

  factory GeminiModelDescriptor.fromJson(Map<String, Object?> json) {
    final rawName = json['name']?.toString().trim() ?? '';
    final id = rawName.replaceFirst(RegExp(r'^models/'), '');
    final methods = (json['supportedGenerationMethods'] as List?)
            ?.map((value) => value.toString())
            .toSet() ??
        const <String>{};
    return GeminiModelDescriptor(
      id: id,
      displayName: json['displayName']?.toString().trim().isNotEmpty == true
          ? json['displayName']!.toString().trim()
          : id,
      supportedGenerationMethods: Set<String>.unmodifiable(methods),
      description: _nullableText(json['description']),
      inputTokenLimit: _integer(json['inputTokenLimit']),
      outputTokenLimit: _integer(json['outputTokenLimit']),
    );
  }

  static String? _nullableText(Object? value) {
    final text = value?.toString().trim();
    return text?.isNotEmpty == true ? text : null;
  }

  static int? _integer(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? '');
  }
}

class GeminiApiKeyTestResult {
  const GeminiApiKeyTestResult({
    required this.ordinal,
    required this.maskedKey,
    required this.available,
    required this.message,
    this.modelCount = 0,
  });

  final int ordinal;
  final String maskedKey;
  final bool available;
  final String message;
  final int modelCount;
}

class GeminiCatalogValidationResult {
  const GeminiCatalogValidationResult({
    required this.keyResults,
    required this.models,
  });

  final List<GeminiApiKeyTestResult> keyResults;
  final List<GeminiModelDescriptor> models;

  bool get hasAvailableKey => keyResults.any((result) => result.available);
}

class GeminiModelCatalogException implements Exception {
  const GeminiModelCatalogException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class GeminiModelCatalogClient {
  GeminiModelCatalogClient({
    http.Client? client,
    this.timeout = const Duration(seconds: 15),
  }) : _client = client ?? http.Client();

  static final Uri _modelsUri = Uri.parse(
    'https://generativelanguage.googleapis.com/v1beta/models?pageSize=1000',
  );

  final http.Client _client;
  final Duration timeout;

  Future<GeminiCatalogValidationResult> validateKeysAndLoadModels(
    List<String> apiKeys,
  ) async {
    final keys = GeminiInvoiceSettings.parseApiKeys(apiKeys.join('\n'));
    final keyResults = <GeminiApiKeyTestResult>[];
    var catalog = const <GeminiModelDescriptor>[];

    for (var index = 0; index < keys.length; index++) {
      final key = keys[index];
      try {
        final models = await listModels(key);
        if (catalog.isEmpty) catalog = models;
        keyResults.add(
          GeminiApiKeyTestResult(
            ordinal: index + 1,
            maskedKey: GeminiInvoiceSettings.maskApiKey(key),
            available: true,
            message: '可用',
            modelCount: models.length,
          ),
        );
      } on GeminiModelCatalogException catch (error) {
        keyResults.add(
          GeminiApiKeyTestResult(
            ordinal: index + 1,
            maskedKey: GeminiInvoiceSettings.maskApiKey(key),
            available: false,
            message: _safeMessage(error),
          ),
        );
      } on TimeoutException {
        keyResults.add(
          GeminiApiKeyTestResult(
            ordinal: index + 1,
            maskedKey: GeminiInvoiceSettings.maskApiKey(key),
            available: false,
            message: '連線逾時',
          ),
        );
      } catch (_) {
        keyResults.add(
          GeminiApiKeyTestResult(
            ordinal: index + 1,
            maskedKey: GeminiInvoiceSettings.maskApiKey(key),
            available: false,
            message: '無法完成安全測試',
          ),
        );
      }
    }

    return GeminiCatalogValidationResult(
      keyResults: List<GeminiApiKeyTestResult>.unmodifiable(keyResults),
      models: List<GeminiModelDescriptor>.unmodifiable(catalog),
    );
  }

  Future<List<GeminiModelDescriptor>> listModels(String apiKey) async {
    final key = apiKey.trim();
    if (key.isEmpty) {
      throw const GeminiModelCatalogException('API Key 為空白');
    }

    final response = await _client
        .get(
          _modelsUri,
          headers: <String, String>{
            'Accept': 'application/json',
            'x-goog-api-key': key,
          },
        )
        .timeout(timeout);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw GeminiModelCatalogException(
        _httpFailureMessage(response.statusCode, response.body),
        statusCode: response.statusCode,
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw const GeminiModelCatalogException('模型清單格式不正確');
    }
    final rawModels = decoded['models'];
    if (rawModels is! List) {
      throw const GeminiModelCatalogException('模型清單為空或格式不正確');
    }

    final models = rawModels
        .whereType<Map>()
        .map(
          (value) => GeminiModelDescriptor.fromJson(
            Map<String, Object?>.from(value.cast<String, Object?>()),
          ),
        )
        .where(
          (model) =>
              model.id.isNotEmpty &&
              model.supportsGenerateContent &&
              !model.id.toLowerCase().contains('embedding'),
        )
        .toList(growable: false)
      ..sort(_compareModels);
    return List<GeminiModelDescriptor>.unmodifiable(models);
  }

  int _compareModels(GeminiModelDescriptor left, GeminiModelDescriptor right) {
    if (left.id == GeminiInvoiceSettings.defaultModel) return -1;
    if (right.id == GeminiInvoiceSettings.defaultModel) return 1;
    final leftFlash = left.id.toLowerCase().contains('flash');
    final rightFlash = right.id.toLowerCase().contains('flash');
    if (leftFlash != rightFlash) return leftFlash ? -1 : 1;
    return left.id.compareTo(right.id);
  }

  String _httpFailureMessage(int statusCode, String body) {
    switch (statusCode) {
      case 400:
        return 'API Key 或要求格式不正確';
      case 401:
        return 'API Key 未通過驗證';
      case 403:
        return 'API Key 沒有 Gemini API 權限';
      case 429:
        return '目前專案配額或頻率限制已達上限';
      default:
        if (statusCode >= 500) return 'Gemini 服務暫時無法使用';
        final normalized = body.replaceAll(RegExp(r'\s+'), ' ').trim();
        final bounded = normalized.length > 120
            ? normalized.substring(0, 120)
            : normalized;
        return bounded.isEmpty ? 'HTTP $statusCode' : 'HTTP $statusCode：$bounded';
    }
  }

  String _safeMessage(GeminiModelCatalogException error) {
    final message = error.message.replaceAll(RegExp(r'AIza[\w-]+'), 'API_KEY');
    return message.length > 160 ? message.substring(0, 160) : message;
  }
}
