# Caja móvil en efectivo — Implementation Plan

> **For agentic workers:** ejecutar este plan tarea por tarea con writing-plans, systematic-debugging ante fallos y verificación antes del cierre. Consultar superpowers:executing-plans si está disponible. Por preferencia de esta sesión se ejecuta nativamente, una fase a la vez, sin delegación automática. No comenzar ninguna fase solo por redactar este plan.

**Goal:** completar el requisito de venta de contado offline en Flutter con recepción de efectivo, persistencia tras reinicio y sincronización sin duplicados.

**Architecture:** pantalla de caja y servicio de preparación/venta sobre sesión, SQLite y outbox existentes. Snapshot propio y escritura atómica venta+concesión; backend actual autoriza y concilia los efectos centrales.

**Tech Stack:** Flutter3.47.1/Dart, Provider, sqflite/SQLite7→8, flutter_test/sqflite_common_ffi, integration_test, FastAPI y PostgreSQL QA; contratos /sync/authorizations y /sync/batch.

**Spec:** FLUTTER_CAJA_EFECTIVO_SPEC.md, en esta misma carpeta. Requisito original: PDF examen6.2–6.4 y7.2. No utilizar el documento académico antiguo como fuente de permisos/esquema.

## Global Constraints

- No rehacer billetera ni reservas; conservar sesión persistente y datos por propietario.
- No renombrar fashion_store_v2_<scope>.db; migración7→8 aditiva, sin fresh local ni borrado de colas.
- Caja exige ventas.create y contrato offline; operador y cliente sin permiso no acceden.
- Máximo24h de preparación: no cambia duración de sesión móvil; stock desconocido no autoriza cobro.
- Una transacción guarda venta y consume concesión; ningún UUID sin autorización offline.
- El cliente opcional se omite inicialmente; sin descarga de datos personales ni nuevos roles.
- Una operación conserva UUID, fecha, cantidades e importes al reintentar; servidor decide aceptación final.
- No nuevos servicios/proveedores/PostgreSQL previstos. Cambio backend solo con reproducción documentada que pruebe necesidad.
- Cada fase deja EFECTIVO_E<n>_CIERRE.md y matriz en docs/auditoria_software; copiar contexto a mobile/docs/efectivo para recuperación desde GitHub antes de publicar.
- Autorización vigente: pruebas demo/sandbox y push cuando convenga con D-blip-max. Revisar diff y secretos antes de cada commit; nunca git add de toda la raíz. Se puede reconstruir demo Railway si es necesario, pero registrar corte y no resetear durante una conciliación.

## Review Focus

1. Perfil antiguo, rol sin permiso o cuenta cambiada: sin caja ni publicación de datos ajenos (E1/E3/E4).
2. Stock ausente/viejo y descuentos por pendientes: no inventar disponibilidad ni permitir exceso local (E2/E4).
3. SQLite falla o doble pulsación: concesión intacta, carrito conservado, una sola operación (E2/E3).
4. Sesión expirada, red intermitente y respuesta perdida: mismo UUID y efecto central único (E2/E4).
5. Actualización y reinicio: billetera/sesión/colas históricas intactas, recibo provisional recuperable (E2/E4).

## Baseline y hallazgos

Mobile base b8ac8757ffcdc7e9afe7bdc8ecb073ce6467c134; backendf635346. PWA finalizada en web, no tocarla para este alcance. Flutter admite cuentas COMPANY pero User/sessionProfile no conservan permissions. saveOfflineSale solo tiene declaración, sin llamadas UI. InventoryService.getProductAvailability agrupa stock por sucursal. SQLite versión7, tablas de concesiones/outbox ya disponibles. 13pruebas wallet/sync/reinicio aprobadas en revisión8/11; baseline histórico de preparación129 no se presenta como nueva aceptación.

Corrección del diagnóstico previo: take(channel,online:false) ya rechaza grant ausente; el fallbackUUID puede ocurrir con sesión online. El riesgo específico comprobado por lectura es consumir concesión antes del insert, no demostrar que toda venta offline actual se guarda sin firma. Prueba roja debe reproducir el caso antes de corregirlo.

## E1 — Identidad y preparación de caja

**Modificar:** mobile/lib/models/user.dart; mobile/lib/models/mobile_session.dart; mobile/lib/services/auth_service.dart si necesita getter de permisos; mobile/lib/services/inventory_service.dart; mobile/lib/core/database/database_helper.dart (migración8 y snapshots).

**Crear:** mobile/test/cash_migration_test.dart; mobile/lib/models/cash_snapshot.dart; mobile/lib/services/cash_sale_service.dart; mobile/test/cash_permissions_test.dart; mobile/test/cash_preparation_test.dart.

