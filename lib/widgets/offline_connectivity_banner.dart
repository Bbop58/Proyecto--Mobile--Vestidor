import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/services/connectivity_service.dart';
import '../core/services/offline_sync_service.dart';

class OfflineConnectivityBanner extends StatelessWidget {
  const OfflineConnectivityBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final connectivity = context.watch<ConnectivityService>();
    final syncService = context.watch<OfflineSyncService>();

    final isOffline = !connectivity.isOnline;
    final pendingCount = syncService.pendingCount;
    final isSyncing = syncService.isSyncing;

    // Si está online y no hay nada pendiente por sincronizar, no mostramos nada
    if (!isOffline && pendingCount == 0 && !isSyncing) {
      return const SizedBox.shrink();
    }

    Color bgColor;
    Color textColor = Colors.white;
    IconData icon;
    String message;

    if (isOffline) {
      bgColor = const Color(0xFFDC2626); // Rojo alerta
      icon = Icons.wifi_off_rounded;
      message = pendingCount > 0
          ? 'Modo Offline: Operando con SQLite ($pendingCount en cola)'
          : 'Modo Offline: Sin conexión a la nube (Caché local)';
    } else if (isSyncing) {
      bgColor = const Color(0xFF2563EB); // Azul sincronización
      icon = Icons.sync_rounded;
      message = 'Sincronizando $pendingCount transacciones con el servidor...';
    } else {
      // Online con pendientes
      bgColor = const Color(0xFFD97706); // Ámbar
      icon = Icons.cloud_upload_outlined;
      message = '$pendingCount operaciones locales pendientes por subir';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: bgColor,
        boxShadow: [
          BoxShadow(
            color: bgColor.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        bottom: false,
        child: Row(
          children: [
            Icon(icon, color: textColor, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: textColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (!isOffline && pendingCount > 0 && !isSyncing)
              InkWell(
                onTap: () => syncService.syncBatchNow(),
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'Subir ahora',
                    style: TextStyle(
                      color: Color(0xFFD97706),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            if (isSyncing)
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

