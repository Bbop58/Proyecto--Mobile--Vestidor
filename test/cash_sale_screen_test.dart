import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:mobile/core/database/database_helper.dart';
import 'package:mobile/core/services/connectivity_service.dart';
import 'package:mobile/core/services/offline_authorization_service.dart';
import 'package:mobile/core/services/offline_sync_service.dart';
import 'package:mobile/models/cash_snapshot.dart';
import 'package:mobile/models/user.dart';
import 'package:mobile/screens/sales/cash_sale_screen.dart';
import 'package:mobile/services/api_service.dart';
import 'package:mobile/services/auth_service.dart';
import 'package:mobile/services/branch_service.dart';
import 'package:mobile/services/cash_sale_service.dart';
import 'package:mobile/services/inventory_service.dart';
import 'package:mobile/services/product_service.dart';
import 'package:mobile/services/storage_service.dart';

class _Auth extends AuthService {
  _Auth(this.active,ApiService api,StorageService storage):super(api,storage);
  final User active;
  @override User get currentUser=>active;
}
class _Conn extends ConnectivityService { @override bool get isOnline=>false; }
class _Sync extends OfflineSyncService {
  _Sync(super.api,super.conn);
  int calls=0;
  bool fail=false;
  @override Future<String> saveOfflineSale({required String localRequestId,required String sucursalId,
    required List<Map<String,dynamic>> items,required double montoTotal,
    required double montoRecibido,required double cambio,String? cajeroId,
    String? clienteId,String metodoPago='EFECTIVO',String? notas}) async {
    calls++;
    if(fail) throw StateError('Disco ocupado');
    expect(localRequestId,isNotEmpty);
    expect(items.single['cantidad'],1);
    expect(montoTotal,20);expect(montoRecibido,30);expect(cambio,10);
    return 'operation-1';
  }
  @override Future<List<Map<String,dynamic>>> getAllOperations() async => [
    {'client_operation_id':'operation-1','local_status':'LOCAL_PENDIENTE'}];
}
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    sqfliteFfiInit();databaseFactory=databaseFactoryFfi;
    final dir=await Directory.systemTemp.createTemp('cash-screen-');
    await databaseFactory.setDatabasesPath(dir.path);
    const owner='company:cash-screen-person';
    DatabaseHelper.activateScope(owner);
    final now=DateTime.now().toUtc();
    await DatabaseHelper.instance.forScope(owner).saveCashSnapshot(CashSnapshot(
      owner:owner,branchId:'branch',preparedAt:now,validUntil:now.add(const Duration(hours:1)),
      products:[],availability:[{'variante_id':'variant','nombre':'Camisa',
        'sku':'SKU-1','talla':'M','color':'Negro','precio':20.0,'stock_disponible':2}]).toRow());
  });
  testWidgets('cash form keeps cart after save error and shows provisional receipt on retry',(tester) async {
    final storage=StorageService(),api=ApiService(storage),conn=_Conn();
    final user=User.fromJson({'id':'cash-screen-person','tenant_id':'company','email':'qa@example.com',
      'full_name':'QA','is_active':true,'access_scope':'COMPANY',
      'permissions':['ventas.create'],'subscription_capabilities':{'offline':true}});
    final auth=_Auth(user,api,storage),sync=_Sync(api,conn);
    DatabaseHelper.activateScope('company:cash-screen-person');
    final cash=CashSaleService(api:api,branches:BranchService(api),products:ProductService(api),
      inventory:InventoryService(api),authorizations:OfflineAuthorizationService(api));
    await tester.pumpWidget(ChangeNotifierProvider<AuthService>.value(value:auth,
      child:MaterialApp(home:CashSaleScreen(cashService:cash,syncService:sync,connectivityService:conn))));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds:80)));
    await tester.pump();
    expect(find.textContaining('Camisa'),findsOneWidget);
    await tester.tap(find.byTooltip('Añadir'));
    await tester.enterText(find.byType(TextField).last,'30');
    await tester.ensureVisible(find.text('Guardar venta pendiente'));
    sync.fail=true;
    await tester.tap(find.text('Guardar venta pendiente'));
    await tester.pump();
    expect(find.textContaining('Disco ocupado'),findsOneWidget);
    expect(find.text('Total: Bs 20.00'),findsOneWidget);
    sync.fail=false;
    await tester.tap(find.text('Guardar venta pendiente'));
    await tester.pump();
    expect(sync.calls,2);
    expect(find.text('Comprobante provisional'),findsOneWidget);
    expect(find.text('Operación operation-1'),findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    sync.dispose();conn.dispose();auth.dispose();api.dispose();
    DatabaseHelper.activateScope(null);
  });
}
