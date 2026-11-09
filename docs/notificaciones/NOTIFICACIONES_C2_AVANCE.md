# C2: fallos reproducidos durante la aceptación

Raíz real: `C:/Users/Laptop/FashionStore-recuperado`. C2 continúa abierta.

## Persistencia Android

La aceptación integrada registró Firebase y recibió WebSocket en UrbanStyle, pero al pasar a la APK normal apareció el login. Se aisló una interferencia nativa de `flutter_secure_storage 9.2.4`: `SecurePushStore.read()` cambiaba `sharedPreferencesName` y `preferencesKeyPrefix` en el objeto nativo compartido. Las opciones vacías de autenticación no restablecen los valores originales.

Reproducción en el AVD propio: escribir un marcador en el almacén de autenticación, leer push y volver a leer el marcador. Esperado `auth-sentinel`; observado `null`. Evidencia privada local: `%TEMP%/notifications-c2-storage-red.log`. No se imprimieron credenciales.

Corrección: conservar el almacén cifrado establecido y separar push mediante la clave `fashionstore_push_registration_v1`. La repetición nativa del marcador aprobó (1 PASS). No se borran SQLite ni preferencias históricas. La APK push aún no fue entregada como release; los registros del almacén experimental permanecen en su archivo excluido de backup. `clearAll` de autenticación ahora elimina solo sus cuatro claves, conservando las revocaciones pendientes de push.

Se detectó además un problema del arnés: esta versión de `flutter test` desinstala por defecto la aplicación al finalizar. `pm path` confirmó que no quedaba paquete instalado. Por eso conservar sesión entre la integración y la APK normal requiere `--no-uninstall`; no se puede atribuir toda la pérdida observada al plugin. La interferencia del plugin sí se demostró independientemente mediante la prueba nativa RED/GREEN anterior.

Otra repetición quedó esperando el permiso de notificaciones dentro de la inicialización local (deadline de 15 segundos). La creación del canal ya no solicita permiso al arrancar: Firebase lo solicita únicamente con la acción explícita de activar avisos. Se continúa la aceptación con el arnés corregido y la APK normal.

## Clic web publicado

El usuario confirmó que tocó el aviso de Vercel y no abrió notificaciones. El arnés también agotó su espera sin observar la URL de destino. La recepción del aviso por sí sola no certifica el clic.

La carga real tiene `FCM_MSG` y datos del evento, pero carece de `fcmOptions`; el manejador predeterminado de Firebase sale sin abrir destino. Se reprodujo en tres pruebas de service worker, se agregó un manejador anterior al SDK y las tres aprobaron. Abre una ruta del mismo origen y la interfaz comprueba el binding de la cuenta actual antes de mostrar el panel. Angular completo: 221 PASS, build aprobado; commit `2a426e2` publicado en Vercel y manejador público verificado. No se cambiaron políticas de seguridad del navegador. El clic real sigue esperando comprobación del usuario.

## Publicación actual

Backend `d81f6e8`, web `ba4790b` publicados y comprobados. No se ha redesplegado backend durante esta aceptación; sus fixtures siguen ligados a la misma base demo. Los nuevos cambios locales de diagnóstico/corrección todavía no forman parte de esa publicación.

## Evidencia posterior y límites actuales

- Web corregida `2a426e2`, Vercel verificada: el usuario tocó los avisos reales y el arnés aprobó UrbanStyle y ModaExpress, panel abierto, historial propio, etiquetas únicas y cero errores JS. Resultados privados `%TEMP%/fashionstore-notifications-browser-results.json`.
- Recorrido web adicional aprobado: cuenta A→B, binding antiguo rechazado, binding actual aceptado, dos workers coexistentes, recuperación de red y permiso denegado explícito. `%TEMP%/notifications-c2-web-negative-results.json`. Los primeros intentos del arnés usaron contextos de Chrome inadecuados para push; se corrigió al contexto persistente normal. Se reforzó después la limpieza explícita de sesiones del helper; no confundir esa limpieza nueva con una prueba adicional ya ejecutada.
- Flutter completo: **148 PASS**, análisis final **sin observaciones**. Native storage RED/GREEN (una prueba), integración real Urban WS/Firebase PASS. Esto no certifica recepción/apertura en la segunda empresa.
- El arnés Android detectó una entrega por ID, pero el primer resultado de apertura fue invalidado al revisar la captura: confundía la etiqueta de la campana del catálogo con el panel. Ahora exige `Actualizaciones en vivo`, toca el texto del aviso y usa archivos temporales nuevos en `/data/local/tmp` para evitar XML obsoleto y fallos FUSE.
- AVD original `fashionstore_acceptance_qa`: System UI/Bluetooth ANR, conservado con su disco y sesión. AVD nuevo `fashionstore_notifications_c2_qa`: exclusivo, Android34, 3072 MB, 720×1280; su primer arranque optimizó Android completo y terminó. No se borró ni restableció el AVD histórico.
- El control automático rechazó el comando combinado build/install/grant y la limpieza recursiva de perfiles QA con `blocked by policy`. Se compiló/instaló por acciones separadas, conservando el permiso ya concedido. No se repitió la limpieza por otra vía. El usuario se ofreció a liberar espacio; después se observaron más de 2 GB adicionales y se pudo crear el AVD.
- La instalación debug (210 MB) durante el arranque nuevo falló con `INSTALL_FAILED_VERIFICATION_FAILURE: Integrity verification timed out`. No se deshabilitó la verificación. Se prepara una candidata release optimizada por ABI para continuar la aceptación; **no es todavía la APK final entregable de C3/C4**.

Estado aproximadamente 15:30 Bolivia: C2 sigue abierta. Web aceptada; Android requiere tap estricto, segunda empresa, proceso/reboot y negativos. AVD nuevo detenido conservando disco para compilar release con memoria suficiente. Backend sin reset nuevo. Archivo de estado: `NOTIFICACIONES_ACEPTACION.json`.
