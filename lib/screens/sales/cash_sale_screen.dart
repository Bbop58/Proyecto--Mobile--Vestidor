import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../config/routes.dart';
import '../../core/database/database_helper.dart';
import '../../core/services/connectivity_service.dart';
import '../../core/services/offline_authorization_service.dart';
import '../../core/services/offline_sync_service.dart';
import '../../models/cash_snapshot.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../services/branch_service.dart';
import '../../services/cash_sale_service.dart';
import '../../services/inventory_service.dart';
import '../../services/product_service.dart';

class CashSaleScreen extends StatefulWidget {
  final CashSaleService? cashService;
  final OfflineSyncService? syncService;
  final ConnectivityService? connectivityService;
  const CashSaleScreen({super.key,this.cashService,this.syncService,this.connectivityService});
  @override
  State<CashSaleScreen> createState()=>_CashSaleScreenState();
}

class _CashSaleScreenState extends State<CashSaleScreen> {
  final received=TextEditingController();
  final search=TextEditingController();
  final quantities=<String,int>{};
  final branches=<String,String>{};
  final snapshots=<String,CashSnapshot>{};
  CashSaleService? cash;
  ConnectivityService? connectivity;
  String? selected, requestId, receiptId, error, owner;
  bool busy=false;
  Map<String,dynamic>? receipt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if(!mounted)return;
      if(!CashSaleService.eligible(context.read<AuthService>().currentUser))return;
      connectivity=widget.connectivityService ?? context.read<ConnectivityService>();
      connectivity!.addListener(_connectivityChanged);
      _load();
    });
    DatabaseHelper.scopeChanges.addListener(_identityChanged);
  }
  void _identityChanged() {
    if (!mounted) return;
    setState(() { owner=DatabaseHelper.scope; selected=null;requestId=null;receiptId=null;
      receipt=null;error=null;quantities.clear();snapshots.clear();branches.clear();received.clear(); });
    if(owner!=null) unawaited(_load());
  }
  void _connectivityChanged() {
    if(mounted && connectivity?.isOnline==true) {
      unawaited(_load());
      unawaited(_refreshReceipt());
    }
  }
  @override
  void dispose() {
    DatabaseHelper.scopeChanges.removeListener(_identityChanged);
    connectivity?.removeListener(_connectivityChanged);
    received.dispose();search.dispose();super.dispose();
  }
  CashSaleService _service() => cash ??= widget.cashService ?? CashSaleService(
    api:context.read<ApiService>(),branches:context.read<BranchService>(),
    products:context.read<ProductService>(),inventory:context.read<InventoryService>(),
    authorizations:OfflineAuthorizationService(context.read<ApiService>()));

  Future<void> _load() async {
    final scope=DatabaseHelper.scope;
    final user=context.read<AuthService>().currentUser;
    if(scope==null || user==null || !_service().canSell(user)) return;
    final stored=await DatabaseHelper.instance.forScope(scope).listCashSnapshots();
    final available=<String,CashSnapshot>{};
    for(final row in stored) {
      try {final value=CashSnapshot.fromRow(row);
        if(value.owner==scope && value.isValid) available[value.branchId]=value;
      } catch (_) { /* An invalid snapshot never enables a sale. */ }
    }
    if (!mounted || DatabaseHelper.scope!=scope) return;
    final labels=<String,String>{};
    if((widget.connectivityService ?? context.read<ConnectivityService>()).isOnline) {
      try {for(final branch in await context.read<BranchService>().getBranches()) {
        labels[branch.id]=branch.nombre;
      }} catch (_) { /* Existing preparation remains available offline. */ }
    }
    if(!mounted || DatabaseHelper.scope!=scope) return;
    setState(() {owner=scope;snapshots..clear()..addAll(available);
      branches..clear()..addAll(labels);
      selected=selected!=null && (labels.containsKey(selected)||available.containsKey(selected))
        ?selected:(labels.keys.isNotEmpty?labels.keys.first:(available.keys.isNotEmpty?available.keys.first:null));
    });
    await _refreshReceipt();
  }
  Future<void> _refreshReceipt() async {
    final id=receiptId;
    if(id==null)return;
    final rows=await (widget.syncService ?? context.read<OfflineSyncService>()).getAllOperations();
    if(mounted) setState(() {receipt=rows.where((r)=>r['client_operation_id']==id).firstOrNull;});
  }
  Future<void> _prepare() async {
    final id=selected,user=context.read<AuthService>().currentUser;
    if(id==null||user==null||busy)return;
    setState(() {busy=true;error=null;});
    try {
      if(!(widget.connectivityService ?? context.read<ConnectivityService>()).isOnline) throw StateError('Conéctate para preparar caja');
      final value=await _service().prepare(branchId:id,user:user);
      if(!mounted || owner!=DatabaseHelper.scope)return;
      setState(() {snapshots[id]=value;quantities.clear();requestId=null;});
    } catch(e) {if(mounted)setState(() {error='$e';});}
    finally {if(mounted)setState(() {busy=false;});}
  }
  int? _receivedCents() {
    final raw=received.text.trim().replaceAll(',','.');
    if(!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(raw))return null;
    final parts=raw.split('.');
    return int.parse(parts[0])*100+(parts.length==2?int.parse(parts[1].padRight(2,'0')):0);
  }
  int _price(Map<String,dynamic> row)=>((row['precio'] as num).toDouble()*100).round();
  Future<void> _save() async {
    final id=selected, snapshot=id==null?null:snapshots[id];
    final user=context.read<AuthService>().currentUser;
    if(busy||id==null||snapshot==null||user==null)return;
    final chosen=snapshot.availability.where((v)=>(quantities[v['variante_id']]??0)>0).toList();
    final total=chosen.fold<int>(0,(sum,v)=>sum+_price(v)*(quantities[v['variante_id']]??0));
    final paid=_receivedCents();
    if(chosen.isEmpty||paid==null||paid<total) {
      setState(() {error='Selecciona prendas y registra el efectivo recibido (mínimo Bs ${(total/100).toStringAsFixed(2)}).';});return;
    }
    requestId ??= const Uuid().v4();
    setState(() {busy=true;error=null;});
    try {
      final op=await (widget.syncService ?? context.read<OfflineSyncService>()).saveOfflineSale(
        localRequestId:requestId!,sucursalId:id,
        items:chosen.map((v)=>{'variante_id':v['variante_id'],
          'cantidad':quantities[v['variante_id']]!,'precio_unitario':v['precio']}).toList(),
        montoTotal:total/100,montoRecibido:paid/100,cambio:(paid-total)/100);
      if(!mounted||owner!=DatabaseHelper.scope)return;
      setState(() {receiptId=op;requestId=null;quantities.clear();received.clear();});
      await _refreshReceipt();
    } catch(e) {if(mounted)setState(() {error='$e';});}
    finally {if(mounted)setState(() {busy=false;});}
  }
  @override
  Widget build(BuildContext context) {
    final user=context.watch<AuthService>().currentUser;
    if(!CashSaleService.eligible(user)) {
      return Scaffold(appBar:AppBar(title:const Text('Caja móvil')),
        body:const Center(child:Text('Tu cuenta no tiene permiso para caja móvil.')));
    }
    final snapshot=selected==null?null:snapshots[selected];
    final rows=snapshot?.availability.where((v)=>
      '${v['nombre']} ${v['sku']} ${v['talla']} ${v['color']}'.toLowerCase().contains(search.text.toLowerCase())).toList() ?? [];
    final total=(snapshot?.availability ?? []).fold<int>(0,(sum,v)=>sum+_price(v)*(quantities[v['variante_id']]??0));
    final paid=_receivedCents();
    final options={...branches,...{for(final id in snapshots.keys)id:branches[id]??id}};
    return Scaffold(appBar:AppBar(title:const Text('Caja móvil'),actions:[
      IconButton(onPressed:busy?null:_load,icon:const Icon(Icons.refresh),tooltip:'Actualizar'),
    ]),body:ListView(padding:const EdgeInsets.all(16),children:[
      const Text('Venta presencial en efectivo. La confirmación final llega al sincronizar.'),
      const SizedBox(height:16),
      DropdownButtonFormField<String>(initialValue:options.containsKey(selected)?selected:null,
        decoration:const InputDecoration(labelText:'Sucursal'),items:options.entries.map((e)=>
          DropdownMenuItem(value:e.key,child:Text(e.value,overflow:TextOverflow.ellipsis))).toList(),
        onChanged:busy?null:(value)=>setState(() {selected=value;quantities.clear();requestId=null;})),
      const SizedBox(height:12),
      OutlinedButton.icon(onPressed:busy||selected==null?null:_prepare,
        icon:const Icon(Icons.download_for_offline_outlined),label:const Text('Preparar caja con Internet')),
      if(snapshot==null) const Padding(padding:EdgeInsets.all(12),child:Text('Prepara esta sucursal con Internet antes de cobrar.')),
      if(snapshot!=null) ...[
        Text('Preparada hasta ${snapshot.validUntil.toLocal()}'),
        TextField(controller:search,decoration:const InputDecoration(labelText:'Buscar prenda o SKU',prefixIcon:Icon(Icons.search)),
          onChanged:(_)=>setState((){})),
        ...rows.map((row) {
          final id=row['variante_id'] as String;
          final qty=quantities[id]??0;
          return ListTile(title:Text('${row['nombre']} · ${row['talla']} · ${row['color']}'),
            subtitle:Text('${row['sku']} · Bs ${(_price(row)/100).toStringAsFixed(2)} · Disponible ${row['stock_disponible']}'),
            trailing:Row(mainAxisSize:MainAxisSize.min,children:[
              IconButton(tooltip:'Quitar',onPressed:busy||qty==0?null:()=>setState(() {quantities[id]=qty-1;requestId=null;}),icon:const Icon(Icons.remove_circle_outline)),
              Text('$qty'),
              IconButton(tooltip:'Añadir',onPressed:busy||qty>=(row['stock_disponible'] as int)?null:()=>setState(() {quantities[id]=qty+1;requestId=null;}),icon:const Icon(Icons.add_circle_outline)),
            ]));
        }),
        const Divider(),
        Text('Total: Bs ${(total/100).toStringAsFixed(2)}'),
        TextField(controller:received,keyboardType:const TextInputType.numberWithOptions(decimal:true),
          decoration:const InputDecoration(labelText:'Efectivo recibido (Bs)'),onChanged:(_)=>setState((){requestId=null;})),
        Text('Cambio: Bs ${paid==null||paid<total?'—':((paid-total)/100).toStringAsFixed(2)}'),
        const SizedBox(height:12),
        FilledButton(onPressed:busy?null:_save,child:Text(busy?'Guardando…':'Guardar venta pendiente')),
      ],
      if(error!=null) Padding(padding:const EdgeInsets.all(12),child:Text(error!,style:TextStyle(color:Theme.of(context).colorScheme.error))),
      if(receiptId!=null) Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        const Text('Comprobante provisional',style:TextStyle(fontWeight:FontWeight.bold)),
        Text('Operación $receiptId'),
        Text(receipt?['local_status']?.toString()??'Pendiente de sincronización'),
        TextButton(onPressed:()=>Navigator.pushNamed(context,AppRoutes.offlineSync),child:const Text('Ver sincronización')),
      ]))),
    ]));
  }
}
