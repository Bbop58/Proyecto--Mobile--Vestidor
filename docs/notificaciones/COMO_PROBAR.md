# Probar las notificaciones

Backend publicado: `d81f6e8`. Web corregida: `2a426e2`.
Firebase: `fashionstore-14410`. No se necesita otro servicio ni otra clave.

## Android: recorrido mínimo

1. Instalar la APK ARM64 compilada para Railway conservando los datos de la aplicación.
2. Ingresar como cliente de una empresa y abrir **Notificaciones**.
3. Pulsar **Activar avisos del sistema** y aceptar el permiso de Android.
4. Con la aplicación abierta, preparar desde la web una reserva de ese cliente: el historial debe actualizarse en vivo.
5. Dejar la aplicación en segundo plano y preparar otra reserva: debe aparecer un aviso genérico de FashionStore en Android.
6. Tocar el texto del aviso: debe abrir el historial del cliente autenticado.
7. Repetir con la otra empresa.

Las cuentas sintéticas vigentes las genera `backend/scripts/verify_notifications_live.py`; se guardan fuera de Git en `%TEMP%/fashionstore-notifications-fixtures.json`. Un nuevo reset demo invalida esas cuentas. No desplegar backend durante el recorrido.

## Web

En Notificaciones, **En vivo** indica conexión WebSocket. **Activar avisos del sistema** habilita el aviso externo del navegador. El clic abre el panel autenticado; un binding antiguo de otra cuenta se rechaza.

La reserva registrada y la reserva preparada son dos eventos distintos. Sus dos avisos no son duplicados.

## Evidencia y límites

Web: ambas empresas, recepción/clic real, aislamiento, reconexión, permiso denegado y coexistencia PWA/FCM aprobados. Flutter: 148 pruebas completas y análisis sin observaciones; registro Firebase/WS Urban y aislamiento nativo del almacén seguro aprobados. La aceptación final del clic Android queda registrada en el cierre C2, no se presume por compilar la APK.

El emulador original y uno limpio presentaron fallos de Android System UI/Bluetooth; se conservaron sus discos y se optó por el teléfono para terminar el recorrido. No cambiar políticas de seguridad ni borrar datos para resolver esos fallos.

Para el arnés Android propio: `backend/.venv/Scripts/python.exe mobile/scripts/verify_android_notification.py --remote --company urbanstyle`. Solo admite los AVD propios identificados en el script. Si se prepara sesión mediante `flutter test`, usar **--no-uninstall** para conservarla.
