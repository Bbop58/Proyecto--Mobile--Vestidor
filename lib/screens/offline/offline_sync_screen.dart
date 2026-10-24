import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/services/connectivity_service.dart';
import '../../core/services/offline_sync_service.dart';

class OfflineSyncScreen extends StatefulWidget {
  const OfflineSyncScreen({super.key});

  @override
  State<OfflineSyncScreen> createState() => _OfflineSyncScreenState();
}

class _OfflineSyncScreenState extends State<OfflineSyncScreen> {
  List<Map<String, dynamic>> _operations = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadOperations();
  }

  Future<void> _loadOperations() async {
    setState(() => _isLoading = true);
    final syncService = context.read<OfflineSyncService>();
    final list = await syncService.getAllOperations();
    if (mounted) {
      setState(() {
        _operations = list;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final connectivity = context.watch<ConnectivityService>();
    final syncService = context.watch<OfflineSyncService>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sincronización Offline'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refrescar Lista',
            onPressed: _loadOperations,
          ),
        ],
      ),
      body: Column(
        children: [
          // Banner de estado de red
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: connectivity.isOnline
                ? Colors.green.withValues(alpha: 0.15)
                : Colors.red.withValues(alpha: 0.15),
            child: Row(
              children: [
                Icon(
                  connectivity.isOnline ? Icons.wifi : Icons.wifi_off,
                  color: connectivity.isOnline ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        connectivity.isOnline ? 'Conectado a Internet' : 'Modo Offline (Sin Conexión)',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: connectivity.isOnline ? Colors.green.shade800 : Colors.red.shade800,
                        ),
                      ),
                      Text(
                        connectivity.isOnline
                            ? 'Las operaciones locales se sincronizarán con el servidor central.'
                            : 'Las ventas y reservas se guardan en la base de datos local SQLite.',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Resumen de cola y botón de sincronización
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'OPERACIONES PENDIENTES',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${syncService.pendingCount} en cola local',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: syncService.pendingCount > 0 ? Colors.amber.shade800 : Colors.green,
                            ),
                          ),
                        ],
                      ),
                    ),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).primaryColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: syncService.isSyncing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.sync),
                      label: Text(syncService.isSyncing ? 'Sincronizando...' : 'Sincronizar Ahora'),
                      onPressed: (!connectivity.isOnline || syncService.isSyncing || syncService.pendingCount == 0)
                          ? null
                          : () async {
                              await syncService.syncBatchNow();
                              await _loadOperations();
                            },
                    ),
                  ],
                ),
              ),
            ),
          ),

          if (syncService.lastError != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        syncService.lastError!,
                        style: const TextStyle(color: Colors.red, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Título de lista
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Historial de Operaciones en este Móvil (SQLite)',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
            ),
          ),

          // Lista de transacciones
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _operations.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.storage_outlined, size: 48, color: Colors.grey.shade400),
                            const SizedBox(height: 12),
                            const Text(
                              'No hay operaciones locales registradas',
                              style: TextStyle(color: Colors.grey),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        itemCount: _operations.length,
                        separatorBuilder: (context, index) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final op = _operations[index];
                          final status = op['local_status'] ?? 'LOCAL_PENDIENTE';
                          final isConfirmed = status == 'CONFIRMADA';
                          final isPending = status == 'LOCAL_PENDIENTE';
                          final isStockRejected = status == 'RECHAZADA_POR_STOCK';

                          Color statusColor = Colors.amber;
                          IconData statusIcon = Icons.access_time;
                          String statusLabel = 'Pendiente';

                          if (isConfirmed) {
                            statusColor = Colors.green;
                            statusIcon = Icons.check_circle_outline;
                            statusLabel = 'Sincronizada';
                          } else if (isStockRejected) {
                            statusColor = Colors.red;
                            statusIcon = Icons.remove_circle_outline;
                            statusLabel = 'Rechazada por Stock';
                          } else if (!isPending) {
                            statusColor = Colors.purple;
                            statusIcon = Icons.warning_amber_rounded;
                            statusLabel = status;
                          }

                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                            leading: CircleAvatar(
                              backgroundColor: statusColor.withValues(alpha: 0.15),
                              child: Icon(statusIcon, color: statusColor, size: 20),
                            ),
                            title: Text(
                              op['operation_type'] == 'VENTA_CONTADO_OFFLINE' ? 'Venta Contado' : 'Reserva',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Fecha: ${op['fecha_local']?.toString().split('T').first ?? ''}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                if (op['server_receipt'] != null)
                                  Text(
                                    'Recibo Oficial: ${op['server_receipt']}',
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue),
                                  ),
                                if (op['error_detail'] != null)
                                  Text(
                                    op['error_detail'],
                                    style: const TextStyle(fontSize: 11, color: Colors.red),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                              ],
                            ),
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  '${(op['monto_total'] as num?)?.toStringAsFixed(2) ?? '0.00'} Bs.',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: statusColor.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    statusLabel,
                                    style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
