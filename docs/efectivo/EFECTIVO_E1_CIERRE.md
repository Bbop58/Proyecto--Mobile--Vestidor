# Caja móvil en efectivo — E1, cierre local

9 de noviembre de 2026. Fase E1 de preparación terminada; E2–E4 siguen pendientes. No existe todavía una pantalla de cobro ni una venta en efectivo desde Flutter.

## Cambios

- El perfil móvil conserva los códigos de permiso recibidos del backend. Los perfiles antiguos carecen de permiso de caja hasta revalidarse; cliente, operador de plataforma y cuenta restringida no pueden preparar caja.
- La preparación exige sesión revalidada, capacidad offline, `ventas.create`, sucursal activa obtenida de la API, catálogo activo, stock positivo por sucursal/SKU/variante y una concesión `SYNC` con `VENTA_CONTADO_OFFLINE` para la misma empresa y usuario. No deduce permiso del nombre del rol.
- Guarda una instantánea versionada por sucursal en el SQLite del propietario, con vencimiento máximo de 24 horas o el vencimiento de la concesión, lo que ocurra primero. Una descarga fallida conserva la instantánea anterior. Una instantánea vencida o de otro propietario no se entrega.
- Migración SQLite 7→8 aditiva: `cash_snapshots`, `pending_operations.local_request_id` e índice único. Las bases históricas sin tabla de pendientes no intentan crear el índice sobre una tabla ausente. Billetera, nonce, órdenes y pendientes existentes siguen intactos.
- El lector anterior de inventario agrupado por sucursal sigue disponible para el comprador; caja usa lectura detallada separada. No hay cambios en backend, web, esquema PostgreSQL ni seeders.

## Verificación

- Pruebas rojas previas: método `hasPermission` ausente y versión SQLite esperada 8 frente a 7. Luego, `flutter test --no-pub`: 136 aprobadas. Se detectaron y corrigieron dos expectativas antiguas de versión 7 y el índice sobre una base v3 sin tabla `pending_operations`.
- Tras agregar dos casos de preparación, las tres pruebas dirigidas de caja: 9 aprobadas. Cubren perfil antiguo/inválido, sucursal e inventario, permisos/contrato, falta de concesión, reintento fallido, aislamiento por propietario y vencimiento. `flutter analyze --no-pub`: sin observaciones.
- Se revisó en código el contrato backend: `build_user_response` entrega permisos; seed admin/encargado/cajero incluye `ventas.create`, cliente no; las rutas de sucursales/productos exigen sus permisos y la concesión offline incluye el tipo de efectivo solo para `ventas.create`. No se hizo login HTTP real vendedor/cliente en E1; queda para la integración E4.

## Límites y siguiente fase

E1 solo prepara datos. No guarda una venta ni consume concesiones; esas transacciones pertenecen a E2. E3 añade pantalla y E4 verifica API/PostgreSQL/Android, construye APK y publica. No se hizo commit, push ni despliegue de una función incompleta. Los cambios generados por Flutter en registrantes Linux/macOS/Windows ya estaban presentes y se dejan fuera del alcance.
