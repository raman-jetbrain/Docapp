import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();

  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('app.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(path, version: 1, onCreate: _createDB);
  }

  Future _createDB(Database db, int version) async {
    const idType = 'INTEGER PRIMARY KEY AUTOINCREMENT';
    const textType = 'TEXT NOT NULL';
    const textNullable = 'TEXT';
    const blobNullable = 'BLOB';

    await db.execute('''
      CREATE TABLE customers (
        id $idType,
        name $textType,
        phone $textType,
        email $textNullable,
        address $textNullable,
        dob $textNullable,
        gender $textNullable,
        image $blobNullable
      )
    ''');

    await db.execute('''
      CREATE TABLE custom_entries (
        id $idType,
        customer_id INTEGER,
        type TEXT NOT NULL,
        detail TEXT NOT NULL,
        FOREIGN KEY (customer_id) REFERENCES customers (id) ON DELETE CASCADE
      )
    ''');
  }

  Future<int> insertCustomer(Map<String, dynamic> row) async {
    final db = await instance.database;
    return await db.insert('customers', row);
  }

  Future<int> insertCustomEntry(Map<String, dynamic> row) async {
    final db = await instance.database;
    return await db.insert('custom_entries', row);
  }

  Future<List<Map<String, dynamic>>> getCustomEntries(int customerId) async {
    final db = await instance.database;
    return await db.query('custom_entries', where: 'customer_id = ?', whereArgs: [customerId]);
  }

  Future close() async {
    final db = await instance.database;
    db.close();
  }
}