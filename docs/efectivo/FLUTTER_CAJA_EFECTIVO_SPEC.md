# Especificación — Efectivo offline en Flutter

Fecha: 8/11/2026. Estado: propuesta lista para implementación por fases; no implementada. Fuente: Examen Parcial-2 - Sistemas 2 - S2-2026 (6).pdf, puntos6.2–6.4 y7.2. Auditoría: docs/auditoria_software/REVISION_FLUTTER_EFECTIVO_Y_WALLET.md.

## Objetivo y recorrido

Personal de una empresa con permiso ventas.create abre **Caja móvil**, prepara su dispositivo con conexión y selecciona sucursal y variantes de su empresa. Sin conexión, añade cantidades, registra efectivo recibido y calcula cambio. Al guardar se confirma únicamente la escritura local y se entrega comprobante provisional. Cerrar o reiniciar no pierde esa operación. Al recuperar conexión se revalida identidad y se envía la misma operación al endpoint /sync/batch; queda confirmada con recibo central o rechazada/con conflicto y motivo visible.

El cliente conserva carrito, reservas y billetera. No se le permite declarar recepción de efectivo ni se convierte una compra de billetera en una venta de efectivo. Caja móvil es acceso por permiso, no por nombre de rol: admin/cajero/encargado solo si el servidor les otorgó ventas.create. El operador de plataforma no tiene caja. No se crea un rol nuevo.

## Alcance mínimo

Una pantalla dedicada y un servicio pequeño de caja. Catálogo propio con búsqueda por nombre/SKU, variantes activas y precio vigente descargado; selector de sucursal autorizada; carrito de caja separado del carrito del cliente; total, recibido, cambio; Guardar venta y comprobante provisional. Acceso a la pantalla de sincronización existente. Sin nuevos paneles, IA, promociones configurables, cupones, pago electrónico, liquidación de reservas ni formularios de clientes.

Cliente opcional se omite en la primera versión; la venta es a consumidor no identificado y no requiere descargar datos personales. Identidad del responsable y empresa derivadas de la sesión propia, nunca elegidas libremente. Sucursal debe pertenecer a esa empresa y estar dentro de lo autorizado por el backend. No se inventa una restricción a una sola sucursal si el contrato actual permite varias.

## Persistencia y preparación

Conservar nombre de archivo fashion_store_v2_<scope>.db y las tablas existentes; migración SQLite7→8 aditiva. Añadir cash_snapshots(branch_id PRIMARY KEY,owner TEXT NOT NULL,prepared_at TEXT NOT NULL,valid_until TEXT NOT NULL,payload_json TEXT NOT NULL). El payload versionado contiene catálogo mínimo/variantes, stock por variante y los permisos/sucursales necesarios para caja; nunca contraseñas, claves, tokens de sesión ni lista de clientes. pending_operations añade local_request_id con índice UNIQUE que admita NULL para filas históricas. No renombrar ni borrar billetera, concesiones, reservas u operaciones anteriores.

Una preparación completa requiere identidad confirmada online, ventas.create, offline habilitado y datos/stock/concesiones elegibles. La vigencia de caja es como máximo24h y se limita por concesiones; mostrar fecha y vencimiento. Una descarga fallida no sustituye un snapshot válido por uno parcial. Mantener la sesión móvil persistente existente: que venza la preparación bloquea nuevas ventas offline, no cierra sesión ni elimina pendientes.

Persistir permissions en sessionProfile y User de forma compatible: perfil histórico sin ese campo equivale a lista vacía, necesita revalidación para habilitar caja. No deducir privilegios por nombre/email. El backend ya entrega permisos mediante build_user_response; no modificar su esquema ni su contrato salvo evidencia indispensable.

El stock de caja debe conservar producto/variante/SKU/sucursal. No reutilizar como stock exacto el InventoryService actual que agrupa por sucursal: agregar consulta detallada con sucursal_id y correlación por SKU/variante, sin alterar el comportamiento del comprador. Desconocido no es cero y no autoriza venta. Restar las cantidades de ventas y reservas propias pendientes para evitar vender repetidamente la misma existencia conocida. Esto no garantiza stock global de equipos desconectados; el servidor decide al sincronizar.

## Guardado y autorización

Cada intento tiene local_request_id estable generado una sola vez. Validar cantidades enteras positivas, variantes activas, precios finitos y no negativos, total exacto, recibido finito >=total y cambio=recibido-total. Calcular en centavos; el API mantiene importes BOB con2decimales. No aceptar NaN/Infinity, montos negativos ni manipulación de total.

En una única transacción SQLite: comprobar solicitud anterior y su contenido inmutable; validar snapshot vigente/stock considerando pendientes; escoger concesión SYNC no vencida y consistente con tenant/actor/operation_id/kind VENTA_CONTADO_OFFLINE; insertar pending_operations con UUID de esa concesión y firma original; consumir concesión. Fallo revierte ambos cambios. Firma solo se verifica criptográficamente en backend; comprobaciones locales no conceden privilegios centrales. Si falta concesión no generar una operación sin autorización. Repetir el mismo local_request_id devuelve el mismo UUID sin consumir otra concesión; diferente contenido con el mismo request se rechaza.

No cambiar OfflineAuthorizationService.take usado por billetera/reserva de manera global sin regresión. Añadir vía atómica específica para efectivo reutilizando la tabla de concesiones. Online también puede usar la misma cola autorizada y autoenvío; si no puede prepararse, no anunciar guardado ni inventar venta. Se mantiene el comprobante como provisional hasta respuesta central.

## Reconciliación

Reutilizar OfflineSyncService y /sync/batch. Revalidar sesión antes de enviar; respetar mutex, propietario, UUID y payload originales. 0/timeout/5xx conservan pendientes y permiten reintento. 401/403 conservan operación y siguen las reglas actuales de sesión/restricción. Respuesta incompleta no borra ni confirma filas. Stock insuficiente/precio cambiado quedan visibles con motivo, sin venta central falsa. No incrementar saldo ni tocar nonce de wallet.

En la primera entrega la caja no introduce un nuevo botón de crear sucesores: revisar el botón de reintento existente; mantenerlo solo si valida estado central y consigue nueva concesión+UUID de forma atómica con supersedes_operation_id. Si no cumple, deshabilitarlo para efectivo mostrando revisión requerida. Nunca recrear automáticamente una venta tras respuesta perdida.

## Aceptación

Pruebas unitarias y widgets, SQLite real, reapertura en proceso independiente y Android/emulador con APK contra API/PostgreSQL QA. Preparar vendedor y cliente por empresa; ninguna operación cliente habilita efectivo. Dos empresas: un efectivo válido por empresa, recibido/cambio correctos, recibo central, decremento de stock exacto, replay sin otro efecto. Conflictos de stock y precio, permiso/grant vencidos, disco/cuota, doble pulsación, cambio de identidad y respuesta perdida. Regresión billetera/reservas/sesión obligatoria. Ninguna prueba con HTTP simulado acredita por sí sola el recorrido Android/API real.

No prometer cero errores absolutos. Cerrar contra matriz con resultados y limitaciones verificadas. Generar APK release para API publicada después de publicar únicamente repos que realmente cambien; no ofrecer APK apuntando a10.0.2.2 para teléfono físico.
