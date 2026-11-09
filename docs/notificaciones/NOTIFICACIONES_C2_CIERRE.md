# C2 — Aceptación operativa de notificaciones

Fecha: 9/11/2026. Cierre del alcance básico priorizado por el usuario: notificaciones sencillas, visibles y funcionales en web y móvil.

## Aprobado

- **Web, ambas empresas:** WebSocket real, recepción FCM en segundo plano, clic real del usuario que abre el panel, historial propio y etiquetas únicas sin información privada en la pantalla bloqueada.
- **Web adicional:** cambio A→B rechaza el binding anterior y acepta el actual; workers PWA/FCM coexistentes; recuperación de red; permiso denegado explícito; cero errores JavaScript.
- **Android, UrbanStyle:** integración nativa de WebSocket/Firebase aprobada y usuario confirmó en teléfono que recibió el aviso y abrió Notificaciones.
- **Android, ModaExpress:** después de cambiar de cuenta, el usuario confirmó recepción, apertura y conservación de sesión al quitar la app de recientes y volverla a abrir.
- Comprobación final API: las dos reservas de prueba pertenecen a sus respectivas cuentas/empresas y están PREPARADA. Se conservan para demostración; no se hicieron compras ni cobros. Se cerraron solo las sesiones HTTP auxiliares, conservando la sesión del teléfono.

## Correcciones incluidas

1. Clic web explícito en el service worker: la carga FID recibida no incluía el enlace esperado por el manejador predeterminado. El destino es del mismo origen y se valida el binding de la cuenta actual.
2. Push Android usa una clave propia dentro del almacén seguro existente. Se reprodujo y corrigió que las opciones mutables de flutter_secure_storage 9.2.4 redirigían las lecturas de autenticación.
3. La limpieza de autenticación conserva las revocaciones pendientes de push. La preparación del canal Android no solicita permisos al arrancar; se solicitan al activar avisos.
4. Se corrigió el arnés para conservar datos con --no-uninstall y para no confundir la campana del catálogo con la pantalla de notificaciones.

## Límites de la evidencia

No se certificó un nuevo reinicio físico del teléfono ni se repitió cada caso extremo offline/permisos/revocación en él. Esos casos conservan sus pruebas automáticas y evidencia anterior; las confirmaciones físicas nuevas son recepción/apertura en ambas empresas y reapertura con sesión conservada en ModaExpress.

Los AVD propios fallaron en Android System UI/Bluetooth, incluido uno limpio. Se conservaron sus discos y se cerraron. El primer resultado de tap del arnés fue invalidado al revisar la captura; las confirmaciones del usuario en teléfono son la evidencia final de apertura.

Evidencia estructurada: NOTIFICACIONES_ACEPTACION.json. Los registros temporales y datos de acceso QA permanecen fuera de Git.
