import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:mobile/models/user.dart';
import 'package:mobile/screens/sales/cash_sale_screen.dart';
import 'package:mobile/services/api_service.dart';
import 'package:mobile/services/auth_service.dart';
import 'package:mobile/services/storage_service.dart';

class _Auth extends AuthService {
  _Auth(User user) : current=user, super(ApiService(StorageService()),StorageService());
  final User current;
  @override
  User get currentUser=>current;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('direct cash route denies a client and a platform operator',(tester) async {
    for (final profile in [
      {'id':'client','tenant_id':'company','access_scope':'COMPANY','permissions':<String>[],
        'subscription_capabilities':{'offline':true}},
      {'id':'operator','tenant_id':'company','access_scope':'PLATFORM','is_platform_admin':true,
        'permissions':['ventas.create'],'subscription_capabilities':{'offline':true}},
    ]) {
      final user=User.fromJson({...profile,'email':'qa@example.com','full_name':'QA','is_active':true});
      final auth=_Auth(user);
      await tester.pumpWidget(ChangeNotifierProvider<AuthService>.value(value:auth,
        child:const MaterialApp(home:CashSaleScreen())));
      await tester.pump();
      expect(find.text('Tu cuenta no tiene permiso para caja móvil.'),findsOneWidget);
      expect(find.text('Guardar venta pendiente'),findsNothing);
      await tester.pumpWidget(const SizedBox());
      auth.dispose();
    }
  });
}
