import 'dart:convert';

import 'package:my_finance_app/features/invoice/invoice_award_official_dataset.dart';

/// Durable, deterministic representation of one validated official dataset.
///
/// This contract intentionally does not choose a production database or mutate
/// any schema. Adapters may persist [payload] as opaque UTF-8 bytes only after
/// the dataset has passed the canonical validator.
class OfficialInvoiceAwardLkgSnapshot {
  const OfficialInvoiceAwardLkgSnapshot({
    required this.periodId,
    required this.payload,
  });

  final String periodId;
  final String payload;
}

abstract interface class OfficialInvoiceAwardLkgRepository {
  Future<OfficialInvoiceAwardLkgSnapshot?> read(String periodId);

  Future<void> replaceValidated(OfficialInvoiceAwardLkgSnapshot snapshot);
}

class OfficialInvoiceAwardLkgCodec {
  const OfficialInvoiceAwardLkgCodec();

  static const int schemaVersion = 1;

  OfficialInvoiceAwardLkgSnapshot encode(
    OfficialInvoiceAwardDataset dataset,
    OfficialInvoiceAwardDatasetValidator validator,
  ) {
    if (!validator.validate(dataset).isValid) {
      throw const FormatException('Refusing to persist an invalid award dataset');
    }

    final rules = dataset.rules
        .map((rule) => <String, Object?>{
              'kind': rule.kind.name,
              'number': rule.number,
            })
        .toList(growable: false)
      ..sort((left, right) {
        final kindCompare = (left['kind']! as String)
            .compareTo(right['kind']! as String);
        if (kindCompare != 0) return kindCompare;
        return (left['number']! as String)
            .compareTo(right['number']! as String);
      });

    final payload = jsonEncode(<String, Object?>{
      'schemaVersion': schemaVersion,
      'period': <String, Object?>{
        'rocYear': dataset.period.rocYear,
        'startMonth': dataset.period.startMonth,
        'endMonth': dataset.period.endMonth,
      },
      'provenance': <String, Object?>{
        'sourceId': dataset.provenance.sourceId,
        'fetchedAt': dataset.provenance.fetchedAt.toUtc().toIso8601String(),
        'parserVersion': dataset.provenance.parserVersion,
        'contentSha256': dataset.provenance.contentSha256.toLowerCase(),
      },
      'published': dataset.published,
      'complete': dataset.complete,
      'rules': rules,
    });

    return OfficialInvoiceAwardLkgSnapshot(
      periodId: dataset.period.id,
      payload: payload,
    );
  }

  OfficialInvoiceAwardDataset decode(
    OfficialInvoiceAwardLkgSnapshot snapshot,
    OfficialInvoiceAwardDatasetValidator validator,
  ) {
    final root = jsonDecode(snapshot.payload);
    if (root is! Map<String, dynamic> || root['schemaVersion'] != schemaVersion) {
      throw const FormatException('Unsupported award snapshot schema');
    }

    final periodJson = _map(root['period'], 'period');
    final provenanceJson = _map(root['provenance'], 'provenance');
    final rulesJson = root['rules'];
    if (rulesJson is! List) {
      throw const FormatException('Invalid award snapshot rules');
    }

    final period = OfficialInvoiceAwardPeriod(
      rocYear: _integer(periodJson['rocYear'], 'rocYear'),
      startMonth: _integer(periodJson['startMonth'], 'startMonth'),
      endMonth: _integer(periodJson['endMonth'], 'endMonth'),
    );
    if (period.id != snapshot.periodId) {
      throw const FormatException('Award snapshot period mismatch');
    }

    final rules = rulesJson.map((raw) {
      final ruleJson = _map(raw, 'rule');
      final kindName = ruleJson['kind'];
      final number = ruleJson['number'];
      if (kindName is! String || number is! String) {
        throw const FormatException('Invalid award snapshot rule');
      }
      final kind = OfficialInvoiceAwardRuleKind.values
          .where((candidate) => candidate.name == kindName)
          .firstOrNull;
      if (kind == null) {
        throw const FormatException('Unknown award rule kind');
      }
      return OfficialInvoiceAwardRule(kind: kind, number: number);
    }).toList(growable: false);

    final fetchedAtRaw = provenanceJson['fetchedAt'];
    if (fetchedAtRaw is! String) {
      throw const FormatException('Invalid fetchedAt');
    }
    final fetchedAt = DateTime.tryParse(fetchedAtRaw);
    if (fetchedAt == null || !fetchedAt.isUtc) {
      throw const FormatException('Invalid fetchedAt');
    }

    final dataset = OfficialInvoiceAwardDataset(
      period: period,
      provenance: OfficialInvoiceAwardProvenance(
        sourceId: _string(provenanceJson['sourceId'], 'sourceId'),
        fetchedAt: fetchedAt,
        parserVersion: _string(provenanceJson['parserVersion'], 'parserVersion'),
        contentSha256:
            _string(provenanceJson['contentSha256'], 'contentSha256'),
      ),
      rules: rules,
      published: _boolean(root['published'], 'published'),
      complete: _boolean(root['complete'], 'complete'),
    );
    if (!validator.validate(dataset).isValid) {
      throw const FormatException('Invalid decoded award dataset');
    }
    return dataset;
  }

  Map<String, dynamic> _map(Object? value, String field) {
    if (value is! Map<String, dynamic>) {
      throw FormatException('Invalid $field');
    }
    return value;
  }

  int _integer(Object? value, String field) {
    if (value is! int) throw FormatException('Invalid $field');
    return value;
  }

  String _string(Object? value, String field) {
    if (value is! String || value.isEmpty) {
      throw FormatException('Invalid $field');
    }
    return value;
  }

  bool _boolean(Object? value, String field) {
    if (value is! bool) throw FormatException('Invalid $field');
    return value;
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
