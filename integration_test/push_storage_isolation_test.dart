import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mobile/services/notification_push_service.dart';
import 'package:mobile/services/storage_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('push access cannot redirect the default authentication store', (tester) async {
    const auth = FlutterSecureStorage(aOptions: AndroidOptions());
    const key = 'qa_push_storage_isolation_sentinel';
    await auth.write(key: key, value: 'auth-sentinel');
    final push = SecurePushStore();
    await push.read();
    expect(await auth.read(key: key), 'auth-sentinel');
    final original=await push.read();
    try {
      await push.write({'qa':'push-sentinel'});
      await StorageService().clearAll();
      expect(await SecurePushStore().read(),{'qa':'push-sentinel'});
      expect(await auth.read(key:key),'auth-sentinel');
    } finally {
      if(original!=null){
        await push.write(original);
      }else{
        await auth.delete(key:'fashionstore_push_registration_v1');
      }
    }
    await auth.delete(key: key);
  });
}
