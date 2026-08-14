import 'package:sqflite/sqflite.dart';

import '../features/transaction/taiwan_business_calendar.dart';
import 'production_schema_v16.dart';

const int canonicalProductionSchemaVersion = 17;

const String taiwanBusinessCalendarSourceUrl =
    'https://www.dgpa.gov.tw/informationlist?uid=41';

Future<void> createCanonicalProductionV17Tables(
  DatabaseExecutor db,
) async {
  await createCanonicalProductionV16Tables(db);
  await _createDebitCardProfilesTable(db);
  await _createDebitCardSettlementsTable(db);
  await _createTaiwanBusinessCalendarTable(db);
  await _seedTaiwanBusinessCalendar(db);
}

Future<void> _createDebitCardProfilesTable(DatabaseExecutor db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS debit_card_profiles (
      debit_card_account_id TEXT PRIMARY KEY,
      linked_bank_account_id TEXT NOT NULL,
      currency_code TEXT NOT NULL,
      settlement_business_days INTEGER NOT NULL DEFAULT 2,
      is_enabled INTEGER NOT NULL DEFAULT 1,
      created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      CHECK (debit_card_account_id <> linked_bank_account_id),
      CHECK (settlement_business_days >= 0),
      CHECK (is_enabled IN (0, 1)),
      FOREIGN KEY (debit_card_account_id)
        REFERENCES accounts(id) ON DELETE CASCADE,
      FOREIGN KEY (linked_bank_account_id)
        REFERENCES accounts(id) ON DELETE RESTRICT
    )
  ''');
  await db.execute('''
    CREATE INDEX IF NOT EXISTS idx_debit_card_profiles_linked_bank
    ON debit_card_profiles(linked_bank_account_id, is_enabled)
  ''');
}

Future<void> _createDebitCardSettlementsTable(DatabaseExecutor db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS debit_card_settlements (
      id TEXT PRIMARY KEY,
      debit_card_account_id TEXT NOT NULL,
      linked_bank_account_id TEXT NOT NULL,
      transaction_id TEXT NOT NULL UNIQUE,
      amount REAL NOT NULL,
      currency_code TEXT NOT NULL,
      authorized_at TEXT NOT NULL,
      expected_settlement_date TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'pending',
      terminal_at TEXT,
      failure_reason TEXT,
      settlement_transfer_transaction_id TEXT,
      created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      CHECK (amount > 0),
      CHECK (debit_card_account_id <> linked_bank_account_id),
      CHECK (status IN ('pending', 'confirmed', 'cancelled', 'failed')),
      CHECK (
        (status = 'pending' AND terminal_at IS NULL) OR
        (status <> 'pending' AND terminal_at IS NOT NULL)
      ),
      FOREIGN KEY (debit_card_account_id)
        REFERENCES accounts(id) ON DELETE RESTRICT,
      FOREIGN KEY (linked_bank_account_id)
        REFERENCES accounts(id) ON DELETE RESTRICT,
      FOREIGN KEY (transaction_id)
        REFERENCES transactions(id) ON DELETE RESTRICT,
      FOREIGN KEY (settlement_transfer_transaction_id)
        REFERENCES transactions(id) ON DELETE SET NULL
    )
  ''');
  await db.execute('''
    CREATE INDEX IF NOT EXISTS idx_debit_card_settlements_card_date
    ON debit_card_settlements(
      debit_card_account_id,
      expected_settlement_date DESC
    )
  ''');
  await db.execute('''
    CREATE INDEX IF NOT EXISTS idx_debit_card_settlements_bank_status
    ON debit_card_settlements(
      linked_bank_account_id,
      status,
      expected_settlement_date ASC
    )
  ''');
  await db.execute('''
    CREATE INDEX IF NOT EXISTS idx_debit_card_settlements_pending_due
    ON debit_card_settlements(status, expected_settlement_date ASC)
  ''');
}

Future<void> _createTaiwanBusinessCalendarTable(DatabaseExecutor db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS taiwan_business_calendar_days (
      calendar_date TEXT PRIMARY KEY,
      is_business_day INTEGER NOT NULL,
      day_label TEXT NOT NULL DEFAULT '',
      source_year INTEGER NOT NULL,
      source_revision TEXT NOT NULL,
      source_url TEXT NOT NULL,
      updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      CHECK (is_business_day IN (0, 1))
    )
  ''');
  await db.execute('''
    CREATE INDEX IF NOT EXISTS idx_taiwan_calendar_year_business
    ON taiwan_business_calendar_days(source_year, is_business_day, calendar_date)
  ''');
}

Future<void> _seedTaiwanBusinessCalendar(DatabaseExecutor db) async {
  const calendar = TaiwanBusinessCalendar.bundled();
  final batch = db.batch();
  var date = DateTime.utc(2026, 1, 1);
  final end = DateTime.utc(2027, 12, 31);

  while (!date.isAfter(end)) {
    final isBusinessDay = calendar.isBusinessDay(date);
    final isWeekend = date.weekday == DateTime.saturday ||
        date.weekday == DateTime.sunday;
    final year = date.year;
    batch.insert(
      'taiwan_business_calendar_days',
      <String, Object?>{
        'calendar_date': TaiwanBusinessCalendar.dateKey(date),
        'is_business_day': isBusinessDay ? 1 : 0,
        'day_label': isBusinessDay
            ? ''
            : isWeekend
                ? (date.weekday == DateTime.saturday ? '星期六' : '星期日')
                : '政府公告放假日或補假日',
        'source_year': year,
        'source_revision': year == 2026
            ? 'DGPA-115-2025-10-02'
            : 'DGPA-116-2026-05-21',
        'source_url': taiwanBusinessCalendarSourceUrl,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    date = date.add(const Duration(days: 1));
  }

  await batch.commit(noResult: true);
}
