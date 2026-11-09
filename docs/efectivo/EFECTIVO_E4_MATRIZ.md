# Matriz E4 — aceptación de caja móvil en efectivo

9 de noviembre de 2026. Las cuentas, productos y ventas usados son datos demo. El alcance nativo se ensayó en un AVD propio; no se atribuye certificación a un teléfono físico.

| Control | Evidencia | Resultado |
|---|---|---|
| Acceso de cajero y separación de cliente | Login API local en UrbanStyle y ModaExpress; concesión y permiso `ventas.create`; widget bloquea cliente y operador | Aprobado |
| Preparación con red | Flutter nativo obtiene sucursal, catálogo, variante, precio, inventario y autorización; persiste instantánea por propietario | Aprobado en ambas empresas locales y ModaExpress remota |
| Guardado sin red | AVD con red predeterminada `none`; venta en efectivo con cambio; SQLite conserva UUID y pendiente | Aprobado en ambas empresas locales y ModaExpress remota |
| Cierre y reapertura | `integration_test` ejecutado en tres procesos Android separados con `--no-uninstall` | Aprobado; sesión y pendiente conservadas |
| Sincronización | Al reconectar, pendiente pasa a `CONFIRMADA`, guarda recibo y entidad; segunda sincronización no genera pendiente | Aprobado local y remoto |
| Conciliación PostgreSQL local | SQL por tenant/UUID: dos ventas confirmadas por empresa (API y Android), un detalle por venta, un movimiento y stock −1 por cada operación | Aprobado |
| Conciliación Railway | UUID `8513b2a5-ad83-48bc-b7ea-13bc52dba783`: recibo, venta, Bs 180/190/cambio 10, un detalle y stock −1; consulta HTTP independiente | Aprobado |
| Precio cambiado y stock agotado | Dos operaciones firmadas sobre API y PostgreSQL locales; conflicto o rechazo durable sin nueva venta | Aprobado |
| Reenvío y conflictos | Pruebas backend de replay concurrente, stock, permisos y alcance de empresa; API real local repite el mismo UUID | 37 pruebas dirigidas y ensayo API aprobados |
| Billetera, reservas y sesión | Suite Flutter completa, incluye regresiones existentes | 142 pruebas aprobadas |
| Análisis estático | `flutter analyze --no-pub` | Sin observaciones |
| APK release | `flutter build apk --release` apuntando a Railway; instalada y pantalla de login abierta en AVD | Aprobado |
| Teléfono Android físico | No ejecutado en esta aceptación | Pendiente de prueba manual |

La prueba remota no necesita un nuevo despliegue del backend: usa la API ya publicada. La APK final enlaza a esa API; su firma y ubicación se registran en `EFECTIVO_ARTEFACTOS.json`.
