import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static final scopeChanges = ValueNotifier<String?>(null);
  static String? get scope => scopeChanges.value;
  static void activateScope(String? value) {
    scopeChanges.value = value;
  }

  static final Map<String, Future<Database>> _databases = {};

  final String? _fixedScope;
  DatabaseHelper._init() : _fixedScope = null;
  DatabaseHelper._scoped(this._fixedScope);
  DatabaseHelper forScope(String owner) => DatabaseHelper._scoped(owner);

  Future<Database> get database async {
    final owner = _fixedScope ?? scope ?? 'anonymous';
    final safe = owner.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    return _databases.putIfAbsent(
      owner,
      () => _initDB('fashion_store_v2_$safe.db'),
    );
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 6,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if(oldVersion<6) {
      await _createFavoriteTables(db);
      final columns=await db.rawQuery('PRAGMA table_info(cached_products)');
      if(columns.isNotEmpty) {
        for(final name in ['categoria_id','temporada']) {
          if(!columns.any((row)=>row['name']==name)) await db.execute('ALTER TABLE cached_products ADD COLUMN $name TEXT');
        }
      }
    }
    if (oldVersion < 4) {
      // Check columns because version-1 upgrades create the current wallet tables.
      for (final entry in {'local_wallet': {'saldo_retenido': 'REAL NOT NULL DEFAULT 0.0'},
        'offline_wallet_orders': {'codigo_cupon': 'TEXT'}}.entries) {
        final columns = await db.rawQuery('PRAGMA table_info(${entry.key})');
        if (columns.isEmpty) continue;
        for (final column in entry.value.entries) {
          if (!columns.any((row) => row['name'] == column.key)) {
            await db.execute('ALTER TABLE ${entry.key} ADD COLUMN ${column.key} ${column.value}');
          }
        }
      }
    }
    if (oldVersion < 2) {
      await _createWalletTables(db);
    }
    if (oldVersion < 3) {
      try {
        await db.execute(
          'ALTER TABLE cached_products ADD COLUMN precio_oferta REAL;',
        );
      } catch (_) {}
      try {
        await db.execute(
          'ALTER TABLE cached_products ADD COLUMN en_oferta INTEGER DEFAULT 0;',
        );
      } catch (_) {}
      await _createFavoriteTables(db);
    }
    if (oldVersion < 5) {
      final additions = {
        'pending_operations': {'codigo_cupon': 'TEXT', 'fecha_hora_esperada': 'TEXT',
          'supersedes_operation_id': 'TEXT', 'replacement_id': 'TEXT', 'synced_at': 'TEXT'},
        'local_wallet': {'server_validated': 'INTEGER NOT NULL DEFAULT 0'}
      };
      for (final entry in additions.entries) {
        final columns = await db.rawQuery('PRAGMA table_info(${entry.key})');
        if (columns.isEmpty) continue;
        for (final column in entry.value.entries) {
          if (!columns.any((row) => row['name'] == column.key)) {
            await db.execute('ALTER TABLE ${entry.key} ADD COLUMN ${column.key} ${column.value}');
          }
        }
      }
    }
  }

  Future<void> _createFavoriteTables(Database db) async {
    await db.execute('CREATE TABLE IF NOT EXISTS favorite_mutations (product_id TEXT PRIMARY KEY, user_id TEXT NOT NULL, desired INTEGER NOT NULL, revision TEXT NOT NULL, product_json TEXT NOT NULL)');
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
        saldo_retenido REAL NOT NULL DEFAULT 0.0,
        server_validated INTEGER NOT NULL DEFAULT 0,
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
        codigo_cupon TEXT,
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
        categoria_id TEXT,
        temporada TEXT,
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
        codigo_cupon TEXT,
        fecha_hora_esperada TEXT,
        supersedes_operation_id TEXT,
        replacement_id TEXT,
        synced_at TEXT,
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
    final db = await database;
    final batch = db.batch();
    for (final b in branches) {
      batch.insert('cached_branches', {
        'id': b['id'],
        'nombre': b['nombre'],
        'ciudad': b['ciudad'] ?? '',
        'direccion': b['direccion'] ?? '',
        'activa': (b['activa'] == true || b['activa'] == 1) ? 1 : 0,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> getCachedBranches() async {
    final db = await database;
    return await db.query('cached_branches', where: 'activa = 1');
  }

  // ── PRODUCTOS Y VARIANTES ──
  Future<void> cacheProducts(List<Map<String, dynamic>> products,{bool replace=false}) async {
    final db = await database;
    final batch = db.batch();
    if(replace) batch.delete('cached_products');
    for (final p in products) {
      batch.insert('cached_products', {
        'id': p['id'],
        'nombre': p['nombre'],
        'categoria_id':p['categoria_id'],
        'temporada':p['temporada'],
        'categoria': p['categoria'] is Map
            ? p['categoria']['nombre']
            : (p['categoria']?.toString() ?? ''),
        'precio_base': (p['precio_base'] as num).toDouble(),
        'precio_oferta': p['precio_oferta'] != null
            ? (p['precio_oferta'] as num).toDouble()
            : null,
        'en_oferta': (p['en_oferta'] == true || p['en_oferta'] == 1) ? 1 : 0,
        'imagen_url': p['imagen_url'] ?? '',
        'variantes_json': p['variantes_json'] ?? '[]',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> getCachedProducts() async {
    final db = await database;
    return await db.query('cached_products');
  }

  // ── FAVORITOS (WISHLIST) OFFLINE ──
  Future<void> queueFavoriteChange(String user,Map<String,dynamic> product,bool desired,String revision) async {
    final db=await database;
    await db.transaction((tx) async {
      final id=product['id'];final encoded=jsonEncode(product);
      await tx.insert('favorite_mutations',{'product_id':id,'user_id':user,'desired':desired?1:0,'revision':revision,'product_json':encoded},conflictAlgorithm:ConflictAlgorithm.replace);
      if(desired) {
        await tx.insert('local_favorites',{'product_id':id,'user_id':user,'product_json':encoded,'created_at':DateTime.now().toUtc().toIso8601String()},conflictAlgorithm:ConflictAlgorithm.replace);
      } else { await tx.delete('local_favorites',where:'product_id=?',whereArgs:[id]); }
    });
  }

  Future<List<Map<String,dynamic>>> pendingFavoriteChanges(String user) async {
    final db=await database;return db.query('favorite_mutations',where:'user_id=?',whereArgs:[user]);
  }

  Future<void> acknowledgeFavoriteChange(String id,String revision) async {
    final db=await database;await db.delete('favorite_mutations',where:'product_id=? AND revision=?',whereArgs:[id,revision]);
  }

  Future<void> replaceFavoriteSnapshot(String user,List<Map<String,dynamic>> products) async {
    final db=await database;
    await db.transaction((tx) async {
      final pending=await tx.query('favorite_mutations',where:'user_id=?',whereArgs:[user]);
      final merged={for(final product in products) product['id']:jsonEncode(product)};
      for(final row in pending) {
        if(row['desired']==1) { merged[row['product_id']]=row['product_json'].toString(); }
        else { merged.remove(row['product_id']); }
      }
      await tx.delete('local_favorites');
      for(final entry in merged.entries) {
        await tx.insert('local_favorites',{'product_id':entry.key,'user_id':user,'product_json':entry.value,'created_at':DateTime.now().toUtc().toIso8601String()});
      }
    });
  }

  Future<void> saveLocalFavorite(
    String productId,
    String? userId,
    String productJson,
  ) async {
    final db = await database;
    await db.insert('local_favorites', {
      'product_id': productId,
      'user_id': userId ?? '',
      'product_json': productJson,
      'created_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> removeLocalFavorite(String productId) async {
    final db = await database;
    await db.delete(
      'local_favorites',
      where: 'product_id = ?',
      whereArgs: [productId],
    );
  }

  Future<List<Map<String, dynamic>>> getLocalFavorites([String? userId]) async {
    final db = await database;
    if (userId != null && userId.isNotEmpty) {
      return await db.query(
        'local_favorites',
        where: 'user_id = ? OR user_id = ?',
        whereArgs: [userId, ''],
      );
    }
    return await db.query('local_favorites');
  }

  Future<bool> isLocalFavorite(String productId) async {
    final db = await database;
    final res = await db.query(
      'local_favorites',
      where: 'product_id = ?',
      whereArgs: [productId],
    );
    return res.isNotEmpty;
  }

  // ── OPERACIONES OFFLINE (VENTAS Y RESERVAS) ──
  Future<void> insertPendingOperation(Map<String, dynamic> op) async {
    if ((_fixedScope ?? scope) == null) {
      throw StateError("Inicia sesión para registrar operaciones");
    }
    final db = await database;
    await db.transaction((transaction) async {
      final existing = await transaction.query('pending_operations',where:'client_operation_id = ?',whereArgs:[op['client_operation_id']]);
      if (existing.isNotEmpty) {
        if (_operationContent(existing.first) != _operationContent(op)) { throw StateError('El UUID local ya contiene otra operación'); }
      } else {
        await transaction.insert('pending_operations',op,conflictAlgorithm:ConflictAlgorithm.abort);
      }
    });
  }

  String _operationContent(Map<String,dynamic> row) => jsonEncode({for(final key in [
    'client_operation_id','operation_type','sucursal_id','cajero_id','cliente_id','fecha_local','monto_total',
    'monto_recibido','cambio','metodo_pago','codigo_cupon','fecha_hora_esperada','supersedes_operation_id','items_json'])
      key: ['monto_total','monto_recibido','cambio'].contains(key) && row[key] is num
        ? (row[key] as num).toDouble()
        : key=='metodo_pago' ? row[key] ?? 'EFECTIVO' : row[key]});

  Future<List<Map<String, dynamic>>> getPendingOperations() async {
    final db = await database;
    return await db.query(
      'pending_operations',
      where: 'local_status = ?',
      whereArgs: ['LOCAL_PENDIENTE'],
      orderBy: 'created_at ASC',
    );
  }

  Future<List<Map<String, dynamic>>> getAllOperations() async {
    final db = await database;
    return await db.query('pending_operations', orderBy: 'created_at DESC');
  }

  Future<void> updateOperationStatus(
    String clientOpId,
    Map<String, dynamic> updates,
  ) async {
    final db = await database;
    await db.update(
      'pending_operations',
      updates,
      where: 'client_operation_id = ?',
      whereArgs: [clientOpId],
    );
  }

  Future<int> getPendingCount() async {
    final db = await database;
    final count = Sqflite.firstIntValue(
      await db.rawQuery(
        'SELECT COUNT(*) FROM pending_operations WHERE local_status = ?',
        ['LOCAL_PENDIENTE'],
      ),
    );
    return count ?? 0;
  }

  // ── BILLETERA VIRTUAL Y TRANSACCIONES LOCALES (PLAN 14) ──
  Future<void> saveLocalWallet({
    required String userId,
    required double saldo,
    double saldoRetenido = 0,
    required int nonce,
    required String firma,
    String moneda = 'BOB',
  }) async {
    final db = await database;
    await db.transaction((transaction) async {
      final previous = await transaction.query('local_wallet',where:'user_id = ?',whereArgs:[userId]);
      if (previous.isNotEmpty && previous.first['server_validated'] == 1 &&
          (previous.first['nonce'] as num).toInt() > nonce) { return; }
      await transaction.insert('local_wallet', {'user_id':userId,'saldo':saldo,'saldo_retenido':saldoRetenido,
        'nonce':nonce,'firma':firma,'moneda':moneda,'server_validated':1,
        'updated_at':DateTime.now().toUtc().toIso8601String()},conflictAlgorithm:ConflictAlgorithm.replace);
    });
  }

  Future<Map<String, dynamic>?> getLocalWallet(String userId) async {
    final db = await database;
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
    final db = await database;
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

  Future<void> saveLocalWalletTransactions(
    List<Map<String, dynamic>> txs,
  ) async {
    final db = await database;
    final batch = db.batch();
    for (final tx in txs) {
      batch.insert('local_wallet_transactions', {
        'id': tx['id'],
        'user_id': tx['user_id'] ?? '',
        'tipo': tx['tipo'],
        'monto': (tx['monto'] as num).toDouble(),
        'saldo_anterior': (tx['saldo_anterior'] as num?)?.toDouble() ?? 0.0,
        'saldo_posterior': (tx['saldo_posterior'] as num?)?.toDouble() ?? 0.0,
        'descripcion': tx['descripcion'] ?? '',
        'fecha':
            tx['created_at'] ??
            tx['fecha'] ??
            DateTime.now().toUtc().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> getLocalWalletTransactions(
    String userId,
  ) async {
    final db = await database;
    return await db.query(
      'local_wallet_transactions',
      where: "user_id = ? AND tipo <> 'REGISTRO_LOCAL_CONCILIADO'",
      whereArgs: [userId],
      orderBy: 'fecha DESC',
    );
  }

  Future<void> insertOfflineWalletOrder(Map<String, dynamic> order) async {
    if ((_fixedScope ?? scope) == null) {
      throw StateError("Inicia sesión para registrar operaciones");
    }
    final db = await database;
    await db.insert(
      'offline_wallet_orders',
      order,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String,dynamic>>> getAllWalletOrders() async {
    final owner=_fixedScope ?? scope;
    if(owner==null) return [];
    final db=await database;
    return db.query('offline_wallet_orders',where:'cliente_id=?',whereArgs:[owner.split(':').last],orderBy:'created_at DESC');
  }

  Future<List<Map<String, dynamic>>> getPendingOfflineWalletOrders() async {
    final db = await database;
    return await db.query(
      'offline_wallet_orders',
      where: 'status = ?',
      whereArgs: ['PENDIENTE'],
      orderBy: 'created_at ASC',
    );
  }

  Future<Map<String, dynamic>?> getOfflineWalletOrder(String id) async {
    final db = await database;
    final rows = await db.query('offline_wallet_orders', where: 'client_operation_id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> updateOfflineWalletOrderStatus(
    String clientOpId, {
    required String status,
    String? serverReceipt,
    String? errorDetail,
  }) async {
    final db = await database;
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

  static List<Map<String,dynamic>> verifiedResults(List<Map<String,dynamic>> pending, Map<String,dynamic> response, {bool wallet = false}) {
    final raw = response['results'] ?? response['detalles'];
    if (raw is! List || raw.length != pending.length) throw const FormatException('Respuesta incompleta; pendientes conservados');
    final expected = {for(final op in pending) op['client_operation_id'].toString():op};
    final seen = <String>{};
    final results = <Map<String,dynamic>>[];
    for (final value in raw) {
      if (value is! Map) throw const FormatException('Respuesta inválida');
      final result = Map<String,dynamic>.from(value);
      final id = result['client_operation_id']?.toString();
      final status = result['status'];
      if (id == null || !expected.containsKey(id) || !seen.add(id) ||
        !(wallet ? ['CONFIRMADA','CONFLICTO','COMPENSADA_POR_STOCK','RECHAZADA_POR_SOBREGIRO','REINTENTAR']
          : ['CONFIRMADA','CONFLICTO','RECHAZADA_POR_STOCK','REINTENTAR']).contains(status) ||
        (!wallet && result['operation_type'] != null && result['operation_type'] != expected[id]!['operation_type']) ||
        (status == 'CONFIRMADA' && (result['receipt_number'] is! String || (result['receipt_number'] as String).isEmpty || result['server_entity_id'] == null))) {
        throw const FormatException('Respuesta no verificable; pendientes conservados');
      }
      results.add(result);
    }
    return results;
  }

  Future<void> applySyncResults(List<Map<String,dynamic>> pending, Map<String,dynamic> response) async {
    final results = verifiedResults(pending,response);
    final db = await database;
    await db.transaction((transaction) async {
      for(final result in results) {
        await transaction.update('pending_operations', {
          'local_status':result['status']=='REINTENTAR'?'LOCAL_PENDIENTE':result['status'],
          'server_receipt':result['receipt_number'],'server_entity_id':result['server_entity_id'],
          'error_detail':result['error_detail'],'synced_at':response['processed_at']},
          where:'client_operation_id = ? AND local_status = ?',whereArgs:[result['client_operation_id'],'LOCAL_PENDIENTE']);
      }
    });
  }

  Future<double> getPendingWalletTotal(String userId) async {
    final db = await database;
    final rows = await db.rawQuery("SELECT COALESCE(SUM(monto_total),0) AS total FROM offline_wallet_orders WHERE cliente_id=? AND status='PENDIENTE'",[userId]);
    return (rows.first['total'] as num).toDouble();
  }

  Future<Map<String,dynamic>> recordWalletOrder(Map<String,dynamic> order) async {
    final owner = _fixedScope ?? scope;
    if (owner == null || owner.split(':').last != order['cliente_id']) throw StateError('La operación requiere su propietario');
    final db = await database;
    return db.transaction((transaction) async {
      final walletRows = await transaction.query('local_wallet',where:'user_id = ?',whereArgs:[order['cliente_id']]);
      if (walletRows.isEmpty || walletRows.first['server_validated'] != 1) throw StateError('Conéctate para validar la billetera antes de usarla');
      final wallet = walletRows.first;
      final previous = await transaction.query('offline_wallet_orders',where:'client_operation_id = ?',whereArgs:[order['client_operation_id']]);
      final totals = await transaction.rawQuery("SELECT COALESCE(SUM(monto_total),0) AS total FROM offline_wallet_orders WHERE cliente_id=? AND status='PENDIENTE'",[order['cliente_id']]);
      final pending = (totals.first['total'] as num).toDouble();
      final amount = (order['monto_total'] as num).toDouble();
      final balance = (wallet['saldo'] as num).toDouble();
      final held = (wallet['saldo_retenido'] as num?)?.toDouble() ?? 0;
      if (previous.isNotEmpty) {
        for(final field in ['cliente_id','sucursal_id','monto_total','items_json','codigo_cupon']) {
          if (previous.first[field] != order[field]) throw StateError('El UUID ya contiene otra orden');
        }
        return {...wallet,'pending_total':pending};
      }
      if (!amount.isFinite || amount <= 0 || (amount*100-(amount*100).round()).abs()>0.000001 ||
          (amount*100).round() > (balance*100).round()-(held*100).round()-(pending*100).round()) {
        throw StateError('Saldo disponible insuficiente o importe inválido');
      }
      await transaction.insert('offline_wallet_orders',order,conflictAlgorithm:ConflictAlgorithm.abort);
      await transaction.insert('local_wallet_transactions',{
        'id':'LOCAL-${order['client_operation_id']}','user_id':order['cliente_id'],'tipo':'PAGO_VENTA_OFFLINE_PENDIENTE',
        'monto':-amount,'saldo_anterior':balance-pending,'saldo_posterior':balance-pending-amount,
        'descripcion':'Compra pendiente de confirmación central','fecha':order['fecha_local']});
      return {...wallet,'pending_total':pending+amount};
    });
  }

  Future<void> applyWalletSyncResults(String userId,List<Map<String,dynamic>> pending,Map<String,dynamic> response) async {
    final results = verifiedResults(pending,response,wallet:true);
    final balance = response['nuevo_saldo'];final nonce = response['nuevo_nonce'];
    final signature = response['nueva_firma'];final held = response['saldo_retenido'];
    if (balance is! num || !balance.isFinite || balance < 0 || held is! num || !held.isFinite || held < 0 || held > balance ||
      nonce is! int || nonce < 0 || signature is! String || signature.isEmpty) { throw const FormatException('Falta el saldo central confirmado'); }
    final db = await database;
    await db.transaction((transaction) async {
      for(final result in results) {
        await transaction.update('offline_wallet_orders',{'status':result['status']=='REINTENTAR'?'PENDIENTE':result['status'],
          'server_receipt':result['receipt_number'],'error_detail':result['error_detail']},
          where:'client_operation_id=? AND status=?',whereArgs:[result['client_operation_id'],'PENDIENTE']);
        if(result['status'] != 'REINTENTAR') {
          await transaction.update('local_wallet_transactions',{'tipo':'REGISTRO_LOCAL_CONCILIADO'},
            where:'id=?',whereArgs:['LOCAL-${result['client_operation_id']}']);
        }
      }
      final existing = await transaction.query('local_wallet',where:'user_id=?',whereArgs:[userId]);
      if (existing.isEmpty || existing.first['server_validated'] != 1 || (existing.first['nonce'] as num).toInt() <= nonce) {
        await transaction.insert('local_wallet',{'user_id':userId,'saldo':balance,'saldo_retenido':held,
          'nonce':nonce,'firma':signature,'moneda':'BOB','server_validated':1,'updated_at':DateTime.now().toUtc().toIso8601String()},
          conflictAlgorithm:ConflictAlgorithm.replace);
      }
    });
  }

  Future<void> invalidateWallet(String userId) async {
    final db=await database;
    await db.update('local_wallet',{'server_validated':0},where:'user_id=?',whereArgs:[userId]);
  }

  Future<String> replaceRejectedOperation(String id,Map<String,dynamic> replacement) async {
    final db = await database;
    return db.transaction((transaction) async {
      final rows = await transaction.query('pending_operations',where:'client_operation_id=?',whereArgs:[id]);
      if(rows.isEmpty) throw StateError('Operación no encontrada');
      final previous = rows.first;
      if(previous['replacement_id'] != null) return previous['replacement_id'].toString();
      if(previous['server_entity_id'] != null || !['CONFLICTO','RECHAZADA_POR_STOCK'].contains(previous['local_status'])) throw StateError('Revisa el efecto original antes de crear otro');
      final next = {...replacement,'supersedes_operation_id':id,'local_status':'LOCAL_PENDIENTE'};
      await transaction.insert('pending_operations',next,conflictAlgorithm:ConflictAlgorithm.abort);
      await transaction.update('pending_operations',{'local_status':'REEMPLAZADA','replacement_id':next['client_operation_id']},where:'client_operation_id=?',whereArgs:[id]);
      return next['client_operation_id'].toString();
    });
  }
}
