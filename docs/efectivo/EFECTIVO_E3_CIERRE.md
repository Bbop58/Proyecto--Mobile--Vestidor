# Caja móvil en efectivo — E3, cierre local

9 de noviembre de 2026. Pantalla Flutter integrada en la ruta `/cash-sale` y visible en Mi Perfil solo para cuentas de empresa con permiso `ventas.create`, capacidad offline activa y servicio sin restricción. La ruta vuelve a verificar el acceso al abrirse directamente.

La pantalla permite seleccionar una sucursal preparada, buscar una variante por nombre o SKU, elegir cantidades, consultar el stock local, introducir efectivo recibido y ver total/cambio. Con conexión prepara o renueva catálogo, stock y concesiones; sin conexión utiliza solo la instantánea vigente. El botón guarda una operación pendiente y muestra un comprobante explícitamente provisional con enlace a Sincronización Offline. Al reconectar actualiza la preparación y el estado del recibo. Si cambia la identidad, vacía el borrador visible y oculta los datos previos sin borrar las operaciones persistidas del propietario anterior.

El guardado mantiene el carrito y el identificador de solicitud ante un error; tras un éxito inicia una solicitud nueva. Mientras guarda deshabilita las acciones del formulario. Los rechazos de efectivo no generan automáticamente un nuevo cobro. No se tocó el carrito del comprador, la billetera ni los permisos de otros módulos.

## Verificación

- Widget de acceso directo: cliente y operador de plataforma bloqueados.
- Widget de formulario con SQLite FFI, instantánea preparada y doble de sincronización: selecciona variante, calcula Bs20 total/Bs30 recibido/Bs10 cambio; el error conserva carrito e importe; el reintento muestra comprobante provisional.
- `flutter test --no-pub`: 142 pruebas aprobadas, incluidas regresiones existentes de carrito, reservas, billetera y sesión. `flutter analyze --no-pub`: sin observaciones.

## Pendiente de E4

La prueba de widgets usa un doble de sincronización; no acredita todavía venta real, doble toque en Android, cierre/reinicio del proceso, PostgreSQL ni PayPal. E4 compilará APK QA, recorrerá ambas empresas y conciliará UUID, efectivo, stock y movimientos contra el servidor. No hay commit, push, despliegue ni APK publicados por E3.
