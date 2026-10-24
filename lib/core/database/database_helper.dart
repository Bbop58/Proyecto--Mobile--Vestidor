import 'dart:async';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('fashion_store_offline.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    // 1. Sucursales cacheadas
    await db.execute('''
      CREATE TABLE cached_branches (
        id TEXT PRIMARY KEY,
        nombre TEXT NOT NULL,
        ciudad TEXT,
        direccion TEXT,
        activa INTEGER DEFAULT 1
      )
    ''');

    // 2. Catálogo de productos y variantes
    await db.execute('''
      CREATE TABLE cached_products (
        id TEXT PRIMARY KEY,
        nombre TEXT NOT NULL,
        categoria TEXT,
        precio_base REAL NOT NULL,
        imagen_url TEXT,
        variantes_json TEXT
      )
    ''');

    // 3. Operaciones comerciales pendientes de sincronización (RNF04 / RNF05)
    await db.execute('''
      CREATE TABLE pending_operations (
        client_operation_id TEXT PRIMARY KEY,
        operation_type TEXT NOT NULL,
        sucursal_id TEXT NOT NULL,
        cajero_id TEXT,
        cliente_id TEXT,
        fecha_local TEXT NOT NULL,
        monto_total REAL NOT NULL,
        monto_recibido REAL,
        cambio REAL,
        metodo_pago TEXT DEFAULT 'EFECTIVO',
        notas TEXT,
        items_json TEXT NOT NULL,
        local_status TEXT NOT NULL, -- 'LOCAL_PENDIENTE', 'CONFIRMADA', 'RECHAZADA_POR_STOCK', 'CONFLICTO'
        server_receipt TEXT,
        server_entity_id TEXT,
        error_detail TEXT,
        created_at TEXT NOT NULL
      )
    ''');
  }

  // ── SUCURSALES ──
  Future<void> cacheBranches(List<Map<String, dynamic>> branches) async {
    final db = await instance.database;
    final batch = db.batch();
    for (final b in branches) {
      batch.insert(
        'cached_branches',
        {
          'id': b['id'],
          'nombre': b['nombre'],
          'ciudad': b['ciudad'] ?? '',
          'direccion': b['direccion'] ?? '',
          'activa': (b['activa'] == true || b['activa'] == 1) ? 1 : 0,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> getCachedBranches() async {
    final db = await instance.database;
    return await db.query('cached_branches', where: 'activa = 1');
  }

  // ── PRODUCTOS Y VARIANTES ──
  Future<void> cacheProducts(List<Map<String, dynamic>> products) async {
    final db = await instance.database;
    final batch = db.batch();
    for (final p in products) {
      batch.insert(
        'cached_products',
        {
          'id': p['id'],
          'nombre': p['nombre'],
          'categoria': p['categoria'] is Map ? p['categoria']['nombre'] : (p['categoria']?.toString() ?? ''),
          'precio_base': (p['precio_base'] as num).toDouble(),
          'imagen_url': p['imagen_url'] ?? '',
          'variantes_json': p['variantes_json'] ?? '[]',
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> getCachedProducts() async {
    final db = await instance.database;
    return await db.query('cached_products');
  }

  // ── OPERACIONES OFFLINE (VENTAS Y RESERVAS) ──
  Future<void> insertPendingOperation(Map<String, dynamic> op) async {
    final db = await instance.database;
    await db.insert(
      'pending_operations',
      op,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getPendingOperations() async {
    final db = await instance.database;
    return await db.query(
      'pending_operations',
      where: 'local_status = ?',
      whereArgs: ['LOCAL_PENDIENTE'],
      orderBy: 'created_at ASC',
    );
  }

  Future<List<Map<String, dynamic>>> getAllOperations() async {
    final db = await instance.database;
    return await db.query(
      'pending_operations',
      orderBy: 'created_at DESC',
    );
  }

  Future<void> updateOperationStatus(String clientOpId, Map<String, dynamic> updates) async {
    final db = await instance.database;
    await db.update(
      'pending_operations',
      updates,
      where: 'client_operation_id = ?',
      whereArgs: [clientOpId],
    );
  }

  Future<int> getPendingCount() async {
    final db = await instance.database;
    final count = Sqflite.firstIntValue(await db.rawQuery(
      'SELECT COUNT(*) FROM pending_operations WHERE local_status = ?',
      ['LOCAL_PENDIENTE'],
    ));
    return count ?? 0;
  }
}
