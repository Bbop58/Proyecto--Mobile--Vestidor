import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/services/connectivity_service.dart';
import '../core/services/offline_sync_service.dart';
import '../services/auth_service.dart';
import '../models/mobile_session.dart';

class OfflineConnectivityBanner extends StatelessWidget {
  const OfflineConnectivityBanner({super.key});
  @override
  Widget build(BuildContext context) {
    final network = context.watch<ConnectivityService>();
    final sync = context.watch<OfflineSyncService>();
    final auth = context.watch<AuthService?>();
    final offline = !network.isOnline;
    final unverified = auth?.sessionState == SessionState.offline;
    final restricted = auth?.sessionState == SessionState.restricted;
    if (!offline &&
        !unverified &&
        !restricted &&
        sync.pendingCount == 0 &&
        !sync.isSyncing) {
      return const SizedBox.shrink();
    }
    final message = restricted
        ? 'Acceso restringido. Tus datos y pendientes se conservan; no se habilitan nuevas operaciones.'
        : offline
        ? 'Sin Internet: ${sync.pendingCount} operaciones pendientes. Consulta tus datos guardados; para operar necesitas autorización vigente.'
        : unverified
        ? 'Sesión sin verificar. Se conservan tus datos locales y operaciones pendientes.'
        : sync.isSyncing
        ? 'Sincronizando ${sync.pendingCount} operaciones guardadas...'
        : '${sync.pendingCount} operaciones locales pendientes por subir';
    final color = offline
        ? const Color(0xFFB91C1C)
        : sync.isSyncing
        ? const Color(0xFF1D4ED8)
        : const Color(0xFF92400E);
    final action = !offline && !sync.isSyncing;
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        color: color,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: SafeArea(
          bottom: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    offline
                        ? Icons.wifi_off_rounded
                        : Icons.cloud_sync_outlined,
                    color: Colors.white,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      message,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (sync.isSyncing)
                    const Padding(
                      padding: EdgeInsets.only(left: 8),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      ),
                    ),
                ],
              ),
              if (action)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      minimumSize: const Size(48, 48),
                    ),
                    onPressed: () async {
                      if (unverified || restricted) {
                        await auth?.revalidateSession();
                      } else {
                        await sync.syncBatchNow(force: true);
                      }
                    },
                    child: Text(
                      unverified || restricted ? 'Reintentar' : 'Subir ahora',
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
