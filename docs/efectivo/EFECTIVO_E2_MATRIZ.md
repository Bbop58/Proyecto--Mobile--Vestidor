# Matriz E2 — caja en efectivo

| Control | Resultado |
|---|---|
| Misma solicitud, mismo contenido | Una fila y el mismo UUID |
| Misma solicitud, contenido cambiado | Rechazo sin otro cobro |
| Insert SQLite abortado | Cero filas; concesión intacta |
| Concesión de reserva o ajena | Efectivo bloqueado |
| Sin stock o precio comprobado | Efectivo bloqueado; ninguna fila nueva |
| Billetera | Saldo y nonce intactos |
| Envío a `/sync/batch` | Reutiliza revalidación/mutex/outbox; integración real E4 |
| Sucesor de efectivo rechazado | Bloqueado; requiere revisión |
| Suite Flutter | 140 aprobadas |
| Análisis estático | Sin observaciones |
| UI, Android y servidor real | E3/E4 pendientes |
