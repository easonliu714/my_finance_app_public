import 'dart:math' as math;

import 'package:sqflite/sqflite.dart';

import 'canonical_cloud_invoice_persistence_codec.dart';
import '../cloud_invoice_candidate.dart';

const Set<String> supportedOfficialInvoiceCategories = <String>{
  '早餐',
  '午餐',
  '晚餐',
  '飲料水果',
  '捷運',
  '客運',
  '家居百貨',
  '電子數碼',
  '手續費',
  '電影',
};

class OfficialInvoiceCategorySuggestionInput {
  const OfficialInvoiceCategorySuggestionInput({
    required this.id,
    required this.invoiceDate,
    required this.sellerIdentifier,
    required this.sellerName,
    required this.lineItems,
  });

  final String id;
  final DateTime invoiceDate;
  final String sellerIdentifier;
  final String sellerName;
  final List<CloudInvoiceLineItem> lineItems;
}

class OfficialInvoiceCategorySuggestion {
  const OfficialInvoiceCategorySuggestion({
    required this.category,
    required this.confidence,
    required this.reasons,
    required this.historyEvidenceCount,
  });

  final String? category;
  final double confidence;
  final List<String> reasons;
  final int historyEvidenceCount;

  bool get canPrefill => category != null && confidence >= 0.65;
}

class OfficialInvoiceCategorySuggestionService {
  const OfficialInvoiceCategorySuggestionService({
    this.referenceTime,
  });

  final DateTime? referenceTime;

  Future<Map<String, OfficialInvoiceCategorySuggestion>> suggestMany(
    DatabaseExecutor db,
    List<OfficialInvoiceCategorySuggestionInput> inputs,
  ) async {
    if (inputs.isEmpty) return const {};
    final rows = await db.rawQuery('''
      SELECT
        t.category,
        m.seller_identifier,
        m.seller_name,
        m.line_items_json,
        m.created_at
      FROM cloud_invoice_metadata_links m
      JOIN transactions t ON t.id = m.transaction_id
      ORDER BY m.created_at DESC
      LIMIT 500
    ''');
    final history = rows
        .map(_HistoricalCategoryEvidence.fromRow)
        .where(
          (item) => supportedOfficialInvoiceCategories.contains(
            item.category.trim(),
          ),
        )
        .toList(growable: false);
    final resolvedReferenceTime = (referenceTime ?? DateTime.now()).toUtc();
    return <String, OfficialInvoiceCategorySuggestion>{
      for (final input in inputs)
        input.id: _suggest(
          input,
          history,
          referenceTime: resolvedReferenceTime,
        ),
    };
  }

  OfficialInvoiceCategorySuggestion suggestWithoutHistory(
    OfficialInvoiceCategorySuggestionInput input,
  ) {
    return _suggest(
      input,
      const <_HistoricalCategoryEvidence>[],
      referenceTime: (referenceTime ?? input.invoiceDate).toUtc(),
    );
  }

