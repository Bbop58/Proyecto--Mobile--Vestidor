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
      version: 3,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _createWalletTables(db);
    }
    if (oldVersion < 3) {
      try {
        await db.execute('ALTER TABLE cached_products ADD COLUMN precio_oferta REAL;');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE cached_products ADD COLUMN en_oferta INTEGER DEFAULT 0;');
      } catch (_) {}
      await _createFavoriteTables(db);
    }
  }

  Future<void> _createFavoriteTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS local_favorites (
        product_id TEXT PRIMARY KEY,
        user_id TEXT,
        product_json TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
  }

  Future<void> _createWalletTables(Database db) async {
    // 4. Billetera virtual prepago local (Plan 14)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS local_wallet (
        user_id TEXT PRIMARY KEY,
        saldo REAL NOT NULL DEFAULT 0.0,
        nonce INTEGER NOT NULL DEFAULT 0,
        firma TEXT,
        moneda TEXT DEFAULT 'BOB',
        updated_at TEXT
      )
    ''');

    // 5. Historial de transacciones de billetera cacheadas localmente
    await db.execute('''
      CREATE TABLE IF NOT EXISTS local_wallet_transactions (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        tipo TEXT NOT NULL,
        monto REAL NOT NULL,
        saldo_anterior REAL,
        saldo_posterior REAL,
        descripcion TEXT,
        fecha TEXT NOT NULL
      )
    ''');

    // 6. Cola específica de órdenes pagadas con saldo wallet offline
    await db.execute('''
      CREATE TABLE IF NOT EXISTS offline_wallet_orders (
        client_operation_id TEXT PRIMARY KEY,
        cliente_id TEXT,
        sucursal_id TEXT NOT NULL,
        monto_total REAL NOT NULL,
        nonce_usado INTEGER,
        firma_usada TEXT,
        items_json TEXT NOT NULL,
        fecha_local TEXT NOT NULL,
        status TEXT DEFAULT 'PENDIENTE',
        server_receipt TEXT,
        error_detail TEXT,
        created_at TEXT NOT NULL
      )
    ''');
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

    // 2. Catálogo de productos y variantes (con soporte de ofertas)
    await db.execute('''
      CREATE TABLE cached_products (
        id TEXT PRIMARY KEY,
        nombre TEXT NOT NULL,
        categoria TEXT,
        precio_base REAL NOT NULL,
        precio_oferta REAL,
        en_oferta INTEGER DEFAULT 0,
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

    await _createWalletTables(db);
    await _createFavoriteTables(db);
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
          'precio_oferta': p['precio_oferta'] != null ? (p['precio_oferta'] as num).toDouble() : null,
          'en_oferta': (p['en_oferta'] == true || p['en_oferta'] == 1) ? 1 : 0,
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

  // ── FAVORITOS (WISHLIST) OFFLINE ──
  Future<void> saveLocalFavorite(String productId, String? userId, String productJson) async {
    final db = await instance.database;
    await db.insert(
      'local_favorites',
      {
        'product_id': productId,
        'user_id': userId ?? '',
        'product_json': productJson,
        'created_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> removeLocalFavorite(String productId) async {
    final db = await instance.database;
    await db.delete('local_favorites', where: 'product_id = ?', whereArgs: [productId]);
  }

  Future<List<Map<String, dynamic>>> getLocalFavorites([String? userId]) async {
    final db = await instance.database;
    if (userId != null && userId.isNotEmpty) {
      return await db.query('local_favorites', where: 'user_id = ? OR user_id = ""', whereArgs: [userId]);
    }
    return await db.query('local_favorites');
  }

  Future<bool> isLocalFavorite(String productId) async {
    final db = await instance.database;
    final res = await db.query('local_favorites', where: 'product_id = ?', whereArgs: [productId]);
    return res.isNotEmpty;
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

  // ── BILLETERA VIRTUAL Y TRANSACCIONES LOCALES (PLAN 14) ──
  Future<void> saveLocalWallet({
    required String userId,
    required double saldo,
    required int nonce,
    required String firma,
    String moneda = 'BOB',
  }) async {
    final db = await instance.database;
    await db.insert(
      'local_wallet',
      {
        'user_id': userId,
        'saldo': saldo,
        'nonce': nonce,
        'firma': firma,
        'moneda': moneda,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, dynamic>?> getLocalWallet(String userId) async {
    final db = await instance.database;
    final results = await db.query(
      'local_wallet',
      where: 'user_id = ?',
      whereArgs: [userId],
      limit: 1,
    );
    if (results.isNotEmpty) return results.first;
    return null;
  }

  Future<void> updateLocalWalletBalance({
    required String userId,
    required double nuevoSaldo,
    required int nuevoNonce,
  }) async {
    final db = await instance.database;
    await db.update(
      'local_wallet',
      {
        'saldo': nuevoSaldo,
        'nonce': nuevoNonce,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'user_id = ?',
      whereArgs: [userId],
    );
  }

  Future<void> saveLocalWalletTransactions(List<Map<String, dynamic>> txs) async {
    final db = await instance.database;
    final batch = db.batch();
    for (final tx in txs) {
      batch.insert(
        'local_wallet_transactions',
        {
          'id': tx['id'],
          'user_id': tx['user_id'] ?? '',
          'tipo': tx['tipo'],
          'monto': (tx['monto'] as num).toDouble(),
          'saldo_anterior': (tx['saldo_anterior'] as num?)?.toDouble() ?? 0.0,
          'saldo_posterior': (tx['saldo_posterior'] as num?)?.toDouble() ?? 0.0,
          'descripcion': tx['descripcion'] ?? '',
          'fecha': tx['created_at'] ?? tx['fecha'] ?? DateTime.now().toUtc().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> getLocalWalletTransactions(String userId) async {
    final db = await instance.database;
    return await db.query(
      'local_wallet_transactions',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'fecha DESC',
    );
  }

  Future<void> insertOfflineWalletOrder(Map<String, dynamic> order) async {
    final db = await instance.database;
    await db.insert(
      'offline_wallet_orders',
      order,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getPendingOfflineWalletOrders() async {
    final db = await instance.database;
    return await db.query(
      'offline_wallet_orders',
      where: 'status = ?',
      whereArgs: ['PENDIENTE'],
      orderBy: 'created_at ASC',
    );
  }

  Future<void> updateOfflineWalletOrderStatus(String clientOpId, {
    required String status,
    String? serverReceipt,
    String? errorDetail,
  }) async {
    final db = await instance.database;
    await db.update(
      'offline_wallet_orders',
      {
        'status': status,
        'server_receipt': serverReceipt,
        'error_detail': errorDetail,
      },
      where: 'client_operation_id = ?',
      whereArgs: [clientOpId],
    );
  }
}
