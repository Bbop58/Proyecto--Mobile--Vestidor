# Caja móvil en efectivo — E2, cierre local

9 de noviembre de 2026. Guardado local y reconciliación reutilizada implementados; E3 y E4 pendientes. No existe todavía la pantalla de caja ni aceptación Android/servidor real para efectivo.

## Resultado

- `saveAuthorizedCashOperation` guarda una venta de efectivo pendiente y consume exactamente una concesión SYNC en la misma transacción SQLite. La concesión debe pertenecer al actor/empresa, incluir `VENTA_CONTADO_OFFLINE` y estar vigente. No genera UUID sin firma.
- `local_request_id` estable devuelve el UUID original al repetir la misma solicitud; contenido distinto con ese identificador se rechaza. Cantidades, precios y total se validan en centavos; efectivo recibido debe cubrir el total y el cambio se calcula en la fila.
- La instantánea preparada debe pertenecer al usuario, a la sucursal y estar vigente. El stock por variante se reduce por operaciones locales pendientes o confirmadas desde la preparación. Una variante sin precio/stock conocido no se cobra.
- `OfflineSyncService.saveOfflineSale` delega en ese guardado y verifica perfil, permiso, capacidad offline, método efectivo y cambio. La sincronización existente ya revalida la sesión y conserva UUID/outbox ante errores de red. El botón de sucesor se bloqueó para efectivo rechazado porque no obtiene una concesión nueva de forma atómica.
- Billetera y reservas siguen usando sus rutas propias; no se modificó el backend ni PostgreSQL.

## Evidencia

- Prueba roja de API de almacenamiento ausente; después, `cash_storage_test.dart`: guardado único, doble llamada, contenido distinto, concesión incorrecta, stock agotado y trigger SQLite que aborta el insert sin consumir la concesión. Wallet conserva saldo90/nonce2.
- Regresión dirigida de almacenamiento/integridad/sync/wallet:25 aprobadas. Suite Flutter completa:140 aprobadas. `flutter analyze --no-pub`: sin observaciones. `git diff --check`: sin errores de espacio.
- La respuesta perdida, la sincronización real contra PostgreSQL, Keystore/reinicio Android y conflictos centrales siguen en E4; no se atribuyen a estas pruebas locales.

## Estado

Cambios locales en móvil; sin commit, push, despliegue ni APK en esta fase. La raíz de documentación está en el respaldo local; se copiará el contexto necesario al repo móvil antes de publicar E4. Archivos generados Linux/macOS/Windows previos no se incorporan al alcance.
