---
title: Instantáneas de API sin procesar
description: Exporta instantáneas JSON o NDJSON inmutables y versionadas de registros de Health Connect y de respuestas de los proveedores Fitbit, Oura, WHOOP y Withings, con manifiestos por tipo y sumas de comprobación.
---

<div class="docs-hero">
  <p class="docs-eyebrow">Android · exportación para archivo</p>
  <p>Raw API Snapshot es un producto de exportación independiente de Health.md for Android, pensado para flujos de migración y archivado: un artefacto JSON o NDJSON inmutable y versionado por cada rango seleccionado, que conserva los registros nativos.</p>
  <div class="docs-actions">
    <a class="docs-button" href="https://play.google.com/store/apps/details?id=com.healthmd.android" target="_blank" rel="noopener">Descargar en Google Play</a>
    <a class="docs-button-secondary" href="/es/docs/android/">Guía de la app para Android</a>
  </div>
</div>

## Qué es una instantánea sin procesar

Las exportaciones de compatibilidad convierten los registros de Health Connect en resúmenes diarios legibles de `HealthData`. Una instantánea sin procesar omite por completo esa conversión:

- **Las instantáneas de Health Connect** conservan todos los campos que expone la API fijada de AndroidX, incluidos la identidad y los metadatos nativos, las marcas de tiempo en nanosegundos, los desplazamientos de origen que admiten nulos, los valores enum sin procesar, las muestras anidadas, las etapas, las rutas y las estructuras de entrenamientos planificados.
- **Las instantáneas de Fitbit, Oura, WHOOP y Withings** conservan los bytes exactos de las respuestas correctas del proveedor y revelan la paginación del endpoint y la agregación en el servidor. Los proveedores no compatibles se informan en lugar de normalizarse o sustituirse silenciosamente por datos de Health Connect.
- Cada artefacto termina con un **manifiesto** con el estado, los problemas, los recuentos y las sumas de comprobación por tipo. Las exportaciones a carpeta también reciben un archivo adicional `.sha256`.

Una instantánea sin procesar es completa a nivel de API para la API fijada del proveedor en la app; no es una copia transaccional de la base de datos del proveedor. No puede recuperar registros inaccesibles, unidades originales que la API no expone, registros eliminados ni campos desconocidos para el SDK instalado.

## Vista previa antes del destino

Las instantáneas sin procesar pueden previsualizarse sin un destino configurado. La vista previa realiza la lectura nativa completa del proveedor en un almacenamiento privado sin copias de seguridad, mantiene en memoria solo un texto inicial y final acotado y elimina el artefacto temporal sin subir nada.

## Reglas de entrega

Las subidas de API sin procesar son deliberadamente más estrictas que las exportaciones de API de compatibilidad:

| Regla | Motivo |
|---|---|
| Solo HTTPS | El artefacto transmitido nunca viaja en texto sin cifrar |
| Redirecciones rechazadas | El artefacto y las credenciales nunca pueden reenviarse a otro origen |
| Encabezados de esquema, exportación y suma de comprobación | El endpoint receptor puede verificar qué aceptó |
| Artefacto privado temporal eliminado tras el intento | No queda ninguna copia en el dispositivo |

## Archivos incrementales

El backend `healthmd.raw-changes`, con versionado independiente, usa tokens de cambio y marcadores de eliminación de Health Connect para futuros flujos de archivado incremental, de modo que una instantánea completa no tenga que ser la única estrategia de archivado.

## Requisitos

- Health.md for Android con el producto Raw API Snapshot.
- Permisos de Health Connect para los tipos de registro seleccionados, o una cuenta conectada de Fitbit, Oura, WHOOP o Withings para instantáneas de proveedores.
- Un endpoint HTTPS si subes instantáneas; la exportación a carpeta local no tiene requisitos de transporte.

## Dónde saber más

- [Contrato de instantánea sin procesar v1](https://github.com/CodyBontecou/health-md/blob/main/apps/android/docs/export-contract/raw-snapshot-v1.md)
- [Contrato de registro sin procesar v1](https://github.com/CodyBontecou/health-md/blob/main/apps/android/docs/export-contract/raw-record-v1.md)
- [Contrato de cambios sin procesar v1](https://github.com/CodyBontecou/health-md/blob/main/apps/android/docs/export-contract/raw-changes-v1.md)
