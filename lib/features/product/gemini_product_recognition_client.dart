import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'product_recognition_candidate.dart';

abstract interface class GeminiProductRecognitionPort {
  Future<ProductRecognitionCandidate> recognize({
    required String apiKey,
    required String model,
    required Uint8List imageBytes,
    required String mimeType,
  });
}

enum GeminiProductRecognitionFailureKind {
  invalidInput,
  authentication,
  quota,
  requestRejected,
  serviceUnavailable,
  timeout,
  network,
  safetyBlocked,
  malformedResponse,
}

class GeminiProductRecognitionException implements Exception {
  const GeminiProductRecognitionException(
    this.kind,
    this.message, {
    this.statusCode,
  });

  final GeminiProductRecognitionFailureKind kind;
  final String message;
  final int? statusCode;

  bool get retryWithNextKey => switch (kind) {
        GeminiProductRecognitionFailureKind.authentication ||
        GeminiProductRecognitionFailureKind.quota ||
        GeminiProductRecognitionFailureKind.serviceUnavailable ||
        GeminiProductRecognitionFailureKind.timeout ||
        GeminiProductRecognitionFailureKind.network => true,
        GeminiProductRecognitionFailureKind.invalidInput ||
        GeminiProductRecognitionFailureKind.requestRejected ||
        GeminiProductRecognitionFailureKind.safetyBlocked ||
        GeminiProductRecognitionFailureKind.malformedResponse => false,
      };

  @override
  String toString() => message;
}