  OfficialInvoiceCategorySuggestion _suggest(
    OfficialInvoiceCategorySuggestionInput input,
    List<_HistoricalCategoryEvidence> history, {
    required DateTime referenceTime,
  }) {
    final currentKeywords = _keywordsFor(
      '${input.sellerName} ${input.lineItems.map((item) => item.name).join(' ')}',
    );
    final heuristic = _heuristic(input, currentKeywords);
    final normalizedSeller = _normalize(input.sellerName);
    final sellerIdentifier = input.sellerIdentifier.trim();
    final scoreByCategory = <String, double>{};
    final countByCategory = <String, int>{};

    for (final evidence in history) {
      final sameIdentifier = sellerIdentifier.isNotEmpty &&
          evidence.sellerIdentifier.isNotEmpty &&
          sellerIdentifier == evidence.sellerIdentifier;
      final sameSeller = normalizedSeller.isNotEmpty &&
          normalizedSeller == evidence.normalizedSellerName;
      final keywordOverlap =
          currentKeywords.intersection(evidence.keywords).length;
      if (!sameIdentifier && !sameSeller && keywordOverlap == 0) continue;

      var weight = 0.0;
      if (sameIdentifier) weight += 3.0;
      if (sameSeller) weight += 1.5;
      weight += math.min(3, keywordOverlap) * 0.8;
      weight *= _recencyWeight(evidence.createdAt, referenceTime);
      scoreByCategory.update(
        evidence.category,
        (value) => value + weight,
        ifAbsent: () => weight,
      );
      countByCategory.update(
        evidence.category,
        (value) => value + 1,
        ifAbsent: () => 1,
      );
    }

    String? historicalCategory;
    var historicalConfidence = 0.0;
    var historyCount = 0;
    if (scoreByCategory.isNotEmpty) {
      final ranking = scoreByCategory.entries.toList()
        ..sort((left, right) => right.value.compareTo(left.value));
      final top = ranking.first;
      final second = ranking.length > 1 ? ranking[1].value : 0.0;
      historicalCategory = top.key;
      historyCount = countByCategory[top.key] ?? 0;
      final leadRatio = top.value / math.max(1.0, second);
      historicalConfidence = math
          .min(
            0.94,
            0.56 +
                math.min(0.24, top.value / 24) +
                (historyCount >= 2 ? 0.08 : 0) +
                (leadRatio >= 1.5 ? 0.06 : 0),
          )
          .toDouble();
    }

    String? category = heuristic?.category;
    var confidence = heuristic?.confidence ?? 0.0;
    final reasons = <String>[...?heuristic?.reasons];

    if (historicalCategory != null) {
      if (category == null) {
        category = historicalCategory;
        confidence = historicalConfidence;
      } else if (category == historicalCategory) {
        confidence = math
            .min(0.97, math.max(confidence, historicalConfidence) + 0.08)
            .toDouble();
      } else {
        confidence = math.min(confidence, 0.59).toDouble();
        reasons.add('品項規則與過往紀錄不同，保留人工判斷');
      }
      if (category == historicalCategory && historyCount > 0) {
        reasons.add('參考 $historyCount 筆相似歷史交易');
        reasons.add('近期歷史紀錄權重較高');
      }
    }

    if (category == null) {
      return const OfficialInvoiceCategorySuggestion(
        category: null,
        confidence: 0,
        reasons: <String>['目前沒有足夠證據，請人工選擇分類'],
        historyEvidenceCount: 0,
      );
    }
    return OfficialInvoiceCategorySuggestion(
      category: category,
      confidence: confidence.clamp(0.0, 1.0).toDouble(),
      reasons: List<String>.unmodifiable(reasons.toSet()),
      historyEvidenceCount: historyCount,
    );
  }

  _RuleSuggestion? _heuristic(
    OfficialInvoiceCategorySuggestionInput input,
    Set<String> keywords,
  ) {
    if (_containsAny(keywords, const {'手續費', '服務費', '處理費'})) {
      return const _RuleSuggestion(
        '手續費',
        0.88,
        <String>['品項包含費用類關鍵字'],
      );
    }
    if (_containsAny(keywords, const {'電影', '影城', '電影票', 'netflix'})) {
      return const _RuleSuggestion(
        '電影',
        0.82,
        <String>['品項或商家符合影視娛樂'],
      );
    }
    if (_containsAny(keywords, const {'捷運', 'metro', '悠遊卡'})) {
      return const _RuleSuggestion(
        '捷運',
        0.84,
        <String>['品項或商家符合捷運交通'],
      );
    }
    if (_containsAny(
      keywords,
      const {'客運', '公車', '高鐵', '台鐵', 'uber', '計程車'},
    )) {
      return const _RuleSuggestion(
        '客運',
        0.78,
        <String>['品項或商家符合交通服務'],
      );
    }
    if (_containsAny(
      keywords,
      const {'googleplay', 'google play', 'app', '軟體', '數位', '3c', '充電線', '耳機'},
    )) {
      return const _RuleSuggestion(
        '電子數碼',
        0.8,
        <String>['品項或商家符合數位／電子消費'],
      );
    }
    if (_containsAny(
      keywords,
      const {'衛生紙', '清潔', '洗衣', '牙膏', '垃圾袋', '家用品', '日用品'},
    )) {
      return const _RuleSuggestion(
        '家居百貨',
        0.76,
        <String>['品項符合日用或居家用品'],
      );
    }

    final hasFood = _containsAny(
      keywords,
      const {
        '飯', '麵', '粥', '湯', '便當', '餐', '漢堡', '雞', '豬', '牛', '魚',
        '蛋', '沙拉', '麵包', '三明治', '水餃', '鍋', '壽司', '滷味', '餅',
      },
    );
    final hasDrink = _containsAny(
      keywords,
      const {
        '茶', '咖啡', '飲料', '果汁', '牛奶', '豆漿', '水果', '可樂',
      },
    );
    if (hasFood) {
      final hour = input.invoiceDate.toLocal().hour;
      if (hour >= 4 && hour < 11) {
        return const _RuleSuggestion(
          '早餐',
          0.8,
          <String>['品項符合餐飲', '交易時間落在早餐時段'],
        );
      }
      if (hour >= 11 && hour < 15) {
        return const _RuleSuggestion(
          '午餐',
          0.8,
          <String>['品項符合餐飲', '交易時間落在午餐時段'],
        );
      }
      if (hour >= 17 && hour < 23) {
        return const _RuleSuggestion(
          '晚餐',
          0.8,
          <String>['品項符合餐飲', '交易時間落在晚餐時段'],
        );
      }
      return const _RuleSuggestion(
        '午餐',
        0.58,
        <String>['品項符合餐飲，但交易時間不在主要餐期'],
      );
    }
    if (hasDrink) {
      return const _RuleSuggestion(
        '飲料水果',
        0.75,
        <String>['品項符合飲料或水果'],
      );
    }
    return null;
  }

