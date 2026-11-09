# Caja móvil en efectivo

## Uso

1. Entra en la app con una cuenta de personal de la empresa que tenga `ventas.create` y la capacidad offline vigente.
2. Con Internet, abre **Caja móvil**, elige la sucursal y pulsa **Preparar caja con Internet**. Se guardan variantes, precios, existencias y autorizaciones para esa cuenta y sucursal. La preparación vence como máximo a las 24 horas; la app muestra la hora exacta.
3. Si se interrumpe Internet, selecciona prenda, talla, color y cantidad. Introduce el efectivo recibido; la pantalla calcula el total y el cambio.
4. Pulsa **Guardar venta pendiente** una vez. El comprobante es **provisional** hasta la confirmación central. Puedes cerrar o reiniciar la app: SQLite conserva la operación con su identificador.
5. Al volver la red, abre **Sincronización Offline** y verifica el estado y el recibo. La app también intenta sincronizar automáticamente. Si hay rechazo por existencias, precio, permiso o vigencia, conserva el registro para revisión; no entregues un recibo central inexistente.

## Alcance y controles

- Solo efectivo, una sucursal de la empresa autenticada. PayPal, tarjeta y billetera usan otros recorridos.
- El servidor comprueba de nuevo autorización, precio, stock, empresa, cajero y UUID. El mismo UUID se concilia una sola vez, aun si se pierde la respuesta y se reenvía.
- La venta no se contabiliza ni descuenta stock central hasta que el servidor confirma. El cambio mostrado es el dinero a devolver por el cajero en el momento del cobro local.
- Una sesión revocada o una autorización vencida impide nuevas ventas. Las pendientes permanecen en el dispositivo para revisión y sincronización con la identidad correcta.
- El inventario local procede de la preparación y puede quedar desactualizado. Una venta que agote o contradiga el stock central se rechaza sin generar una venta falsa.

## Comprobación de esta entrega

- APK QA en emulador Android con API y PostgreSQL descartables: preparación con red, guardado en modo avión, cierre del proceso, reapertura, sincronización y reenvío en UrbanStyle y ModaExpress.
- Pruebas del backend cubren replay, concurrencia, conflicto por stock y separación de empresas. La aceptación nativa no sustituye la prueba en teléfono físico.
- Los artefactos y el estado de publicación están en `EFECTIVO_E4_CIERRE.md` y `EFECTIVO_E4_MATRIZ.md` dentro de esta carpeta.