class GeminiProductRecognitionClient implements GeminiProductRecognitionPort {
  GeminiProductRecognitionClient({
    http.Client? client,
    this.timeout = const Duration(seconds: 75),
    this.maximumInlineImageBytes = 8 * 1024 * 1024,
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final Duration timeout;
  final int maximumInlineImageBytes;

  static const Set<String> _supportedMimeTypes = <String>{
    'image/jpeg',
    'image/png',
    'image/webp',
  };

  @override
  Future<ProductRecognitionCandidate> recognize({
    required String apiKey,
    required String model,
    required Uint8List imageBytes,
    required String mimeType,
  }) async {
    final key = apiKey.trim();
    final normalizedModel = model.trim().replaceFirst(RegExp(r'^models/'), '');
    final normalizedMime = mimeType.trim().toLowerCase();

    if (key.isEmpty) {
      throw const GeminiProductRecognitionException(
        GeminiProductRecognitionFailureKind.invalidInput,
        'Gemini API Key 為空白。',
      );
    }
    if (normalizedModel.isEmpty) {
      throw const GeminiProductRecognitionException(
        GeminiProductRecognitionFailureKind.invalidInput,
        'Gemini 模型名稱為空白。',
      );
    }
    if (imageBytes.isEmpty || imageBytes.length > maximumInlineImageBytes) {
      throw GeminiProductRecognitionException(
        GeminiProductRecognitionFailureKind.invalidInput,
        imageBytes.isEmpty ? '待辨識商品影像為空白。' : '待辨識商品影像超過安全上限。',
      );
    }
    if (!_supportedMimeTypes.contains(normalizedMime)) {
      throw const GeminiProductRecognitionException(
        GeminiProductRecognitionFailureKind.invalidInput,
        '待辨識商品影像格式不支援。',
      );
    }

    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/'
      '$normalizedModel:generateContent',
    );
    final generationConfig = <String, Object?>{
      'temperature': 0,
      'maxOutputTokens': 3072,
      if (RegExp(r'^gemini-3').hasMatch(normalizedModel))
        'thinkingConfig': <String, Object?>{
          'thinkingLevel': 'low',
        },
      'responseMimeType': 'application/json',
      'responseJsonSchema': _responseSchema,
    };
    final requestBody = <String, Object?>{
      'contents': <Object?>[
        <String, Object?>{
          'role': 'user',
          'parts': <Object?>[
            <String, Object?>{
              'inline_data': <String, Object?>{
                'mime_type': normalizedMime,
                'data': base64Encode(imageBytes),
              },
            },
            <String, Object?>{'text': _prompt},
          ],
        },
      ],
      'generationConfig': generationConfig,
    };

    late http.Response response;
    try {
      response = await _client
          .post(
            uri,
            headers: <String, String>{
              'Accept': 'application/json',
              'Content-Type': 'application/json',
              'x-goog-api-key': key,
            },
            body: jsonEncode(requestBody),
          )
          .timeout(timeout);
    } on TimeoutException {
      throw const GeminiProductRecognitionException(
        GeminiProductRecognitionFailureKind.timeout,
        'Gemini 商品辨識連線逾時。',
      );
    } on http.ClientException {
      throw const GeminiProductRecognitionException(
        GeminiProductRecognitionFailureKind.network,
        'Gemini 商品辨識網路連線失敗。',
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _httpFailure(response.statusCode, response.body);
    }

    final decoded = _decodeObject(response.body);
    final text = _candidateText(decoded);
    final candidateJson = _decodeObject(text);
    final candidate = ProductRecognitionCandidate.fromJson(candidateJson);
    if (!candidate.hasUsefulCandidate) {
      throw const GeminiProductRecognitionException(
        GeminiProductRecognitionFailureKind.malformedResponse,
        'Gemini 未回傳可供人工覆核的商品欄位。',
      );
    }
    return candidate;
  }

  GeminiProductRecognitionException _httpFailure(
    int statusCode,
    String body,
  ) {
    final detail = _safeGoogleErrorDetail(body);
    if (statusCode == 401 || statusCode == 403) {
      return GeminiProductRecognitionException(
        GeminiProductRecognitionFailureKind.authentication,
        detail.isEmpty
            ? 'Gemini API Key 未通過驗證或沒有模型權限。'
            : 'Gemini 權限驗證失敗：$detail',
        statusCode: statusCode,
      );
    }
    if (statusCode == 429) {
      return GeminiProductRecognitionException(
        GeminiProductRecognitionFailureKind.quota,
        detail.isEmpty
            ? 'Gemini API Key 已達配額或頻率限制。'
            : 'Gemini 配額或頻率限制：$detail',
        statusCode: statusCode,
      );
    }
    if (statusCode == 408 || statusCode >= 500) {
      return GeminiProductRecognitionException(
        GeminiProductRecognitionFailureKind.serviceUnavailable,
        detail.isEmpty
            ? 'Gemini 服務暫時無法完成商品辨識。'
            : 'Gemini 服務暫時無法完成商品辨識：$detail',
        statusCode: statusCode,
      );
    }
    return GeminiProductRecognitionException(
      GeminiProductRecognitionFailureKind.requestRejected,
      detail.isEmpty
          ? 'Gemini 商品辨識要求被拒絕（HTTP $statusCode）。'
          : 'Gemini 商品辨識要求被拒絕（HTTP $statusCode）：$detail',
      statusCode: statusCode,
    );
  }

  String _safeGoogleErrorDetail(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final error = decoded['error'];
        if (error is Map) {
          final status = error['status']?.toString().trim() ?? '';
          final message = error['message']?.toString().trim() ?? '';
          return _boundSafeDetail(
            <String>[
              if (status.isNotEmpty) status,
              if (message.isNotEmpty) message,
            ].join('：'),
          );
        }
      }
    } catch (_) {}
    return _boundSafeDetail(body);
  }

  String _boundSafeDetail(String value) {
    final sanitized = value
        .replaceAll(RegExp(r'AIza[\w-]+'), 'API_KEY')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (sanitized.isEmpty) return '';
    return sanitized.length > 240 ? sanitized.substring(0, 240) : sanitized;
  }

