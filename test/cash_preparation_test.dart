import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:mobile/core/database/database_helper.dart';
import 'package:mobile/core/services/offline_authorization_service.dart';
import 'package:mobile/models/user.dart';
import 'package:mobile/services/api_service.dart';
import 'package:mobile/services/branch_service.dart';
import 'package:mobile/services/cash_sale_service.dart';
import 'package:mobile/services/inventory_service.dart';
import 'package:mobile/services/product_service.dart';
import 'package:mobile/services/storage_service.dart';

String _grant(String owner, String id) {
  final parts = owner.split(':');
  String encode(Object value) => base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${encode({'alg':'HS256','typ':'JWT'})}.${encode({
    'purpose':'OFFLINE_ENTITLEMENT', 'actor_id':parts[1], 'tenant_id':parts[0],
    'operation_id':id, 'channel':'SYNC', 'kinds':['VENTA_CONTADO_OFFLINE']
  })}.test-signature';
}

class _Api extends ApiService {
  _Api() : super(StorageService());
  bool denied = false, malformed = false, permit = true, ready = true;
  String owner = '';
  @override
  Future<bool> prepareSession({required String expectedScope, bool revalidate = true}) async => ready;
  @override
  Future<ApiResponse> getAuth(String url) async {
    if (denied) { return ApiResponse(success:false,statusCode:403,error:'Sin permiso'); }
    if (url.contains('/sucursales')) { return ApiResponse(success:true,statusCode:200,data:[
      {'id':'branch-1','nombre':'Central','direccion':'Calle 1','activa':true}
    ]); }
    if (url.contains('/productos')) { return ApiResponse(success:true,statusCode:200,data:[
      {'id':'product-1','nombre':'Prenda','codigo':'P1','precio_base':20,
        'activo':true,'variantes':[{'id':'variant-1','producto_id':'product-1',
          'talla':'M','color':'Negro','sku':'SKU-1','precio_extra':0,'activo':true}]}
    ]); }
    if (url.contains('/inventario/disponibilidad')) { return ApiResponse(success:true,statusCode:200,data: malformed ? [
      {'producto_id':'product-1','sucursal_id':'branch-1','sku':'SKU-1',
       'talla':'M','color':'Negro','stock_disponible':'5','precio':20}
    ] : [
      {'producto_id':'product-1','sucursal_id':'branch-1','sku':'SKU-1',
       'talla':'M','color':'Negro','stock_disponible':5,'precio':20}
    ]); }
    return ApiResponse(success:false,statusCode:404);
  }
  @override
  Future<ApiResponse> postAuth(String url, [Map<String,dynamic>? body, Duration? timeout, String? expectedScope]) async {
    final id='grant-${DateTime.now().microsecondsSinceEpoch}';
    return ApiResponse(success:true,statusCode:200,data:{'grants': permit ? [
      {'client_operation_id':id,'channel':'SYNC','authorization':_grant(owner,id),
       'expires_at':DateTime.now().toUtc().add(const Duration(hours:2)).toIso8601String()}
    ] : []});
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  setUpAll(() async {
    sqfliteFfiInit(); databaseFactory=databaseFactoryFfi;
    dir=await Directory.systemTemp.createTemp('cash-preparation-');
    await databaseFactory.setDatabasesPath(dir.path);
  });
  tearDownAll(() async { DatabaseHelper.activateScope(null); });

  User user(String owner, {bool permitted=true}) {
    final parts=owner.split(':');
    return User.fromJson({'id':parts[1],'tenant_id':parts[0],
      'email':'qa@example.com','full_name':'QA','is_active':true,
      'access_scope':'COMPANY','permissions':permitted?['ventas.create']:[],
      'subscription_capabilities':{'offline':true}});
  }
  CashSaleService service(_Api api) => CashSaleService(api:api,
    branches:BranchService(api), products:ProductService(api),
    inventory:InventoryService(api), authorizations:OfflineAuthorizationService(api));

  test('prepares exact branch variant and survives a new service instance', () async {
    final owner='company:person-${DateTime.now().microsecondsSinceEpoch}';
    DatabaseHelper.activateScope(owner);
    final api=_Api()..owner=owner;
    final snapshot=await service(api).prepare(branchId:'branch-1',user:user(owner));
    expect(snapshot.availability.single['variante_id'],'variant-1');
    expect(snapshot.availability.single['stock_disponible'],5);
    expect(snapshot.validUntil.difference(snapshot.preparedAt).inHours,lessThanOrEqualTo(24));
    expect((await service(api).loadPrepared('branch-1'))!.owner,owner);
    DatabaseHelper.activateScope('company:someone-else');
    expect(await service(api).loadPrepared('branch-1'),isNull);
  });

  test('no permission, denied API or incomplete stock never create a snapshot', () async {
    final owner='company:person-${DateTime.now().microsecondsSinceEpoch}';
    DatabaseHelper.activateScope(owner);
    final api=_Api()..owner=owner;
    expect(service(api).canSell(user(owner,permitted:false)),isFalse);
    final base=user(owner).toJson();
    expect(service(api).canSell(User.fromJson({...base,'access_scope':'PLATFORM','is_platform_admin':true})),isFalse);
    expect(service(api).canSell(User.fromJson({...base,'service_restricted':true})),isFalse);
    await expectLater(service(api).prepare(branchId:'branch-1',user:user(owner,permitted:false)),throwsStateError);
    api.denied=true;
    await expectLater(service(api).prepare(branchId:'branch-1',user:user(owner)),throwsException);
    api.denied=false; api.malformed=true;
    await expectLater(service(api).prepare(branchId:'branch-1',user:user(owner)),throwsFormatException);
    expect(await service(api).loadPrepared('branch-1'),isNull);
  });

  test('missing authorization or offline preparation leaves prior snapshot untouched', () async {
    final owner='company:person-${DateTime.now().microsecondsSinceEpoch}';
    DatabaseHelper.activateScope(owner);
    final api=_Api()..owner=owner;
    final original=await service(api).prepare(branchId:'branch-1',user:user(owner));
    api.ready=false;
    await expectLater(service(api).prepare(branchId:'branch-1',user:user(owner)),throwsStateError);
    expect((await service(api).loadPrepared('branch-1'))!.preparedAt,original.preparedAt);
  });

  test('no cash grant cannot prepare even with stock and a permitted profile', () async {
    final owner='company:person-${DateTime.now().microsecondsSinceEpoch}';
    DatabaseHelper.activateScope(owner);
    final api=_Api()..owner=owner..permit=false;
    await expectLater(service(api).prepare(branchId:'branch-1',user:user(owner)),throwsStateError);
    expect(await service(api).loadPrepared('branch-1'),isNull);
  });

  test('expired preparation cannot be loaded offline', () async {
    final owner='company:person-${DateTime.now().microsecondsSinceEpoch}';
    DatabaseHelper.activateScope(owner);
    final api=_Api()..owner=owner;
    final original=await service(api).prepare(branchId:'branch-1',user:user(owner));
    final expired=original.toRow()..['valid_until']=DateTime.now().toUtc().subtract(const Duration(seconds:1)).toIso8601String();
    await DatabaseHelper.instance.forScope(owner).saveCashSnapshot(expired);
    expect(await service(api).loadPrepared('branch-1'),isNull);
  });
}
