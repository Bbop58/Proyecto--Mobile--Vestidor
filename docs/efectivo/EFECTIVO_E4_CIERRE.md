# Caja móvil en efectivo — E4, cierre de aceptación

9 de noviembre de 2026. La caja móvil permite al cajero autorizado preparar catálogo, precio, stock y concesiones con Internet; después registra una venta en efectivo sin red, conserva la operación y la sesión al cerrar la app, y sincroniza el mismo UUID al reconectar. El comprobante se indica como provisional hasta que el servidor confirme la venta. No se cambió el backend ni la web en esta fase.

## Pruebas ejecutadas

- Flutter: 142 pruebas unitarias y de widgets aprobadas; `flutter analyze --no-pub` sin observaciones. La compilación release de 56 429 160 bytes se instaló y abrió el login en el AVD. La variante QA se compiló por separado para la API local.
- Android, API y PostgreSQL locales: en UrbanStyle y ModaExpress se recorrieron preparación conectada, corte real de red, guardado SQLite, cierre de proceso, reapertura offline y sincronización tras recuperar Internet. `integration_test` ejecutó las tres etapas en procesos separados con `--no-uninstall`. SQL independiente encontró por empresa dos UUID confirmados (uno API y uno nativo), dos ventas, dos detalles y dos movimientos. Cada operación descontó una unidad; UrbanStyle registró Bs 106,25/116,25/cambio 10 y ModaExpress Bs 180/190/cambio 10. El reenvío del mismo UUID no creó otra venta.
- Backend dirigido sobre base QA separada: 37 pruebas aprobadas de sincronización, replay concurrente, alcance multiempresa, fallos atómicos y contratos. Dos ensayos HTTP adicionales rechazaron un precio cambiado como `CONFLICTO` y un stock agotado como `RECHAZADA_POR_STOCK`, sin crear venta.
- Android y Railway: ModaExpress preparó caja en la API publicada, guardó una venta sin red, reabrió la app, sincronizó y repitió sin duplicar. La API devolvió `CONFIRMADA`, el mismo UUID, recibo `VTA-OFF-20261109-9C0BB6` y entidad `49b07859-2713-4394-a1cd-938f6ae8eb93`. Una consulta HTTP independiente verificó venta en efectivo por Bs 180, recibido Bs 190, cambio Bs 10, un detalle de la variante vendida y stock de esa sucursal/variante reducido en una unidad. La venta remota utiliza datos demo.

## Correcciones surgidas durante la aceptación

- Se corrigió en login móvil una llamada a `setState` después de desechar el widget, observada durante el arranque frío del AVD.
- Flutter 3.47 generaba en release una referencia al plugin de pruebas excluido de esa compilación. Se añadió un adaptador Java vacío solo en `android/app/src/release`; la prueba de integración sigue usando el plugin real en debug. La APK release compiló y abrió en Android.
- El arnés nativo usa `--no-uninstall`: el modo estándar desinstala la app de prueba entre etapas y borra su SQLite, lo que habría invalidado la prueba de persistencia.

## Límites y entrega

Se probó en un emulador Android propio; falta la aceptación manual en un teléfono físico. La APK release se firma con la configuración debug actual del proyecto, apta para esta demostración, no para distribución en una tienda. La preparación offline caduca y el servidor vuelve a validar permiso, precio y existencias; si otro equipo vende la misma prenda mientras está desconectado, el conflicto queda pendiente de revisión y no se inventa una venta central. No se ejecutaron pagos PayPal ni se modificó la billetera. La operación remota demo queda en Railway hasta el siguiente reinicio de la base demo, conforme al acuerdo del proyecto.

La matriz está en `EFECTIVO_E4_MATRIZ.md`; el hash y la ruta de la APK están en `EFECTIVO_ARTEFACTOS.json`. El manual para el cajero y el contexto E1–E4 se copian al repositorio móvil.

## Publicación

El código de la app se envió a `main` del repositorio móvil en el commit `68be235`, con la preferencia GitHub `D-blip-max` configurada. Backend y web quedaron sin cambios. La APK `1.0.3+4` que apunta a Railway se copió a `C:/Users/Laptop/Downloads/FashionStore-Efectivo-Offline-1.0.3+4.apk`; su copia coincide byte a byte por SHA-256 con la compilación. No se creó un GitHub Release porque esta instalación no dispone del cliente `gh` ni del complemento GitHub. El archivo sí está disponible en Descargas de esta computadora.
