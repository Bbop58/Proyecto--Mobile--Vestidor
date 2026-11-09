# Matriz de aceptación E1 — Caja móvil

| Control | Evidencia | Resultado |
|---|---|---|
| Perfil antiguo sin `permissions` | `cash_permissions_test.dart` | Sin acceso a caja |
| Permisos malformados | `cash_permissions_test.dart` | Perfil rechazado |
| Operador, cuenta restringida o sin `ventas.create` | `cash_preparation_test.dart` | Preparación bloqueada |
| Sucursal y variante exactas | `cash_preparation_test.dart` | Snapshot con sucursal, producto, SKU y variante |
| API rechaza o inventario incompleto | `cash_preparation_test.dart` | Sin snapshot nuevo |
| Sin concesión de efectivo | `cash_preparation_test.dart` | Preparación bloqueada |
| Fallo al renovar preparación | `cash_preparation_test.dart` | Snapshot previo conservado |
| Cambio de propietario y vencimiento | `cash_preparation_test.dart` | Snapshot oculto |
| Migración 7→8 | `cash_migration_test.dart` | Billetera, nonce y pendientes preservados |
| Migración desde v3 sin tabla de pendientes | `tenant_storage_test.dart` | Índice omitido de forma compatible |
| Regresión móvil | `flutter test --no-pub` | 136 aprobadas antes de dos casos adicionales; dirigida final 9 aprobadas |
| Análisis estático | `flutter analyze --no-pub` | Sin observaciones |
| Vendedor/cliente HTTP y Android real | E4 | Pendiente; no atribuido a E1 |
| Cobro local, cola y conciliación | E2–E4 | Pendiente |
