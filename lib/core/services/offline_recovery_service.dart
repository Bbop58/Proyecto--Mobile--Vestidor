import 'dart:convert';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';
import '../../config/api_config.dart';
import '../../services/api_service.dart';
import '../database/database_helper.dart';
import 'offline_sync_service.dart';

/// Recovery is explicit and never assigns unknown historical rows to a user.
class OfflineRecoveryService {
  final ApiService api;
  OfflineRecoveryService(this.api);
  String? _owner;
  List<Map<String,dynamic>> _verified = [];

  Future<Map<String,int>> preview() async {
    final owner = DatabaseHelper.scope;
    if (owner == null) throw StateError('Inicia sesión para verificar el propietario');
    _owner = null; _verified = [];
    final source = <Map<String,dynamic>>[];
    for (final name in ['fashion_store.db','fashion_store_v1.db']) {
      final file = path.join(await getDatabasesPath(),name);
      if (!await databaseFactory.databaseExists(file)) continue;
      final db = await openDatabase(file,readOnly:true,singleInstance:false);
      try {
        final tables = (await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table'")).map((r)=>r['name']).toSet();
        for(final table in ['pending_operations','offline_wallet_orders']) {
          if (tables.contains(table)) {
            for(final row in await db.query(table)) {
              source.add({'channel':table=='pending_operations'?'SYNC':'WALLET','row':Map<String,dynamic>.from(row)});
            }
          }
        }
      } finally { await db.close(); }
    }
    final valid = <Map<String,dynamic>>[];
    for(var start=0;start<source.length;start+=100) {
      final batch = source.skip(start).take(100).toList();
      final entries = batch.map((entry) {
        final row = entry['row'] as Map<String,dynamic>;
        Map<String,dynamic> operation;
        try {
          operation = entry['channel']=='SYNC' ? {...OfflineSyncService.payload(row),'local_status':row['local_status']} : {
            'client_operation_id':row['client_operation_id'],'cliente_id':row['cliente_id'],
            'sucursal_id':row['sucursal_id'],'fecha_local':row['fecha_local'],'monto_total':row['monto_total'],
            'items':jsonDecode(row['items_json'] as String),'nonce':row['nonce_usado'],
            'firma_cliente':row['firma_usada'],'codigo_autorizacion_offline':row['firma_usada'],
            'codigo_cupon':row['codigo_cupon'],'status':row['status']};
        } catch (_) { operation = {'client_operation_id':row['client_operation_id']}; }
        return {'channel':entry['channel'],'operation':operation};
      }).toList();
      final response = await api.postAuth('${ApiConfig.syncBatchUrl.replaceFirst('/batch','')}/recovery/preview',{'entries':entries},null,owner);
      if (owner != DatabaseHelper.scope) throw StateError('La sesión cambió');
      if (!response.success || response.data is! Map) throw StateError('No se pudo verificar la cola antigua');
      final results = response.data['results'];
      if (results is! List || results.length!=batch.length) throw const FormatException('Verificación incompleta');
      for(var i=0;i<results.length;i++) {
        final result = results[i]; final row = batch[i]['row'] as Map<String,dynamic>;
        if(result['index']!=i || result['client_operation_id']!=row['client_operation_id']) throw const FormatException('Identificadores no verificables');
        if(result['eligible']==true) valid.add(batch[i]);
      }
    }
    if (owner != DatabaseHelper.scope) throw StateError('La sesión cambió');
    _owner=owner;_verified=valid;
    return {'eligible':valid.length,'quarantined':source.length-valid.length};
  }

  Future<int> importVerified() async {
    final owner = _owner;
    if (owner == null || owner != DatabaseHelper.scope) throw StateError('Verifica de nuevo con la sesión actual');
    final db = await DatabaseHelper.instance.forScope(owner).database;
    final imported = await db.transaction((tx) async {
      var count = 0;
      for(final entry in _verified) {
        final table=entry['channel']=='SYNC'?'pending_operations':'offline_wallet_orders';
        final row = Map<String,dynamic>.from(entry['row'] as Map);
        final existing = await tx.query(table,where:'client_operation_id=?',whereArgs:[row['client_operation_id']]);
        if(existing.isNotEmpty) continue;
        final columns = (await tx.rawQuery('PRAGMA table_info($table)')).map((r)=>r['name']).toSet();
        row.removeWhere((key,value)=>!columns.contains(key));
        if(table=='pending_operations') {
          row['local_status']='LOCAL_PENDIENTE';row['server_entity_id']=null;row['synced_at']=null;
        } else { row['status']='PENDIENTE'; }
        row['server_receipt']=null;row['error_detail']=null;
        await tx.insert(table,row,conflictAlgorithm:ConflictAlgorithm.abort);count++;
      }
      return count;
    });
    _verified=[];_owner=null;
    return imported;
  }
}
