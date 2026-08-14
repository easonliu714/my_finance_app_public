import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'gemini_invoice_review.dart';

abstract interface class GeminiInvoiceReviewPort {
  Future<GeminiInvoiceReviewCandidate> review({
    required String apiKey,
    required String model,
    required Uint8List imageBytes,
    required String mimeType,
    Map<String, Object?> localSummary = const <String, Object?>{},
  });
}

enum GeminiInvoiceReviewFailureKind {
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

class GeminiInvoiceReviewException implements Exception {
  const GeminiInvoiceReviewException(
    this.kind,
    this.message, {
    this.statusCode,
  });

  final GeminiInvoiceReviewFailureKind kind;
  final String message;
  final int? statusCode;

  bool get retryWithNextKey {
    switch (kind) {
      case GeminiInvoiceReviewFailureKind.authentication:
      case GeminiInvoiceReviewFailureKind.quota:
      case GeminiInvoiceReviewFailureKind.serviceUnavailable:
      case GeminiInvoiceReviewFailureKind.timeout:
      case GeminiInvoiceReviewFailureKind.network:
        return true;
      case GeminiInvoiceReviewFailureKind.invalidInput:
      case GeminiInvoiceReviewFailureKind.requestRejected:
      case GeminiInvoiceReviewFailureKind.safetyBlocked:
      case GeminiInvoiceReviewFailureKind.malformedResponse:
        return false;
    }
  }