**Interfaces:** User.permissions y hasPermission(String), lista vacía para perfil antiguo. CashSnapshot(owner,branchId,preparedAt,validUntil,products,availability). CashSaleService.prepare(branchId), loadPrepared(branchId), canSell y preparación declarada solo tras persistencia completa. Añadir getBranchVariantAvailability(sucursalId) al inventario sin modificar el método agrupado del cliente.

- [x] Registrar estado/repos/SDK y revisar build_user_response, permisos sembrados y contratos de sucursales, productos, inventario y concesiones. La prueba HTTP real con vendedor/cliente queda en E4.
- [x] Escribir rojas: perfil viejo sin permisos, permisos inválidos, operador/restricción, aislamiento de cuenta, SKU/variante, API403 y datos incompletos.
- [x] Ejecutar las pruebas rojas antes del cambio y la suite dirigida verde posterior.
- [x] Conservar permissions del perfil validado y sesión serializada de manera compatible; caja por permiso/capacidad y preparación vigente.
- [x] Implementar DTO/consulta detallada y servicio de preparación, snapshots y migración7→8 compatible con bases históricas.
- [x] Probar scopes A/B, preparación ausente/vencida, falta de concesión y consultas rechazadas; cerrar informe E1 sin publicar UI incompleta.

## E2 — SQLite y guardado atómico

**Modificar:** mobile/lib/core/database/database_helper.dart; mobile/lib/core/services/offline_sync_service.dart; mobile/lib/core/services/offline_authorization_service.dart solo para lectura/preparación de concesiones; mobile/lib/services/cash_sale_service.dart.

**Crear:** mobile/test/cash_storage_test.dart; **Ampliar:** mobile/test/cash_migration_test.dart; mobile/test/cash_sync_test.dart.

**Interfaces:** DatabaseHelper.saveCashSnapshot(CashSnapshot), getCashSnapshot(branchId); saveAuthorizedCashOperation(Map operation,{required String localRequestId}) -> Future<String>. saveOfflineSale acepta localRequestId estable y delega al guardado transaccional; firma/UUID los aporta la concesión SYNC. CashSaleService.saveDraft(...) devuelve UUID solo después de commit. Snapshot/operation usan siempre forScope(owner).

- [x] Pruebas SQLite de solicitud repetida, contenido distinto, concesión de tipo erróneo, stock agotado, fallo de insert y preservación de wallet/nonce; actualización histórica cubierta en E1.
- [x] Roja inicial por ausencia de `saveAuthorizedCashOperation`; dirigida verde posterior.
- [x] Reutilizar la migración 8 de E1 sin otra versión; `local_request_id` único nullable y tablas históricas preservadas.
- [x] Validación en centavos y transacción única para fila+concesión; deduplicación previa, owner, 24h, stock por variante menos operaciones propias desde snapshot.
- [x] Revisar sync: `syncBatchNow` revalida `expectedScope` y conserva mutex y resultados; el guardado de efectivo exige perfil vigente y solicitud estable.
- [x] Bloquear sucesor de efectivo rechazado hasta diseñar una nueva autorización atómica; nunca recrear automáticamente el cobro.
- [x] Suite móvil completa y análisis estático aprobados; cierre E2 local documentado. El commit/publicación quedan para E4 con pantalla y APK completos.

## E3 — Pantalla de caja sencilla

**Modificar:** mobile/lib/config/routes.dart; mobile/lib/main.dart; mobile/lib/screens/home/home_screen.dart; mobile/lib/screens/offline/offline_sync_screen.dart si necesita estado/recibo.

**Crear:** mobile/lib/screens/sales/cash_sale_screen.dart; mobile/test/cash_sale_screen_test.dart; mobile/test/cash_sale_access_test.dart.

**Interfaces:** AppRoutes.cashSale='/cash-sale'. CashSaleScreen consume CashSaleService, AuthService, ConnectivityService y OfflineSyncService. Estado de carrito exclusivo de caja; UUID de solicitud estable mientras se guarda/reintenta la misma venta. Después del commit mostrar recibo provisional y acceso a Sincronización. El servicio consulta las operaciones guardadas al reiniciar, no reconstruye cobros desde la memoria del widget.

