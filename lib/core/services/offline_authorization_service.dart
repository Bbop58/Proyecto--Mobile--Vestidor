import '../../services/api_service.dart';
import '../../config/api_config.dart';
import '../database/database_helper.dart';

/// Scoped license permits, never payment evidence or a replacement for outbox rows.
class OfflineAuthorizationService {
  final ApiService api;
  static final Set<String> _denied={};
  OfflineAuthorizationService(this.api);

  Future<void> prefetch(String channel) async {
    final owner=DatabaseHelper.scope;
    if(owner==null) return;
    try {
      final response=await api.postAuth('${ApiConfig.baseUrl}/api/v1/sync/authorizations',
          {'channel':channel,'count':10},null,owner);
      if(owner!=DatabaseHelper.scope) return;
      if(response.success && response.data is Map) {
        final raw=(response.data as Map)['grants'];
        if(raw is List) {
          await DatabaseHelper.instance.forScope(owner).cacheAuthorizations(
              raw.map((g)=>Map<String,dynamic>.from(g as Map)).toList());
          _denied.remove('$owner:$channel');
        }
      } else if(response.statusCode==403) {
        _denied.add('$owner:$channel');
        await DatabaseHelper.instance.forScope(owner).discardUnusedAuthorizations(channel);
      }
    } catch(_) { /* Authorizations are optional; never discard existing pending work. */ }
  }

  Future<Map<String,dynamic>?> take(String channel,{required bool online}) async {
    final owner=DatabaseHelper.scope;
    if(owner==null) throw StateError('Inicia sesión');
    final serverReady = online && await api.prepareSession(expectedScope:owner);
    if(owner!=DatabaseHelper.scope) throw StateError('La identidad cambió');
    final profile=api.sessionCoordinator?.profile;
    if (api.sessionCoordinator != null && (profile == null ||
        profile['service_restricted'] == true ||
        (profile['subscription_capabilities'] as Map?)?['offline'] != true)) {
      throw StateError('La sesión o el contrato no habilita nuevas operaciones offline');
    }
    if (_denied.contains('$owner:$channel') && serverReady) await prefetch(channel);
    if (_denied.contains('$owner:$channel')) {
      throw StateError('El contrato no habilita operaciones offline');
    }
    final db=DatabaseHelper.instance.forScope(owner);
    var grant=await db.takeAuthorization(channel);
    if(grant==null && serverReady) {await prefetch(channel);grant=await db.takeAuthorization(channel);}
    if(owner!=DatabaseHelper.scope) throw StateError('La identidad cambió');
    if(_denied.contains('$owner:$channel')) throw StateError('El contrato no habilita operaciones offline');
    if (!serverReady && grant == null) {
      throw StateError('No hay autorización offline vigente. Conéctate para renovarla; tus pendientes se conservan.');
    }
    return grant;
  }
}