  Map<String, Object?> _decodeObject(String encoded) {
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is Map) {
        return Map<String, Object?>.from(decoded.cast<String, Object?>());
      }
    } catch (_) {}
    throw const GeminiProductRecognitionException(
      GeminiProductRecognitionFailureKind.malformedResponse,
      'Gemini 回應不是有效的 JSON 物件。',
    );
  }

  String _candidateText(Map<String, Object?> response) {
    final candidates = response['candidates'];
    if (candidates is! List || candidates.isEmpty) {
      final promptFeedback = response['promptFeedback'];
      if (promptFeedback is Map &&
          promptFeedback['blockReason']?.toString().trim().isNotEmpty == true) {
        throw const GeminiProductRecognitionException(
          GeminiProductRecognitionFailureKind.safetyBlocked,
          'Gemini 安全政策未允許處理這張商品影像。',
        );
      }
      throw const GeminiProductRecognitionException(
        GeminiProductRecognitionFailureKind.malformedResponse,
        'Gemini 回應沒有商品候選結果。',
      );
    }

    final candidate = candidates.first;
    if (candidate is! Map) {
      throw const GeminiProductRecognitionException(
        GeminiProductRecognitionFailureKind.malformedResponse,
        'Gemini 商品候選格式不正確。',
      );
    }
    final content = candidate['content'];
    if (content is! Map) {
      throw const GeminiProductRecognitionException(
        GeminiProductRecognitionFailureKind.malformedResponse,
        'Gemini 商品候選內容格式不正確。',
      );
    }
    final parts = content['parts'];
    if (parts is! List) {
      throw const GeminiProductRecognitionException(
        GeminiProductRecognitionFailureKind.malformedResponse,
        'Gemini 商品候選沒有文字結果。',
      );
    }
    final text = parts
        .whereType<Map>()
        .map((part) => part['text']?.toString().trim() ?? '')
        .firstWhere((value) => value.isNotEmpty, orElse: () => '');
    if (text.isEmpty) {
      throw const GeminiProductRecognitionException(
        GeminiProductRecognitionFailureKind.malformedResponse,
        'Gemini 商品候選沒有可解析文字。',
      );
    }
    return text;
  }

  static const String _prompt = '''
你是台灣個人記帳 App 的商品照片辨識器。你的輸出只是一份「待人工覆核候選」，不是正式交易。

只能根據這張影像目前清楚可見的證據填值。不確定、被遮住、沒有顯示或無法可靠判斷的欄位必須回傳 null；不得為了完成記帳而猜測價格、店家、數量或品名。

欄位規則：
1. productName：逐字或保守整理影像上明確可辨識的主要商品名稱。品牌名稱不等於完整商品名稱；若只能看到品牌，可只填品牌或保持 null。
2. quantity：只有影像明確標示數量，或可直接且無歧義地數出商品件數時才填。模糊、遮擋、可能包含背景物件時填 null。
3. unitPrice：只有包裝、價牌、標籤或畫面明確顯示單價時才填。不得從常識、市價或商品名稱猜測。
4. totalAmount：只有影像明確顯示該商品／這組商品的總價時才填。不得自行用 quantity × unitPrice 填入 totalAmount；App 端會在兩者都可信時另外標記為 derived。
5. categorySuggestion：可以提供粗粒度記帳分類建議，但只是 suggestion，不是正式分類 authority。不確定就填 null。
6. merchantName：只有影像中有明確商店／交易場所證據時才填。商品品牌、製造商、代理商不能直接當成 merchantName。
7. recognizedText：只保留與商品、數量、價格、店家有關的簡短可見文字證據；不要全文轉錄背景。
8. confidence：0 到 1，只代表各欄位可見證據可信度；不得用高 confidence 掩蓋推測。
9. warnings：記錄多商品、遮擋、價錢歧義、品牌與商家可能混淆、數量不明等需要人工確認的理由。

如果畫面有多個不同商品，不要自行建立多筆交易。productName 可給一個保守摘要，並在 warnings 標示 multiple_products_visible；無法形成可靠主要商品候選時，各欄位保持 null。
''';

  static final Map<String, Object?> _responseSchema = <String, Object?>{
    'type': 'object',
    'properties': <String, Object?>{
      'productName': <String, Object?>{
        'type': <String>['string', 'null'],
      },
      'quantity': <String, Object?>{
        'type': <String>['number', 'null'],
      },
      'unitPrice': <String, Object?>{
        'type': <String>['number', 'null'],
      },
      'totalAmount': <String, Object?>{
        'type': <String>['number', 'null'],
      },
      'categorySuggestion': <String, Object?>{
        'type': <String>['string', 'null'],
      },
      'merchantName': <String, Object?>{
        'type': <String>['string', 'null'],
      },
      'recognizedText': <String, Object?>{
        'type': <String>['string', 'null'],
      },
      'confidence': <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          for (final field in ProductRecognitionField.values)
            field.name: <String, Object?>{
              'type': <String>['number', 'null'],
              'minimum': 0,
              'maximum': 1,
            },
        },
      },
      'warnings': <String, Object?>{
        'type': 'array',
        'items': <String, Object?>{'type': 'string'},
      },
    },
    'required': <String>[
      'productName',
      'quantity',
      'unitPrice',
      'totalAmount',
      'categorySuggestion',
      'merchantName',
      'recognizedText',
      'confidence',
      'warnings',
    ],
  };
}
