import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();

  static const databaseName = 'my_finance_app.db';
  static const databaseVersion = 1;

  Database? _database;

  Future<Database> get database async {
    final existing = _database;
    if (existing != null) return existing;

    final appDir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(appDir.path, databaseName);
    final opened = await openDatabase(
      dbPath,
      version: databaseVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: _onCreate,
    );
    _database = opened;
    return opened;
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE books (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        currency_code TEXT NOT NULL DEFAULT 'TWD',
        month_start_day INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE accounts (
        id TEXT PRIMARY KEY,
        book_id TEXT NOT NULL,
        name TEXT NOT NULL,
        type TEXT NOT NULL,
        balance REAL NOT NULL DEFAULT 0,
        initial_balance REAL NOT NULL DEFAULT 0,
        currency_code TEXT NOT NULL DEFAULT 'TWD',
        icon TEXT,
        color_hex TEXT,
        sort_order INTEGER NOT NULL DEFAULT 0,
        is_archived INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        FOREIGN KEY(book_id) REFERENCES books(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE categories (
        id TEXT PRIMARY KEY,
        book_id TEXT NOT NULL,
        parent_id TEXT,
        transaction_type TEXT NOT NULL,
        name TEXT NOT NULL,
        icon TEXT,
        color_hex TEXT,
        sort_order INTEGER NOT NULL DEFAULT 0,
        is_system INTEGER NOT NULL DEFAULT 0,
        is_archived INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        FOREIGN KEY(book_id) REFERENCES books(id) ON DELETE CASCADE,
        FOREIGN KEY(parent_id) REFERENCES categories(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE merchants (
        id TEXT PRIMARY KEY,
        book_id TEXT NOT NULL,
        name TEXT NOT NULL,
        normalized_name TEXT NOT NULL,
        address TEXT,
        latitude REAL,
        longitude REAL,
        place_provider TEXT NOT NULL DEFAULT 'manual',
        place_id TEXT,
        phone TEXT,
        note TEXT,
        use_count INTEGER NOT NULL DEFAULT 0,
        last_used_at TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        FOREIGN KEY(book_id) REFERENCES books(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE members (
        id TEXT PRIMARY KEY,
        book_id TEXT NOT NULL,
        name TEXT NOT NULL,
        avatar TEXT,
        is_default INTEGER NOT NULL DEFAULT 0,
        sort_order INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        FOREIGN KEY(book_id) REFERENCES books(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE tags (
        id TEXT PRIMARY KEY,
        book_id TEXT NOT NULL,
        name TEXT NOT NULL,
        color_hex TEXT,
        sort_order INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        FOREIGN KEY(book_id) REFERENCES books(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE transactions (
        id TEXT PRIMARY KEY,
        book_id TEXT NOT NULL,
        type TEXT NOT NULL,
        amount REAL NOT NULL,
        currency_code TEXT NOT NULL DEFAULT 'TWD',
        category_id TEXT,
        account_id TEXT,
        from_account_id TEXT,
        to_account_id TEXT,
        member_id TEXT,
        merchant_id TEXT,
        counterparty_name TEXT,
        note TEXT,
        transaction_time TEXT NOT NULL,
        reimbursable_flag INTEGER NOT NULL DEFAULT 0,
        reimbursement_status TEXT NOT NULL DEFAULT 'none',
        source TEXT NOT NULL DEFAULT 'manual',
        source_ref_id TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        FOREIGN KEY(book_id) REFERENCES books(id) ON DELETE CASCADE,
        FOREIGN KEY(category_id) REFERENCES categories(id),
        FOREIGN KEY(account_id) REFERENCES accounts(id),
        FOREIGN KEY(from_account_id) REFERENCES accounts(id),
        FOREIGN KEY(to_account_id) REFERENCES accounts(id),
        FOREIGN KEY(member_id) REFERENCES members(id),
        FOREIGN KEY(merchant_id) REFERENCES merchants(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE transaction_tags (
        transaction_id TEXT NOT NULL,
        tag_id TEXT NOT NULL,
        PRIMARY KEY(transaction_id, tag_id),
        FOREIGN KEY(transaction_id) REFERENCES transactions(id) ON DELETE CASCADE,
        FOREIGN KEY(tag_id) REFERENCES tags(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE budgets (
        id TEXT PRIMARY KEY,
        book_id TEXT NOT NULL,
        period_type TEXT NOT NULL,
        category_id TEXT,
        amount REAL NOT NULL,
        start_date TEXT NOT NULL,
        end_date TEXT,
        alert_threshold REAL NOT NULL DEFAULT 0.8,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        FOREIGN KEY(book_id) REFERENCES books(id) ON DELETE CASCADE,
        FOREIGN KEY(category_id) REFERENCES categories(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE recurring_rules (
        id TEXT PRIMARY KEY,
        book_id TEXT NOT NULL,
        name TEXT NOT NULL,
        transaction_template_json TEXT NOT NULL,
        frequency TEXT NOT NULL,
        interval_count INTEGER NOT NULL DEFAULT 1,
        start_date TEXT NOT NULL,
        end_date TEXT,
        next_run_at TEXT,
        auto_post INTEGER NOT NULL DEFAULT 0,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        FOREIGN KEY(book_id) REFERENCES books(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('CREATE INDEX idx_transactions_book_time ON transactions(book_id, transaction_time)');
    await db.execute('CREATE INDEX idx_transactions_type ON transactions(type)');
    await db.execute('CREATE INDEX idx_categories_book_type ON categories(book_id, transaction_type)');
    await db.execute('CREATE INDEX idx_accounts_book_type ON accounts(book_id, type)');
    await db.execute('CREATE INDEX idx_merchants_book_name ON merchants(book_id, normalized_name)');
  }
}
