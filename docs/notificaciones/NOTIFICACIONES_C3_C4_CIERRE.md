# C3/C4 — Validación, publicación y entrega

Fecha: 9/11/2026. Cierre operativo del alcance básico pedido por el usuario; no se amplían funciones ni entornos.

## C3: validación y APK

- Backend publicado `d81f6e8`: suite completa anterior **826 PASS**, con fuente final idéntica. Se retiró nuestra instrumentación temporal de diagnóstico; el repositorio backend quedó limpio, sin necesidad de otra ejecución completa ni despliegue/reset.
- Web: **221 PASS**, **3 pruebas del service worker PASS**, build producción aprobado. El commit posterior solo agrega un arnés de aceptación; no modifica la aplicación.
- Flutter: **148 PASS**, análisis final sin observaciones. Aislamiento del almacén seguro reproducido RED/GREEN en Android; integración nativa Urban WebSocket/Firebase aprobada.
- Release ARM64 y x64 compiladas correctamente en **1584,4 s**. Se conserva la versión existente **1.0.3+4** para entregar exactamente el binario probado, identificado además por SHA256.
- APK ARM64 probada en el teléfono: **20.625.883 bytes**, SHA256 `977579d815001c20422c7bff5872450ef510c560b9b8b1d5b755362ec8971d1f`.

## C4: publicación y aceptación

- Cuenta usada para los push: **D-blip-max**; sin cambiar autoría.
- Backend `d81f6e8cc9a04bb5e5bfea510ab8e15632b4a974`: health/ready **200**, base accesible y esquema compatible. Sin otro reset durante la aceptación del teléfono.
- Web implementación `2a426e2`, arnés publicado `339b24b`: Vercel **success**, despliegue `2RWHHvxT6ySU2LgYqnzoiYBJ6m4f`; manejador de clic público comprobado.
- Móvil implementación `63bcfb4629637c979042a0d6082a18839ece71ed` publicada, remoto main coincidente. Este cierre posterior modifica solo documentación.
- Confirmaciones físicas de ambas empresas y reapertura: ver NOTIFICACIONES_C2_CIERRE.md. No se requiere una nueva instalación para cambiar el nombre del archivo final: los bytes son los mismos que se probaron.

Entrega: `C:/Users/Laptop/Downloads/FashionStore-Notificaciones-1.0.3+4.apk`.

Se conservaron los generados desktop previamente modificados sin incluirlos en commits. AVD y PostgreSQL QA propios apagados; archivos y discos históricos conservados. No se cambiaron PayPal/Gemini/billetera ni se publicaron credenciales privadas. No iniciar otra ampliación automáticamente.
