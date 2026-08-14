import 'package:sqflite/sqflite.dart';

/// Reads SQLite schema metadata without reading financial application rows.
class ProductionSchemaAuditService {
  const ProductionSchemaAuditService();

  Future<ProductionSchemaAuditReport> inspect(DatabaseExecutor db) async {
    final versionRows = await db.rawQuery('PRAGMA user_version');
    final userVersion = _asInt(
      versionRows.isEmpty ? null : versionRows.first['user_version'],
    );

    final objectRows = await db.rawQuery('''
      SELECT type, name, tbl_name, sql
      FROM sqlite_master
      WHERE name NOT LIKE 'sqlite_%'
      ORDER BY type ASC, name ASC
    ''');

    final objects = objectRows
        .map(
          (row) => ProductionSchemaObject(
            type: row['type']?.toString() ?? '',
            name: row['name']?.toString() ?? '',
            tableName: row['tbl_name']?.toString() ?? '',
            sql: row['sql']?.toString(),
          ),
        )
        .where((object) => object.name.isNotEmpty)
        .toList(growable: false);

    final tables = <String, ProductionTableAudit>{};
    for (final object in objects.where((item) => item.type == 'table')) {
      final tableName = object.name;
      final tableArgument = _sqlStringLiteral(tableName);

      final columnRows = await db.rawQuery(
        'PRAGMA table_info($tableArgument)',
      );
      final columns = columnRows
          .map(
            (row) => <String, Object?>{
              'cid': _asInt(row['cid']),
              'name': row['name']?.toString() ?? '',
              'type': row['type']?.toString() ?? '',
              'not_null': _asInt(row['notnull']) != 0,
              'default_value': row['dflt_value']?.toString(),
              'primary_key_position': _asInt(row['pk']),
            },
          )
          .toList(growable: false);

      final foreignKeyRows = await db.rawQuery(
        'PRAGMA foreign_key_list($tableArgument)',
      );
      final foreignKeys = foreignKeyRows
          .map(
            (row) => <String, Object?>{
              'id': _asInt(row['id']),
              'sequence': _asInt(row['seq']),
              'parent_table': row['table']?.toString() ?? '',
              'from_column': row['from']?.toString() ?? '',
              'to_column': row['to']?.toString() ?? '',
              'on_update': row['on_update']?.toString() ?? '',
              'on_delete': row['on_delete']?.toString() ?? '',
              'match': row['match']?.toString() ?? '',
            },
          )
          .toList(growable: false);

      final indexRows = await db.rawQuery(
        'PRAGMA index_list($tableArgument)',
      );
      final indexes = <Map<String, Object?>>[];
      for (final indexRow in indexRows) {
        final indexName = indexRow['name']?.toString() ?? '';
        if (indexName.isEmpty) continue;

        final indexInfoRows = await db.rawQuery(
          'PRAGMA index_info(${_sqlStringLiteral(indexName)})',
        );
        indexes.add(<String, Object?>{
          'name': indexName,
          'unique': _asInt(indexRow['unique']) != 0,
          'origin': indexRow['origin']?.toString(),
          'partial': _asInt(indexRow['partial']) != 0,
          'columns': indexInfoRows
              .map(
                (row) => <String, Object?>{
                  'sequence': _asInt(row['seqno']),
                  'column_id': _asInt(row['cid']),
                  'name': row['name']?.toString() ?? '',
                },
              )
              .toList(growable: false),
        });
      }
      indexes.sort(
        (left, right) =>
            (left['name']?.toString() ?? '').compareTo(
              right['name']?.toString() ?? '',
            ),
      );

      tables[tableName] = ProductionTableAudit(
        name: tableName,
        columns: columns,
        indexes: indexes,
        foreignKeys: foreignKeys,
      );
    }

    final sequenceExists = await db.rawQuery('''
      SELECT name
      FROM sqlite_master
      WHERE type = 'table' AND name = 'sqlite_sequence'
      LIMIT 1
    ''');
    final sqliteSequence = sequenceExists.isEmpty
        ? const <Map<String, Object?>>[]
        : (await db.rawQuery(
            'SELECT name, seq FROM sqlite_sequence ORDER BY name ASC',
          ))
              .map(
                (row) => <String, Object?>{
                  'table_name': row['name']?.toString() ?? '',
                  'sequence': _asInt(row['seq']),
                },
              )
              .toList(growable: false);

    return ProductionSchemaAuditReport(
      userVersion: userVersion,
      objects: objects,
      tables: tables,
      sqliteSequence: sqliteSequence,
    );
  }
}

class ProductionSchemaAuditReport {
  const ProductionSchemaAuditReport({
    required this.userVersion,
    required this.objects,
    required this.tables,
    required this.sqliteSequence,
  });

  final int userVersion;
  final List<ProductionSchemaObject> objects;
  final Map<String, ProductionTableAudit> tables;
  final List<Map<String, Object?>> sqliteSequence;

  Map<String, Object?> toJson() => <String, Object?>{
        'user_version': userVersion,
        'objects': objects.map((object) => object.toJson()).toList(),
        'tables': <String, Object?>{
          for (final entry in tables.entries) entry.key: entry.value.toJson(),
        },
        'sqlite_sequence': sqliteSequence,
      };
}

class ProductionSchemaObject {
  const ProductionSchemaObject({
    required this.type,
    required this.name,
    required this.tableName,
    required this.sql,
  });

  final String type;
  final String name;
  final String tableName;
  final String? sql;

  Map<String, Object?> toJson() => <String, Object?>{
        'type': type,
        'name': name,
        'table_name': tableName,
        'sql': sql,
      };
}

class ProductionTableAudit {
  const ProductionTableAudit({
    required this.name,
    required this.columns,
    required this.indexes,
    required this.foreignKeys,
  });

  final String name;
  final List<Map<String, Object?>> columns;
  final List<Map<String, Object?>> indexes;
  final List<Map<String, Object?>> foreignKeys;

  Map<String, Object?> toJson() => <String, Object?>{
        'name': name,
        'columns': columns,
        'indexes': indexes,
        'foreign_keys': foreignKeys,
      };
}

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

String _sqlStringLiteral(String value) {
  return "'${value.replaceAll("'", "''")}'";
}