  bool _containsAny(Set<String> values, Set<String> expected) {
    return values.any(expected.contains);
  }
}

class _RuleSuggestion {
  const _RuleSuggestion(this.category, this.confidence, this.reasons);

  final String category;
  final double confidence;
  final List<String> reasons;
}

class _HistoricalCategoryEvidence {
  const _HistoricalCategoryEvidence({
    required this.category,
    required this.sellerIdentifier,
    required this.normalizedSellerName,
    required this.keywords,
    required this.createdAt,
  });

  factory _HistoricalCategoryEvidence.fromRow(Map<String, Object?> row) {
    final items = decodeCloudInvoiceLineItems(
      row['line_items_json'] as String? ?? '[]',
    );
    final sellerName = row['seller_name'] as String? ?? '';
    return _HistoricalCategoryEvidence(
      category: row['category'] as String? ?? '',
      sellerIdentifier: (row['seller_identifier'] as String? ?? '').trim(),
      normalizedSellerName: _normalize(sellerName),
      keywords: _keywordsFor(
        '$sellerName ${items.map((item) => item.name).join(' ')}',
      ),
      createdAt: DateTime.tryParse(row['created_at'] as String? ?? '')?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  final String category;
  final String sellerIdentifier;
  final String normalizedSellerName;
  final Set<String> keywords;
  final DateTime createdAt;
}

double _recencyWeight(DateTime createdAt, DateTime referenceTime) {
  final age = referenceTime.toUtc().difference(createdAt.toUtc());
  final ageDays = math.max(0, age.inDays);
  if (ageDays <= 30) return 1.0;
  if (ageDays <= 90) return 0.85;
  if (ageDays <= 180) return 0.7;
  if (ageDays <= 365) return 0.5;
  if (ageDays <= 730) return 0.3;
  return 0.15;
}

const Set<String> _keywordVocabulary = <String>{
  '手續費', '服務費', '處理費', '電影', '影城', '電影票', 'netflix',
  '捷運', 'metro', '悠遊卡', '客運', '公車', '高鐵', '台鐵', 'uber', '計程車',
  'googleplay', 'google play', 'app', '軟體', '數位', '3c', '充電線', '耳機',
  '衛生紙', '清潔', '洗衣', '牙膏', '垃圾袋', '家用品', '日用品',
  '飯', '麵', '粥', '湯', '便當', '餐', '漢堡', '雞', '豬', '牛', '魚',
  '蛋', '沙拉', '麵包', '三明治', '水餃', '鍋', '壽司', '滷味', '餅',
  '茶', '咖啡', '飲料', '果汁', '牛奶', '豆漿', '水果', '可樂',
};

Set<String> _keywordsFor(String value) {
  final normalized = _normalize(value);
  return <String>{
    for (final keyword in _keywordVocabulary)
      if (normalized.contains(_normalize(keyword))) keyword,
  };
}

String _normalize(String value) {
  return value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9一-鿿]+'), '');
}