  @override
  String toString() => message;
}

class GeminiInvoiceReviewClient implements GeminiInvoiceReviewPort {
  GeminiInvoiceReviewClient({
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
  Future<GeminiInvoiceReviewCandidate> review({
    required String apiKey,
    required String model,
    required Uint8List imageBytes,
    required String mimeType,
    Map<String, Object?> localSummary = const <String, Object?>{},
  }) async {
    final key = apiKey.trim();
    final normalizedModel = model.trim().replaceFirst(RegExp(r'^models/'), '');
    final normalizedMime = mimeType.trim().toLowerCase();

    if (key.isEmpty) {
      throw const GeminiInvoiceReviewException(
        GeminiInvoiceReviewFailureKind.invalidInput,
        'Gemini API Key 為空白。',
      );
    }
    if (normalizedModel.isEmpty) {
      throw const GeminiInvoiceReviewException(
        GeminiInvoiceReviewFailureKind.invalidInput,
        'Gemini 模型名稱為空白。',
      );
    }
    if (imageBytes.isEmpty || imageBytes.length > maximumInlineImageBytes) {
      throw GeminiInvoiceReviewException(
        GeminiInvoiceReviewFailureKind.invalidInput,
        imageBytes.isEmpty ? '待覆核影像為空白。' : '待覆核影像超過安全上限。',
      );
    }
    if (!_supportedMimeTypes.contains(normalizedMime)) {
      throw const GeminiInvoiceReviewException(
        GeminiInvoiceReviewFailureKind.invalidInput,
        '待覆核影像格式不支援。',
      );
    }

    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/'
      '$normalizedModel:generateContent',
    );
    final generationConfig = <String, Object?>{
      'temperature': 0,
      'maxOutputTokens': 4096,
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
            <String, Object?>{'text': _prompt(localSummary)},
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
      throw const GeminiInvoiceReviewException(
        GeminiInvoiceReviewFailureKind.timeout,
        'Gemini 發票覆核連線逾時。',
      );
    } on http.ClientException {
      throw const GeminiInvoiceReviewException(
        GeminiInvoiceReviewFailureKind.network,
        'Gemini 發票覆核網路連線失敗。',
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _httpFailure(response.statusCode, response.body);
    }

    final decoded = _decodeObject(response.body);
    final text = _candidateText(decoded);
    final candidateJson = _decodeObject(text);
    final candidate = GeminiInvoiceReviewCandidate.fromJson(candidateJson);
    if (!candidate.hasAnyRecognizedValue) {
      throw const GeminiInvoiceReviewException(
        GeminiInvoiceReviewFailureKind.malformedResponse,
        'Gemini 未回傳可供覆核的發票欄位。',
      );
    }
    return candidate;
  }

  GeminiInvoiceReviewException _httpFailure(int statusCode, String body) {
    final detail = _safeGoogleErrorDetail(body);
    if (statusCode == 401 || statusCode == 403) {
      return GeminiInvoiceReviewException(
        GeminiInvoiceReviewFailureKind.authentication,
        detail.isEmpty
            ? 'Gemini API Key 未通過驗證或沒有模型權限。'
            : 'Gemini 權限驗證失敗：$detail',
        statusCode: statusCode,
      );
    }
    if (statusCode == 429) {
      return GeminiInvoiceReviewException(
        GeminiInvoiceReviewFailureKind.quota,
        detail.isEmpty
            ? 'Gemini API Key 已達配額或頻率限制。'
            : 'Gemini 配額或頻率限制：$detail',
        statusCode: statusCode,
      );
    }
    if (statusCode == 408 || statusCode >= 500) {
      return GeminiInvoiceReviewException(
        GeminiInvoiceReviewFailureKind.serviceUnavailable,
        detail.isEmpty
            ? 'Gemini 服務暫時無法完成發票覆核。'
            : 'Gemini 服務暫時無法完成覆核：$detail',
        statusCode: statusCode,
      );
    }
    return GeminiInvoiceReviewException(
      GeminiInvoiceReviewFailureKind.requestRejected,
      detail.isEmpty
          ? 'Gemini 發票覆核要求被拒絕（HTTP $statusCode）。'
          : 'Gemini 發票覆核要求被拒絕（HTTP $statusCode）：$detail',
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
          final combined = <String>[
            if (status.isNotEmpty) status,
            if (message.isNotEmpty) message,
          ].join('：');
          return _boundSafeDetail(combined);
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
    throw const GeminiInvoiceReviewException(
      GeminiInvoiceReviewFailureKind.malformedResponse,
      'Gemini 回應不是有效的 JSON 物件。',
    );
  }

  String _candidateText(Map<String, Object?> response) {
    final candidates = response['candidates'];
    if (candidates is! List || candidates.isEmpty) {
      final promptFeedback = response['promptFeedback'];
      if (promptFeedback is Map &&
          promptFeedback['blockReason']?.toString().trim().isNotEmpty == true) {
        throw const GeminiInvoiceReviewException(
          GeminiInvoiceReviewFailureKind.safetyBlocked,
          'Gemini 安全政策未允許處理這張影像。',
        );
      }
      throw const GeminiInvoiceReviewException(
        GeminiInvoiceReviewFailureKind.malformedResponse,
        'Gemini 回應沒有候選結果。',
      );
    }

    final candidate = candidates.first;
    if (candidate is! Map) {
      throw const GeminiInvoiceReviewException(
        GeminiInvoiceReviewFailureKind.malformedResponse,
        'Gemini 候選結果格式不正確。',
      );
    }
    final content = candidate['content'];
    if (content is! Map) {
      throw const GeminiInvoiceReviewException(
        GeminiInvoiceReviewFailureKind.malformedResponse,
        'Gemini 候選內容格式不正確。',
      );
    }
    final parts = content['parts'];
    if (parts is! List) {
      throw const GeminiInvoiceReviewException(
        GeminiInvoiceReviewFailureKind.malformedResponse,
        'Gemini 候選內容沒有文字結果。',
      );
    }
    final text = parts
        .whereType<Map>()
        .map((part) => part['text']?.toString().trim() ?? '')
        .firstWhere((value) => value.isNotEmpty, orElse: () => '');
    if (text.isEmpty) {
      throw const GeminiInvoiceReviewException(
        GeminiInvoiceReviewFailureKind.malformedResponse,
        'Gemini 候選內容沒有可解析文字。',
      );
    }
    return text;
  }

  String _prompt(Map<String, Object?> localSummary) {
    final boundedSummary = <String, Object?>{
      for (final entry in localSummary.entries.take(20)) entry.key: entry.value,
    };
    return '''
你是台灣發票影像覆核器。只能根據影像中可見的證據填值，不得猜測、補齊、語意改寫或推導看不清楚的內容。

優先順序：
1. 發票號碼、期別與明確標示的 4 碼隨機碼。
2. 賣方統一編號。
3. 日期、時間、商家名稱、總金額。
4. 只有清楚可見時才列出品項。

規則：
- 不確定的欄位必須回傳 null；寧可留空，也不要用相似字或常見店名補值。
- 發票號碼必須是 2 個英文字母加 8 個數字。
- randomCode 只有在影像明確出現「隨機碼」標籤且其值完整可見為 4 位數時才填入；不得從其他 4 位數欄位猜測。
- merchantName 必須逐字抄錄影像上可見的商家名稱，不得自行正名或改寫。
- invoiceTime 必須逐位抄錄影像上可見的時間，格式 HH:mm:ss；秒數看不清楚時回傳 null，不得自行補成 00。
- sellerTaxId 優先使用「賣方」、「統編」或「統一編號」等明確標籤。不得把任意 NO./No. 號碼直接當成統編；但若 NO./No. 後是完整 8 碼、位於商家 identity header 附近，且上下文明確顯示它屬於商家身分資訊，可保留為 sellerTaxId 候選並在 warnings 說明證據來源。
- 日期使用 YYYY-MM-DD；不得把「115年5-6月份」這類發票期別誤當交易日期。
- 總金額必須優先使用總計／合計／總額／小計等總額語意，其次才是應付／實付；「現／收現／現金」屬付款投入證據，不得在較高優先總額證據存在時覆蓋總額。
- confidence 為 0 到 1，代表該欄位可見證據的可信度。
- warnings 只描述影像證據不足、欄位衝突、seller identity 來源或總額與品項不一致。

本機辨識完整度摘要（不代表正確答案）：${jsonEncode(boundedSummary)}
''';
  }

  static final Map<String, Object?> _responseSchema = <String, Object?>{
    'type': 'object',
    'properties': <String, Object?>{
      'invoiceNumber': <String, Object?>{
        'type': <String>['string', 'null'],
      },
      'invoicePeriod': <String, Object?>{
        'type': <String>['string', 'null'],
      },
      'randomCode': <String, Object?>{
        'type': <String>['string', 'null'],
      },
      'sellerTaxId': <String, Object?>{
        'type': <String>['string', 'null'],
      },
      'invoiceDate': <String, Object?>{
        'type': <String>['string', 'null'],
      },
      'invoiceTime': <String, Object?>{
        'type': <String>['string', 'null'],
      },
      'merchantName': <String, Object?>{
        'type': <String>['string', 'null'],
      },
      'totalAmount': <String, Object?>{
        'type': <String>['number', 'null'],
      },
      'lineItems': <String, Object?>{
        'type': 'array',
        'items': <String, Object?>{
          'type': 'object',
          'properties': <String, Object?>{
            'name': <String, Object?>{'type': 'string'},
            'quantity': <String, Object?>{
              'type': <String>['number', 'null'],
            },
            'unitPrice': <String, Object?>{
              'type': <String>['number', 'null'],
            },
            'amount': <String, Object?>{
              'type': <String>['number', 'null'],
            },
          },
          'required': <String>['name', 'quantity', 'unitPrice', 'amount'],
        },
      },
      'confidence': <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          for (final field in <String>[
            'invoiceNumber',
            'invoicePeriod',
            'randomCode',
            'sellerTaxId',
            'invoiceDate',
            'invoiceTime',
            'merchantName',
            'totalAmount',
            'lineItems',
          ])
            field: <String, Object?>{'type': 'number'},
        },
        'required': <String>[
          'invoiceNumber',
          'invoicePeriod',
          'randomCode',
          'sellerTaxId',
          'invoiceDate',
          'invoiceTime',
          'merchantName',
          'totalAmount',
          'lineItems',
        ],
      },
      'warnings': <String, Object?>{
        'type': 'array',
        'items': <String, Object?>{'type': 'string'},
      },
    },
    'required': <String>[
      'invoiceNumber',
      'invoicePeriod',
      'randomCode',
      'sellerTaxId',
      'invoiceDate',
      'invoiceTime',
      'merchantName',
      'totalAmount',
      'lineItems',
      'confidence',
      'warnings',
    ],
  };
}