- [x] Probar acceso directo de cliente/operador y formulario con fallo de guardado/reintento. Doble toque real y fallo físico de disco quedan para Android E4.
- [x] Ejecutar `cash_sale_screen_test.dart` y `cash_sale_access_test.dart`; el widget reveló un problema de preparación del doble de sesión, corregido en el test.
- [x] Añadir acceso Caja móvil solo con permiso y comprobarlo también dentro de la pantalla; preparación online y fecha de vencimiento.
- [x] Pantalla compacta con sucursal, búsqueda de variantes, cantidades, total, recibido, cambio y guardado. Recibo etiquetado provisional.
- [x] Conservar carrito y solicitud si falla el guardado, reiniciar solicitud tras éxito o cambio de datos; cambio de identidad limpia el borrador visible sin borrar SQLite.
- [x] Actualizar al reconectar y consultar estado de recibo; historial existente de sincronización accesible desde el comprobante.
- [x] Suite Flutter completa, análisis estático y cierre E3 local. Sin publicación incompleta de cobro.

## E4 — Aceptación, APK y publicación

**Crear:** mobile/integration_test/cash_sale_journey_test.dart; mobile/docs/efectivo/OPERACION.md; docs/auditoria_software/EFECTIVO_E4_MATRIZ.md, EFECTIVO_E4_CIERRE.md y EFECTIVO_ARTEFACTOS.json. El ensayo nativo en procesos separados cubre el reinicio previsto para `cash_restart_test.dart` con mayor fidelidad.

**Infraestructura QA:** extender scripts de raíz para base dedicada fashionstore_test_cash_mobile, API solo local y fixtures sintéticos de dos empresas/vendedores/clientes; nunca pytest destructivo sobre base de recorridos ni navegación. No usar secretos de proveedores para probar efectivo.

- [x] SQLite nativo entre preparación, guardado offline y sincronización en tres procesos Android separados con `--no-uninstall`. El AVD usa el almacenamiento Android real; teléfono físico pendiente de prueba manual.
- [x] APK QA 10.0.2.2 y AVD propio: vendedor de ambas empresas, preparación, red `none`, efectivo/cambio, cierre/reapertura offline y conciliación. Cliente sin acceso por pruebas de widget y permiso API; no se hizo un toque manual de cliente en AVD.
- [x] Reenvío del mismo UUID local y remoto, concurrencia backend y bloqueo de doble envío por UI; respuesta perdida representada por replay tras commit. Precio alterado y stock agotado rechazados por API+PG sin venta. Identidad, autorización e aislamiento cubiertos por suite dirigida; no se ensayó físicamente el doble toque de pantalla.
- [x] Suite Flutter completa 142, análisis estático y APK. Suite dirigida backend 37. Regresiones de billetera/reserva/sesión incluidas; prueba SQLite verifica saldo/nonce sin cambios por efectivo.
- [x] PostgreSQL por UUID/empresa/sucursal, importes, efectivo/cambio, detalle, stock y movimientos; Railway por recibo/entidad/stock. Evidencias sin credenciales.
- [x] Diffs y credenciales revisados; plan/spec/informes/manual copiados a mobile/docs/efectivo. Commit móvil `68be235` y push a main con preferencia GitHub D-blip-max; backend/web sin push ni cambios.
- [x] APK release `1.0.3+4` apuntando a Railway, hash y commit anotados, copia comprobada en Descargas. GitHub Release no disponible sin `gh`/complemento GitHub; se entrega la copia local accesible en esta computadora.
- [x] Railway con ModaExpress demo: nueva venta offline, cierre/reapertura Android, sincronización/replay, consulta de entidad y decremento de stock. Sin reset ni despliegue backend durante el recorrido.
- [x] E4 cerrada con evidencia real en API, PostgreSQL, AVD y Railway; teléfono físico y doble toque físico no certificados. Servicios/AVD QA propios detenidos al cierre; archivos del usuario conservados. Alta de empresas queda en su plan separado.

## Comandos de referencia

Desde mobile: flutter test test/cash_permissions_test.dart; flutter test test/cash_storage_test.dart test/cash_migration_test.dart; flutter test test/cash_sale_screen_test.dart; flutter test; flutter analyze; flutter build apk --release --dart-define=API_URL=https://proyecto-backend-vestidor-production.up.railway.app.

Comprobar ApiConfig actual y opciones de integration_test antes de fijar comandosAndroid. El APKQA usaAPI local distinta, nunca mezclarlo con elrelease. No sumar resultados de corridas solapadas ni usar las13pruebaswallet como prueba de efectivo.

## Estado

E1–E4 completas el 9/11/2026; móvil publicado en `68be235`, APK release `1.0.3+4` en Descargas. Ver `EFECTIVO_E4_CIERRE.md`, matriz y artefactos. Teléfono físico y doble toque físico no certificados.
