import '../core/database/database_helper.dart';
import '../core/services/offline_authorization_service.dart';
import '../models/cash_snapshot.dart';
import '../models/mobile_session.dart';
import '../models/user.dart';
import 'api_service.dart';
import 'branch_service.dart';
import 'inventory_service.dart';
import 'product_service.dart';

/// Offline cash preparation and durable local receipt. Central acceptance is separate.
class CashSaleService {
  final ApiService api;
  final BranchService branches;
  final ProductService products;
  final InventoryService inventory;
  final OfflineAuthorizationService authorizations;
  final DatabaseHelper database;

  CashSaleService({required this.api, required this.branches,
    required this.products, required this.inventory,
    required this.authorizations, DatabaseHelper? database})
      : database = database ?? DatabaseHelper.instance;

  static bool eligible(User? user) => user != null && user.canUseMobile && user.isActive &&
      !user.serviceRestricted && user.subscriptionCapabilities['offline'] == true &&
      user.hasPermission('ventas.create');
  bool canSell(User? user) => eligible(user);

  Future<CashSnapshot> prepare({required String branchId, required User user}) async {
    final owner = DatabaseHelper.scope;
    if (owner == null || owner != '${user.tenantId}:${user.id}' || !canSell(user)) {
      throw StateError('La cuenta no tiene permiso para preparar caja móvil');
    }
    if (!await api.prepareSession(expectedScope: owner)) {
      throw StateError('Conéctate para preparar caja móvil');
    }
    final activeProfile = api.sessionCoordinator?.profile;
    if (activeProfile != null && (!canSell(User.fromJson(activeProfile)) ||
        activeProfile['id'] != user.id || activeProfile['tenant_id'] != user.tenantId)) {
      throw StateError('La sesión o los permisos cambiaron');
    }
    final branch = (await branches.getBranches()).where((b) => b.id == branchId).firstOrNull;
    if (branch == null || !branch.activa) throw StateError('Sucursal no autorizada');
    final catalogue = await products.getProducts();
    if (catalogue.isEmpty) throw StateError('El catálogo está vacío');
    final stock = await inventory.getBranchVariantAvailability(
      sucursalId: branchId, products: catalogue);
    if (DatabaseHelper.scope != owner) throw StateError('La identidad cambió');
    await authorizations.prefetch('SYNC');
    if (DatabaseHelper.scope != owner) throw StateError('La identidad cambió');
    final db = await database.forScope(owner).database;
    final grants = await db.query('offline_authorizations',
      where: 'channel=?', whereArgs: ['SYNC']);
    final now = DateTime.now().toUtc();
    final eligible = <DateTime>[];
    for (final grant in grants) {
      final claims = accessClaims(grant['authorization']?.toString());
      final expiry = DateTime.tryParse(grant['expires_at']?.toString() ?? '')?.toUtc();
      if (expiry != null && expiry.isAfter(now) && claims != null &&
          claims['purpose'] == 'OFFLINE_ENTITLEMENT' &&
          claims['actor_id'] == user.id && claims['tenant_id'] == user.tenantId &&
          claims['operation_id'] == grant['client_operation_id'] &&
          claims['channel'] == 'SYNC' && claims['kinds'] is List &&
          (claims['kinds'] as List).contains('VENTA_CONTADO_OFFLINE')) {
        eligible.add(expiry);
      }
    }
    if (eligible.isEmpty) throw StateError('No hay autorización offline vigente para caja');
    eligible.sort();
    final maxValidity = now.add(const Duration(hours: 24));
    final validUntil = eligible.last.isBefore(maxValidity) ? eligible.last : maxValidity;
    final snapshot = CashSnapshot(owner: owner, branchId: branchId,
      preparedAt: now, validUntil: validUntil,
      products: catalogue.where((p) => p.activo).map((p) => p.toJson()).toList(),
      availability: stock);
    await database.forScope(owner).saveCashSnapshot(snapshot.toRow());
    if (DatabaseHelper.scope != owner) throw StateError('La identidad cambió');
    return snapshot;
  }

  Future<CashSnapshot?> loadPrepared(String branchId) async {
    final owner = DatabaseHelper.scope;
    if (owner == null) return null;
    final row = await database.forScope(owner).getCashSnapshot(branchId);
    if (row == null || row['owner'] != owner || DatabaseHelper.scope != owner) return null;
    final snapshot = CashSnapshot.fromRow(row);
    return snapshot.isValid ? snapshot : null;
  }

  Future<String> saveDraft({required User user, required String branchId,
    required String localRequestId, required List<Map<String,dynamic>> items,
    required int totalCents, required int receivedCents}) async {
    final owner=DatabaseHelper.scope;
    if (owner==null || owner!='${user.tenantId}:${user.id}' || !canSell(user)) {
      throw StateError('La cuenta no tiene permiso de caja');
    }
    final profile=api.sessionCoordinator?.profile;
    if (profile!=null && (profile['id']!=user.id ||
        profile['tenant_id']!=user.tenantId || !canSell(User.fromJson(profile)))) {
      throw StateError('La sesión o los permisos cambiaron');
    }
    return database.forScope(owner).saveAuthorizedCashOperation(
      owner:owner,branchId:branchId,cashierId:user.id,localRequestId:localRequestId,
      items:items,totalCents:totalCents,receivedCents:receivedCents);
  }
}
